import Foundation

/// Pure state container for posture monitoring - no side effects, fully testable
struct PostureMonitoringState: Equatable {
    var consecutiveBadFrames: Int = 0
    var consecutiveGoodFrames: Int = 0
    var isCurrentlySlouching: Bool = false
    var isCurrentlyAway: Bool = false
    var badPostureStartTime: Date? = nil
    var postureWarningIntensity: CGFloat = 0

    mutating func reset() {
        consecutiveBadFrames = 0
        consecutiveGoodFrames = 0
        isCurrentlySlouching = false
        isCurrentlyAway = false
        badPostureStartTime = nil
        postureWarningIntensity = 0
    }
}

/// Configuration for posture detection thresholds
struct PostureConfig: Equatable {
    var frameThreshold: Int = 8
    var goodFrameThreshold: Int = 5
    var warningOnsetDelay: TimeInterval = 0
    var intensity: CGFloat = 1.0
}

/// Side effects that the engine requests but doesn't execute
enum PostureEngineEffect: Equatable {
    case updateUI
    case updateBlur
    case recordSlouchEvent
    case trackAnalytics(interval: TimeInterval, isSlouching: Bool)
}

/// Result of processing a posture reading
struct PostureReadingResult: Equatable {
    let newState: PostureMonitoringState
    let effects: [PostureEngineEffect]
}

/// Result of processing an away state change
struct AwayChangeResult: Equatable {
    let newState: PostureMonitoringState
    let shouldUpdateUI: Bool
}

/// Result of applying screen lock behavior to tracking state
struct ScreenLockTransitionResult: Equatable {
    let newState: AppState
    let stateBeforeLock: AppState?
}

/// Result of applying screen unlock behavior to tracking state
struct ScreenUnlockTransitionResult: Equatable {
    let newState: AppState
    let stateBeforeLock: AppState?
    let shouldRestartMonitoring: Bool
}

/// Result of processing an AirPods connection change
struct AirPodsConnectionTransitionResult: Equatable {
    let newState: AppState
    let shouldRestartMonitoring: Bool
}

/// Result of camera-connect handling
struct CameraConnectedTransitionResult: Equatable {
    let newState: AppState
    let shouldSelectAndStartMonitoring: Bool
}

enum CameraDisconnectedAction: Equatable {
    case none
    case syncUIOnly
    case switchToFallback(startMonitoring: Bool)
}

/// Result of camera-disconnect handling
struct CameraDisconnectedTransitionResult: Equatable {
    let newState: AppState
    let action: CameraDisconnectedAction
}

/// Result of handling display configuration changes.
struct DisplayConfigurationTransitionResult: Equatable {
    let newState: AppState
    let shouldSwitchToProfileCamera: Bool
    let shouldStartMonitoring: Bool
}

/// Result of switching tracking source manually.
struct SourceSwitchTransitionResult: Equatable {
    let newSource: TrackingSource
    let newState: AppState
    let didSwitchSource: Bool
    let shouldStartMonitoring: Bool
}

/// Result of attempting to start monitoring.
struct MonitoringStartTransitionResult: Equatable {
    let newState: AppState
    let shouldBeginMonitoringSession: Bool
}

/// Result of evaluating startup/initial-setup behavior.
struct InitialSetupTransitionResult: Equatable {
    let shouldApplyStartupCameraProfile: Bool
    let shouldStartMonitoring: Bool
    let shouldShowOnboarding: Bool
}

/// Result of automatic source resolution
struct SourceResolutionResult: Equatable {
    /// The source to activate, or nil to keep current
    let activeSource: TrackingSource?
    let newState: AppState
    let shouldStartMonitoring: Bool
}

/// Pure logic engine for posture monitoring - no side effects
struct PostureEngine {

    // MARK: - Automatic Source Resolution

    /// Resolves which source should be active in automatic mode.
    /// "Ready" means calibrated AND connected.
    static func resolveActiveSource(
        preferred: TrackingSource,
        currentActive: TrackingSource,
        currentState: AppState,
        preferredReadiness: TrackingSourceReadiness,
        fallbackReadiness: TrackingSourceReadiness,
        autoReturn: Bool
    ) -> SourceResolutionResult {
        let preferredReady = preferredReadiness.calibrated && preferredReadiness.connected
        let fallbackReady = fallbackReadiness.calibrated && fallbackReadiness.connected

        // Preferred is ready — use it
        if preferredReady {
            let shouldStart = currentActive != preferred || !currentState.isActive
            return SourceResolutionResult(
                activeSource: preferred,
                newState: .monitoring,
                shouldStartMonitoring: shouldStart
            )
        }

        // Preferred not ready, fallback is ready — use fallback
        if fallbackReady {
            let shouldStart = currentActive != preferred.other || !currentState.isActive
            return SourceResolutionResult(
                activeSource: preferred.other,
                newState: .monitoring,
                shouldStartMonitoring: shouldStart
            )
        }

        // Preferred connected but not calibrated, fallback not ready
        if preferredReadiness.connected && !preferredReadiness.calibrated {
            return SourceResolutionResult(
                activeSource: nil,
                newState: .paused(.noProfile),
                shouldStartMonitoring: false
            )
        }

        // Neither ready — pause with preferred's unavail reason
        return SourceResolutionResult(
            activeSource: nil,
            newState: unavailableState(for: preferred),
            shouldStartMonitoring: false
        )
    }

    // MARK: - Posture Reading Processing

    /// Process a posture reading and return new state + requested effects
    static func processReading(
        _ reading: PostureReading,
        state: PostureMonitoringState,
        config: PostureConfig,
        currentTime: Date = Date(),
        frameInterval: TimeInterval = 0.1
    ) -> PostureReadingResult {
        var newState = state
        var effects: [PostureEngineEffect] = []

        // Always track analytics
        effects.append(.trackAnalytics(interval: frameInterval, isSlouching: state.isCurrentlySlouching))

        if reading.isBadPosture {
            newState.consecutiveBadFrames += 1
            newState.consecutiveGoodFrames = 0

            if newState.consecutiveBadFrames >= config.frameThreshold {
                // Start tracking when bad posture began
                if newState.badPostureStartTime == nil {
                    newState.badPostureStartTime = currentTime
                }

                // Check onset delay
                let badStartTime = newState.badPostureStartTime ?? currentTime
                let elapsedTime = currentTime.timeIntervalSince(badStartTime)
                let onsetDelay = max(0, config.warningOnsetDelay)
                if elapsedTime >= onsetDelay {
                    // Transition to slouching if not already
                    if !newState.isCurrentlySlouching {
                        newState.isCurrentlySlouching = true
                        effects.append(.recordSlouchEvent)
                        effects.append(.updateUI)
                    }

                    // Calculate warning intensity
                    let rawIntensity = Double(config.intensity)
                    let intensity = rawIntensity > 0 ? rawIntensity : 1.0
                    let clampedSeverity = min(1.0, max(0.0, reading.severity))
                    let adjustedSeverity = pow(clampedSeverity, 1.0 / intensity)
                    newState.postureWarningIntensity = CGFloat(adjustedSeverity)
                }
            }
        } else {
            newState.consecutiveGoodFrames += 1
            newState.consecutiveBadFrames = 0
            newState.badPostureStartTime = nil
            newState.postureWarningIntensity = 0

            // Transition back to good posture
            if newState.consecutiveGoodFrames >= config.goodFrameThreshold && newState.isCurrentlySlouching {
                newState.isCurrentlySlouching = false
                effects.append(.updateUI)
            }
        }

        effects.append(.updateBlur)

        return PostureReadingResult(newState: newState, effects: effects)
    }

    // MARK: - Away State Processing

    /// Process an away state change
    static func processAwayChange(
        isAway: Bool,
        state: PostureMonitoringState
    ) -> AwayChangeResult {
        guard isAway != state.isCurrentlyAway else {
            return AwayChangeResult(newState: state, shouldUpdateUI: false)
        }

        var newState = state
        newState.isCurrentlyAway = isAway

        return AwayChangeResult(newState: newState, shouldUpdateUI: true)
    }

    // MARK: - State Machine Transitions

    /// Determine if a state transition should be allowed
    static func canTransition(from currentState: AppState, to newState: AppState) -> Bool {
        switch (currentState, newState) {
        case (.disabled, .monitoring),
             (.disabled, .paused),
             (.disabled, .calibrating),
             (.monitoring, .disabled),
             (.monitoring, .paused),
             (.monitoring, .calibrating),
             (.paused, .disabled),
             (.paused, .monitoring),
             (.paused, .calibrating),
             (.calibrating, .monitoring),
             (.calibrating, .paused),
             (.calibrating, .disabled):
            return true
        default:
            return currentState != newState
        }
    }

    /// Determine if the detector should be running for a given state
    static func shouldDetectorRun(for state: AppState, trackingSource: TrackingSource) -> Bool {
        switch state {
        case .calibrating, .monitoring:
            return true
        case .paused(let reason):
            // Keep AirPods detector running when paused due to removal
            // so we can detect when they're put back in ears
            if reason == .airPodsRemoved && trackingSource == .airpods {
                return true
            }
            return false
        case .disabled:
            return false
        }
    }

    /// Pause reason used when the current source is unavailable.
    static func unavailabilityPauseReason(for trackingSource: TrackingSource) -> PauseReason {
        switch trackingSource {
        case .camera:
            return .cameraDisconnected
        case .airpods:
            return .airPodsRemoved
        }
    }

    /// Pause state used when the current source is unavailable.
    static func unavailableState(for trackingSource: TrackingSource) -> AppState {
        .paused(unavailabilityPauseReason(for: trackingSource))
    }

    /// Determine the next state when enabling from disabled
    static func stateWhenEnabling(
        isCalibrated: Bool,
        detectorAvailable: Bool,
        trackingSource: TrackingSource
    ) -> AppState {
        if !isCalibrated {
            return .paused(.noProfile)
        } else if !detectorAvailable {
            return unavailableState(for: trackingSource)
        } else {
            return .monitoring
        }
    }

    /// Determine state when calibration authorization is denied.
    static func stateWhenCalibrationAuthorizationDenied(
        isCalibrated: Bool
    ) -> AppState {
        isCalibrated ? .monitoring : .paused(.noProfile)
    }

    /// Determine state when calibration authorization is granted.
    static func stateWhenCalibrationAuthorizationGranted() -> AppState {
        .calibrating
    }

    /// Determine state when calibration is cancelled.
    static func stateWhenCalibrationCancels(
        isCalibrated: Bool
    ) -> AppState {
        isCalibrated ? .monitoring : .paused(.noProfile)
    }

    /// Determine state when calibration completes successfully.
    static func stateWhenCalibrationCompletes() -> AppState {
        .monitoring
    }

    /// Determine state/effect outcome when monitoring is requested.
    static func stateWhenMonitoringStarts(
        isMarketingMode: Bool,
        trackingSource: TrackingSource,
        isCalibrated: Bool,
        isConnected: Bool
    ) -> MonitoringStartTransitionResult {
        if isMarketingMode {
            return MonitoringStartTransitionResult(
                newState: .monitoring,
                shouldBeginMonitoringSession: false
            )
        }

        guard isCalibrated else {
            return MonitoringStartTransitionResult(
                newState: .paused(.noProfile),
                shouldBeginMonitoringSession: false
            )
        }

        if trackingSource == .airpods && !isConnected {
            return MonitoringStartTransitionResult(
                newState: .paused(.airPodsRemoved),
                shouldBeginMonitoringSession: true
            )
        }

        return MonitoringStartTransitionResult(
            newState: .monitoring,
            shouldBeginMonitoringSession: true
        )
    }

    /// Determine state impact when pause-on-the-go setting changes.
    static func stateWhenPauseOnTheGoSettingChanges(
        currentState: AppState,
        isEnabled: Bool
    ) -> AppState {
        if !isEnabled, currentState == .paused(.onTheGo) {
            return .monitoring
        }
        return currentState
    }

    /// Determine startup behavior from current source/readiness context.
    static func stateWhenInitialSetupRuns(
        isMarketingMode: Bool,
        trackingSource: TrackingSource,
        hasCameraProfile: Bool,
        profileCameraAvailable: Bool,
        hasValidAirPodsCalibration: Bool
    ) -> InitialSetupTransitionResult {
        if isMarketingMode {
            return InitialSetupTransitionResult(
                shouldApplyStartupCameraProfile: false,
                shouldStartMonitoring: true,
                shouldShowOnboarding: false
            )
        }

        switch trackingSource {
        case .camera:
            let canStartCamera = hasCameraProfile && profileCameraAvailable
            return InitialSetupTransitionResult(
                shouldApplyStartupCameraProfile: canStartCamera,
                shouldStartMonitoring: canStartCamera,
                shouldShowOnboarding: !canStartCamera
            )
        case .airpods:
            return InitialSetupTransitionResult(
                shouldApplyStartupCameraProfile: false,
                shouldStartMonitoring: hasValidAirPodsCalibration,
                shouldShowOnboarding: !hasValidAirPodsCalibration
            )
        }
    }

    /// Determine lock behavior for the current state and source.
    /// Only states with active detector work are transitioned to screenLocked.
    static func stateWhenScreenLocks(
        currentState: AppState,
        trackingSource: TrackingSource,
        stateBeforeLock: AppState?
    ) -> ScreenLockTransitionResult {
        guard currentState != .disabled, currentState != .paused(.screenLocked) else {
            return ScreenLockTransitionResult(newState: currentState, stateBeforeLock: stateBeforeLock)
        }

        guard shouldDetectorRun(for: currentState, trackingSource: trackingSource) else {
            return ScreenLockTransitionResult(newState: currentState, stateBeforeLock: stateBeforeLock)
        }

        return ScreenLockTransitionResult(newState: .paused(.screenLocked), stateBeforeLock: currentState)
    }

    /// Determine unlock behavior based on captured pre-lock state.
    static func stateWhenScreenUnlocks(
        currentState: AppState,
        stateBeforeLock: AppState?
    ) -> ScreenUnlockTransitionResult {
        guard case .paused(.screenLocked) = currentState else {
            return ScreenUnlockTransitionResult(
                newState: currentState,
                stateBeforeLock: stateBeforeLock,
                shouldRestartMonitoring: false
            )
        }

        guard let previousState = stateBeforeLock else {
            return ScreenUnlockTransitionResult(
                newState: currentState,
                stateBeforeLock: nil,
                shouldRestartMonitoring: false
            )
        }

        return ScreenUnlockTransitionResult(
            newState: previousState,
            stateBeforeLock: nil,
            shouldRestartMonitoring: previousState == .monitoring
        )
    }

    /// Determine state impact of an AirPods in-ear connection change.
    static func stateWhenAirPodsConnectionChanges(
        currentState: AppState,
        trackingSource: TrackingSource,
        isConnected: Bool
    ) -> AirPodsConnectionTransitionResult {
        guard trackingSource == .airpods else {
            return AirPodsConnectionTransitionResult(newState: currentState, shouldRestartMonitoring: false)
        }

        if isConnected, currentState == .paused(.airPodsRemoved) {
            return AirPodsConnectionTransitionResult(newState: .monitoring, shouldRestartMonitoring: true)
        }

        if !isConnected, currentState == .monitoring {
            return AirPodsConnectionTransitionResult(newState: .paused(.airPodsRemoved), shouldRestartMonitoring: false)
        }

        return AirPodsConnectionTransitionResult(newState: currentState, shouldRestartMonitoring: false)
    }

    /// Determine state impact of a camera connect event.
    static func stateWhenCameraConnects(
        currentState: AppState,
        trackingSource: TrackingSource,
        hasMatchingProfileForConnectedCamera: Bool
    ) -> CameraConnectedTransitionResult {
        guard trackingSource == .camera else {
            return CameraConnectedTransitionResult(newState: currentState, shouldSelectAndStartMonitoring: false)
        }

        guard case .paused(let reason) = currentState else {
            return CameraConnectedTransitionResult(newState: currentState, shouldSelectAndStartMonitoring: false)
        }

        if hasMatchingProfileForConnectedCamera {
            return CameraConnectedTransitionResult(newState: .monitoring, shouldSelectAndStartMonitoring: true)
        }

        if reason == .cameraDisconnected {
            return CameraConnectedTransitionResult(newState: .paused(.noProfile), shouldSelectAndStartMonitoring: false)
        }

        return CameraConnectedTransitionResult(newState: currentState, shouldSelectAndStartMonitoring: false)
    }

    /// Determine state impact of a camera disconnect event.
    static func stateWhenCameraDisconnects(
        currentState: AppState,
        trackingSource: TrackingSource,
        disconnectedCameraIsSelected: Bool,
        hasFallbackCamera: Bool,
        fallbackMatchesProfile: Bool
    ) -> CameraDisconnectedTransitionResult {
        guard trackingSource == .camera else {
            return CameraDisconnectedTransitionResult(newState: currentState, action: .none)
        }

        guard disconnectedCameraIsSelected else {
            return CameraDisconnectedTransitionResult(newState: currentState, action: .syncUIOnly)
        }

        guard hasFallbackCamera else {
            return CameraDisconnectedTransitionResult(newState: .paused(.cameraDisconnected), action: .none)
        }

        if fallbackMatchesProfile {
            return CameraDisconnectedTransitionResult(
                newState: .monitoring,
                action: .switchToFallback(startMonitoring: true)
            )
        }

        return CameraDisconnectedTransitionResult(
            newState: .paused(.noProfile),
            action: .switchToFallback(startMonitoring: false)
        )
    }

    /// Determine state impact of a display configuration change.
    static func stateWhenDisplayConfigurationChanges(
        currentState: AppState,
        trackingSource: TrackingSource,
        pauseOnTheGoEnabled: Bool,
        isLaptopOnlyConfiguration: Bool,
        hasAnyCamera: Bool,
        hasMatchingProfileCamera: Bool,
        selectedCameraMatchesProfile: Bool
    ) -> DisplayConfigurationTransitionResult {
        guard currentState != .disabled else {
            return DisplayConfigurationTransitionResult(
                newState: currentState,
                shouldSwitchToProfileCamera: false,
                shouldStartMonitoring: false
            )
        }

        if pauseOnTheGoEnabled && isLaptopOnlyConfiguration {
            return DisplayConfigurationTransitionResult(
                newState: .paused(.onTheGo),
                shouldSwitchToProfileCamera: false,
                shouldStartMonitoring: false
            )
        }

        guard trackingSource == .camera else {
            return DisplayConfigurationTransitionResult(
                newState: currentState,
                shouldSwitchToProfileCamera: false,
                shouldStartMonitoring: false
            )
        }

        guard hasAnyCamera else {
            return DisplayConfigurationTransitionResult(
                newState: .paused(.cameraDisconnected),
                shouldSwitchToProfileCamera: false,
                shouldStartMonitoring: false
            )
        }

        if hasMatchingProfileCamera {
            return DisplayConfigurationTransitionResult(
                newState: .monitoring,
                shouldSwitchToProfileCamera: !selectedCameraMatchesProfile,
                shouldStartMonitoring: true
            )
        }

        return DisplayConfigurationTransitionResult(
            newState: .paused(.noProfile),
            shouldSwitchToProfileCamera: false,
            shouldStartMonitoring: false
        )
    }

    /// Determine state impact when user changes selected camera in settings.
    static func stateWhenCameraSelectionChanges(
        currentState: AppState,
        trackingSource: TrackingSource
    ) -> AppState {
        guard trackingSource == .camera else { return currentState }
        return .paused(.noProfile)
    }

    /// Determine state impact when user manually switches tracking source.
    static func stateWhenSwitchingTrackingSource(
        currentState: AppState,
        currentSource: TrackingSource,
        newSource: TrackingSource,
        isNewSourceCalibrated: Bool
    ) -> SourceSwitchTransitionResult {
        guard newSource != currentSource else {
            return SourceSwitchTransitionResult(
                newSource: currentSource,
                newState: currentState,
                didSwitchSource: false,
                shouldStartMonitoring: false
            )
        }

        let newState: AppState = isNewSourceCalibrated ? .monitoring : .paused(.noProfile)
        return SourceSwitchTransitionResult(
            newSource: newSource,
            newState: newState,
            didSwitchSource: true,
            shouldStartMonitoring: isNewSourceCalibrated
        )
    }
}
