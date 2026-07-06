import Foundation
import ComposableArchitecture

enum TrackingMode: String, Equatable, Codable {
    case manual
    case automatic
}

struct TrackingSourceReadiness: Equatable {
    var permissionGranted: Bool = false
    var connected: Bool = false
    var calibrated: Bool = false
    var available: Bool = false
}

struct TrackingFeature: Reducer {
    enum CameraSwitchIntent: Equatable {
        case matchingProfile(ProfileData? = nil)
        case fallback(cameraID: String? = nil, profile: ProfileData? = nil)
        case selectedCamera
    }

    // Observer/testing surface for runtime calls.
    enum EffectIntent: Equatable {
        case startMonitoring
        case beginMonitoringSession
        case applyStartupCameraProfile(ProfileData? = nil)
        case showOnboarding
        case switchCamera(CameraSwitchIntent)
        case syncUI
        case updateBlur
        case trackAnalytics(interval: TimeInterval, isSlouching: Bool)
        case recordSlouchEvent
        case stopDetector(TrackingSource)
        case persistTrackingSource
        case showCalibrationPermissionDeniedAlert
        case openPrivacySettings
        case showCameraCalibrationRetryAlert(message: String?)
        case retryCalibration
    }

    struct State: Equatable {
        var appState: AppState = .disabled

        var trackingMode: TrackingMode = .manual
        var manualSource: TrackingSource = .camera
        var preferredSource: TrackingSource = .camera
        var autoReturnEnabled: Bool = true
        var activeSource: TrackingSource = .camera

        var cameraReadiness = TrackingSourceReadiness()
        var airPodsReadiness = TrackingSourceReadiness()

        var stateBeforeLock: AppState?
        var monitoringState = PostureMonitoringState()
        var postureConfig = PostureConfig()
        var lastPostureReadingTime: Date?

        init(
            appState: AppState = .disabled,
            trackingMode: TrackingMode = .manual,
            manualSource: TrackingSource = .camera,
            preferredSource: TrackingSource = .camera,
            autoReturnEnabled: Bool = true,
            activeSource: TrackingSource? = nil,
            cameraReadiness: TrackingSourceReadiness = TrackingSourceReadiness(),
            airPodsReadiness: TrackingSourceReadiness = TrackingSourceReadiness(),
            stateBeforeLock: AppState? = nil,
            monitoringState: PostureMonitoringState = PostureMonitoringState(),
            postureConfig: PostureConfig = PostureConfig(),
            lastPostureReadingTime: Date? = nil
        ) {
            self.appState = appState
            self.trackingMode = trackingMode
            self.manualSource = manualSource
            self.preferredSource = preferredSource
            self.autoReturnEnabled = autoReturnEnabled
            self.activeSource = activeSource ?? manualSource
            self.cameraReadiness = cameraReadiness
            self.airPodsReadiness = airPodsReadiness
            self.stateBeforeLock = stateBeforeLock
            self.monitoringState = monitoringState
            self.postureConfig = postureConfig
            self.lastPostureReadingTime = lastPostureReadingTime
        }

        func readiness(for source: TrackingSource) -> TrackingSourceReadiness {
            switch source {
            case .camera: return cameraReadiness
            case .airpods: return airPodsReadiness
            }
        }

        var fallbackSource: TrackingSource {
            preferredSource == .camera ? .airpods : .camera
        }

        var isOnFallback: Bool {
            trackingMode == .automatic && activeSource != preferredSource
        }
    }

    enum Action: Equatable {
        case appLaunched
        case setAppState(AppState)
        case toggleEnabled(
            trackingSource: TrackingSource,
            isCalibrated: Bool,
            detectorAvailable: Bool
        )
        case setTrackingMode(TrackingMode)
        case setManualSource(TrackingSource)
        case setPreferredSource(TrackingSource)
        case setAutoReturnEnabled(Bool)
        case setPostureConfiguration(intensity: Double, warningOnsetDelay: TimeInterval)
        case pauseOnTheGoSettingChanged(isEnabled: Bool)
        case postureReadingReceived(PostureReading, isMarketingMode: Bool)
        case awayStateChanged(Bool, isMarketingMode: Bool)
        case initialSetupEvaluated(
            isMarketingMode: Bool,
            hasCameraProfile: Bool,
            profileCameraAvailable: Bool,
            hasValidAirPodsCalibration: Bool,
            cameraProfile: ProfileData? = nil
        )
        case startMonitoringRequested(
            isMarketingMode: Bool,
            trackingSource: TrackingSource,
            isCalibrated: Bool,
            isConnected: Bool
        )
        case airPodsConnectionChanged(Bool)
        case cameraConnected(hasMatchingProfile: Bool, matchingProfile: ProfileData? = nil)
        case cameraDisconnected(
            disconnectedCameraIsSelected: Bool,
            hasFallbackCamera: Bool,
            fallbackHasMatchingProfile: Bool,
            fallbackCameraID: String? = nil,
            fallbackProfile: ProfileData? = nil
        )
        case calibrationAuthorizationDenied(isCalibrated: Bool)
        case calibrationOpenSettingsRequested
        case calibrationRetryRequested
        case calibrationAuthorizationGranted
        case calibrationStartFailed(errorMessage: String?)
        case runtimeDetectorStartFailed(trackingSource: TrackingSource)
        case calibrationCancelled(isCalibrated: Bool)
        case calibrationCompleted(source: TrackingSource)
        case screenLocked
        case screenUnlocked
        case displayConfigurationChanged(
            pauseOnTheGoEnabled: Bool,
            isLaptopOnlyConfiguration: Bool,
            hasAnyCamera: Bool,
            hasMatchingProfileCamera: Bool,
            selectedCameraMatchesProfile: Bool,
            matchingProfile: ProfileData? = nil
        )
        case cameraSelectionChanged
        case switchTrackingSource(TrackingSource, isNewSourceCalibrated: Bool)
        case sourceReadinessChanged(source: TrackingSource, readiness: TrackingSourceReadiness)
    }

    @Dependency(\.trackingRuntime) var trackingRuntime

    private func perform(_ intents: [EffectIntent]) -> Effect<Action> {
        guard !intents.isEmpty else { return .none }
        return .run { _ in
            for intent in intents {
                await trackingRuntime.perform(intent)
            }
        }
    }

    private func perform(_ intents: EffectIntent...) -> Effect<Action> {
        perform(intents)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            let previousAppState = state.appState

            func finish(_ effect: Effect<Action> = .none) -> Effect<Action> {
                if previousAppState.isActive, !state.appState.isActive {
                    state.monitoringState.reset()
                    state.lastPostureReadingTime = nil
                }
                return effect
            }

            switch action {
            case .appLaunched:
                return finish()

            case .setAppState(let appState):
                state.appState = appState
                return finish()

            case let .toggleEnabled(trackingSource, isCalibrated, detectorAvailable):
                state.manualSource = trackingSource
                state.activeSource = trackingSource
                if state.appState == .disabled {
                    state.appState = PostureEngine.stateWhenEnabling(
                        isCalibrated: isCalibrated,
                        detectorAvailable: detectorAvailable,
                        trackingSource: trackingSource
                    )
                    if state.appState == .monitoring {
                        return finish(perform(.startMonitoring))
                    }
                } else {
                    state.appState = .disabled
                }
                return finish()

            case .setTrackingMode(let mode):
                state.trackingMode = mode
                if mode == .automatic {
                    return finish(resolveAutomaticSource(&state))
                }
                // Switching back to manual: activeSource follows manualSource
                let previousSource = state.activeSource
                state.activeSource = state.manualSource
                let sourceChanged = state.activeSource != previousSource
                if sourceChanged && state.appState == .monitoring {
                    return finish(perform(.beginMonitoringSession))
                }
                return finish()

            case .setManualSource(let source):
                let previousSource = state.activeSource
                state.manualSource = source
                state.activeSource = source
                if state.activeSource != previousSource && state.appState == .monitoring {
                    return finish(perform(.beginMonitoringSession))
                }
                return finish()

            case .setPreferredSource(let source):
                state.preferredSource = source
                if state.trackingMode == .automatic {
                    return finish(resolveAutomaticSource(&state))
                }
                return finish()

            case .setAutoReturnEnabled(let enabled):
                state.autoReturnEnabled = enabled
                return finish()

            case let .setPostureConfiguration(intensity, warningOnsetDelay):
                state.postureConfig.intensity = CGFloat(intensity)
                state.postureConfig.warningOnsetDelay = warningOnsetDelay
                return finish()

            case .pauseOnTheGoSettingChanged(let isEnabled):
                state.appState = PostureEngine.stateWhenPauseOnTheGoSettingChanges(
                    currentState: state.appState,
                    isEnabled: isEnabled
                )
                return finish()

            case let .postureReadingReceived(reading, isMarketingMode):
                guard state.appState == .monitoring else { return finish() }

                if isMarketingMode {
                    state.monitoringState.isCurrentlySlouching = false
                    state.monitoringState.postureWarningIntensity = 0
                    state.monitoringState.consecutiveBadFrames = 0
                    return finish(perform(.syncUI, .updateBlur))
                }

                let actualElapsed: TimeInterval?
                if let last = state.lastPostureReadingTime {
                    let raw = reading.timestamp.timeIntervalSince(last)
                    actualElapsed = min(max(0, raw), 2.0)
                } else {
                    actualElapsed = nil
                }
                state.lastPostureReadingTime = reading.timestamp

                let result = PostureEngine.processReading(
                    reading,
                    state: state.monitoringState,
                    config: state.postureConfig,
                    currentTime: reading.timestamp,
                    frameInterval: actualElapsed ?? 0
                )
                state.monitoringState = result.newState

                var intents: [EffectIntent] = []
                for effect in result.effects {
                    switch effect {
                    case .trackAnalytics(let interval, let isSlouching):
                        if actualElapsed != nil {
                            intents.append(.trackAnalytics(interval: interval, isSlouching: isSlouching))
                        }
                    case .recordSlouchEvent:
                        intents.append(.recordSlouchEvent)
                    case .updateUI:
                        intents.append(.syncUI)
                    case .updateBlur:
                        intents.append(.updateBlur)
                    }
                }
                return finish(perform(intents))

            case let .awayStateChanged(isAway, isMarketingMode):
                guard state.appState == .monitoring, !isMarketingMode else { return finish() }

                let result = PostureEngine.processAwayChange(
                    isAway: isAway,
                    state: state.monitoringState
                )
                state.monitoringState = result.newState

                guard result.shouldUpdateUI else { return finish() }
                return finish(perform(.syncUI, .updateBlur))

            case let .initialSetupEvaluated(
                isMarketingMode,
                hasCameraProfile,
                profileCameraAvailable,
                hasValidAirPodsCalibration,
                cameraProfile
            ):
                let result = PostureEngine.stateWhenInitialSetupRuns(
                    isMarketingMode: isMarketingMode,
                    trackingSource: state.activeSource,
                    hasCameraProfile: hasCameraProfile,
                    profileCameraAvailable: profileCameraAvailable,
                    hasValidAirPodsCalibration: hasValidAirPodsCalibration
                )

                var intents: [EffectIntent] = []
                if result.shouldApplyStartupCameraProfile {
                    intents.append(.applyStartupCameraProfile(cameraProfile))
                }
                if result.shouldStartMonitoring {
                    intents.append(.startMonitoring)
                }
                if result.shouldShowOnboarding {
                    intents.append(.showOnboarding)
                }
                return finish(perform(intents))

            case let .startMonitoringRequested(isMarketingMode, trackingSource, isCalibrated, isConnected):
                state.manualSource = trackingSource
                state.activeSource = trackingSource
                state.lastPostureReadingTime = nil
                let result = PostureEngine.stateWhenMonitoringStarts(
                    isMarketingMode: isMarketingMode,
                    trackingSource: trackingSource,
                    isCalibrated: isCalibrated,
                    isConnected: isConnected
                )
                state.appState = result.newState
                if result.shouldBeginMonitoringSession {
                    return finish(perform(.beginMonitoringSession))
                }
                return finish()

            case .airPodsConnectionChanged(let isConnected):
                state.airPodsReadiness.connected = isConnected
                if state.trackingMode == .automatic, state.appState != .disabled {
                    return finish(resolveAutomaticSource(&state))
                }
                let result = PostureEngine.stateWhenAirPodsConnectionChanges(
                    currentState: state.appState,
                    trackingSource: state.activeSource,
                    isConnected: isConnected
                )
                state.appState = result.newState
                if result.shouldRestartMonitoring {
                    return finish(perform(.startMonitoring))
                }
                return finish()

            case .cameraConnected(let hasMatchingProfile, let matchingProfile):
                state.cameraReadiness.connected = true
                if hasMatchingProfile {
                    state.cameraReadiness.calibrated = true
                }
                if state.trackingMode == .automatic, state.appState != .disabled {
                    return finish(resolveAutomaticSource(&state))
                }
                let previousState = state.appState
                let result = PostureEngine.stateWhenCameraConnects(
                    currentState: state.appState,
                    trackingSource: state.activeSource,
                    hasMatchingProfileForConnectedCamera: hasMatchingProfile
                )
                state.appState = result.newState

                if result.shouldSelectAndStartMonitoring {
                    return finish(perform(.switchCamera(.matchingProfile(matchingProfile)), .startMonitoring))
                }

                if result.newState == previousState {
                    return finish(perform(.syncUI))
                }
                return finish()

            case .cameraDisconnected(
                let disconnectedCameraIsSelected,
                let hasFallbackCamera,
                let fallbackHasMatchingProfile,
                let fallbackCameraID,
                let fallbackProfile
            ):
                if disconnectedCameraIsSelected {
                    state.cameraReadiness.connected = hasFallbackCamera
                }
                if state.trackingMode == .automatic, state.appState != .disabled {
                    return finish(resolveAutomaticSource(&state))
                }
                let result = PostureEngine.stateWhenCameraDisconnects(
                    currentState: state.appState,
                    trackingSource: state.activeSource,
                    disconnectedCameraIsSelected: disconnectedCameraIsSelected,
                    hasFallbackCamera: hasFallbackCamera,
                    fallbackMatchesProfile: fallbackHasMatchingProfile
                )
                state.appState = result.newState

                switch result.action {
                case .none:
                    return finish()
                case .syncUIOnly:
                    return finish(perform(.syncUI))
                case .switchToFallback(let startMonitoring):
                    var intents: [EffectIntent] = [
                        .switchCamera(.fallback(cameraID: fallbackCameraID, profile: fallbackProfile))
                    ]
                    if startMonitoring {
                        intents.append(.startMonitoring)
                    }
                    return finish(perform(intents))
                }

            case .calibrationAuthorizationDenied(let isCalibrated):
                state.appState = PostureEngine.stateWhenCalibrationAuthorizationDenied(
                    isCalibrated: isCalibrated
                )
                return finish(perform(.showCalibrationPermissionDeniedAlert))

            case .calibrationOpenSettingsRequested:
                return finish(perform(.openPrivacySettings))

            case .calibrationRetryRequested:
                return finish(perform(.retryCalibration))

            case .calibrationAuthorizationGranted:
                state.appState = PostureEngine.stateWhenCalibrationAuthorizationGranted()
                return finish()

            case .calibrationStartFailed(let errorMessage):
                state.appState = PostureEngine.unavailableState(for: state.activeSource)
                if state.activeSource == .camera {
                    return finish(perform(.showCameraCalibrationRetryAlert(message: errorMessage)))
                }
                return finish()

            case .runtimeDetectorStartFailed(let trackingSource):
                state.manualSource = trackingSource
                state.activeSource = trackingSource
                state.appState = PostureEngine.unavailableState(for: trackingSource)
                return finish()

            case .calibrationCancelled(let isCalibrated):
                state.appState = PostureEngine.stateWhenCalibrationCancels(
                    isCalibrated: isCalibrated
                )
                if isCalibrated {
                    return finish(perform(.startMonitoring))
                }
                return finish()

            case .calibrationCompleted(let source):
                state.monitoringState.reset()
                state.lastPostureReadingTime = nil
                // Update calibrated flag for the source that was just calibrated
                switch source {
                case .camera: state.cameraReadiness.calibrated = true
                case .airpods: state.airPodsReadiness.calibrated = true
                }
                if state.trackingMode == .automatic {
                    return finish(resolveAutomaticSource(&state))
                }
                state.appState = PostureEngine.stateWhenCalibrationCompletes()
                return finish(perform(.startMonitoring))

            case .screenLocked:
                let result = PostureEngine.stateWhenScreenLocks(
                    currentState: state.appState,
                    trackingSource: state.activeSource,
                    stateBeforeLock: state.stateBeforeLock
                )
                state.appState = result.newState
                state.stateBeforeLock = result.stateBeforeLock
                return finish()

            case .screenUnlocked:
                let result = PostureEngine.stateWhenScreenUnlocks(
                    currentState: state.appState,
                    stateBeforeLock: state.stateBeforeLock
                )
                state.appState = result.newState
                state.stateBeforeLock = result.stateBeforeLock
                if result.shouldRestartMonitoring {
                    return finish(perform(.startMonitoring))
                }
                return finish()

            case let .displayConfigurationChanged(
                pauseOnTheGoEnabled,
                isLaptopOnlyConfiguration,
                hasAnyCamera,
                hasMatchingProfileCamera,
                selectedCameraMatchesProfile,
                matchingProfile
            ):
                let result = PostureEngine.stateWhenDisplayConfigurationChanges(
                    currentState: state.appState,
                    trackingSource: state.activeSource,
                    pauseOnTheGoEnabled: pauseOnTheGoEnabled,
                    isLaptopOnlyConfiguration: isLaptopOnlyConfiguration,
                    hasAnyCamera: hasAnyCamera,
                    hasMatchingProfileCamera: hasMatchingProfileCamera,
                    selectedCameraMatchesProfile: selectedCameraMatchesProfile
                )
                state.appState = result.newState

                var intents: [EffectIntent] = []
                if result.shouldSwitchToProfileCamera {
                    intents.append(.switchCamera(.matchingProfile(matchingProfile)))
                }
                if result.shouldStartMonitoring {
                    intents.append(.startMonitoring)
                }
                return finish(perform(intents))

            case .cameraSelectionChanged:
                state.appState = PostureEngine.stateWhenCameraSelectionChanges(
                    currentState: state.appState,
                    trackingSource: state.activeSource
                )
                if state.activeSource == .camera {
                    return finish(perform(.switchCamera(.selectedCamera)))
                }
                return finish()

            case .switchTrackingSource(let newSource, let isNewSourceCalibrated):
                let previousSource = state.activeSource
                let result = PostureEngine.stateWhenSwitchingTrackingSource(
                    currentState: state.appState,
                    currentSource: previousSource,
                    newSource: newSource,
                    isNewSourceCalibrated: isNewSourceCalibrated
                )

                state.manualSource = result.newSource
                state.activeSource = result.newSource
                state.appState = result.newState

                var intents: [EffectIntent] = []
                if result.didSwitchSource {
                    intents.append(.stopDetector(previousSource))
                    intents.append(.persistTrackingSource)
                }
                if result.shouldStartMonitoring {
                    intents.append(.startMonitoring)
                }
                return finish(perform(intents))

            case .sourceReadinessChanged(let source, let readiness):
                switch source {
                case .camera: state.cameraReadiness = readiness
                case .airpods: state.airPodsReadiness = readiness
                }
                if state.trackingMode == .automatic, state.appState != .disabled {
                    return finish(resolveAutomaticSource(&state))
                }
                return finish()
            }
        }
    }

    // MARK: - Automatic Mode Source Resolution

    private func resolveAutomaticSource(_ state: inout State) -> Effect<Action> {
        let previousSource = state.activeSource
        let previousAppState = state.appState
        let prefReadiness = state.readiness(for: state.preferredSource)
        let fbReadiness = state.readiness(for: state.fallbackSource)
        let result = PostureEngine.resolveActiveSource(
            preferred: state.preferredSource,
            currentActive: state.activeSource,
            currentState: state.appState,
            preferredReadiness: prefReadiness,
            fallbackReadiness: fbReadiness,
            autoReturn: state.autoReturnEnabled
        )

        state.activeSource = result.activeSource ?? previousSource
        state.appState = result.newState

        let sourceChanged = state.activeSource != previousSource
        let needsBeginMonitoring = result.newState == .monitoring
            && (sourceChanged || previousAppState != .monitoring)
        let needsStopOld = sourceChanged && previousAppState.isActive

        guard sourceChanged || needsBeginMonitoring || result.newState != previousAppState else {
            return .none
        }

        // Don't call startMonitoring() here — it sends .startMonitoringRequested which
        // overwrites activeSource with manualSource, causing a loop. The detector switch
        // is handled synchronously by applyTrackingStoreTransition via syncDetectorToState.
        // We call beginMonitoringSession to set up calibration data on the new detector.
        var intents: [EffectIntent] = []
        if needsStopOld {
            intents.append(.stopDetector(previousSource))
        }
        if needsBeginMonitoring {
            intents.append(.beginMonitoringSession)
        }
        intents.append(.persistTrackingSource)
        intents.append(.syncUI)
        return perform(intents)
    }
}

/// Executes the side effects requested by the reducer. The reducer describes
/// every effect as a `TrackingFeature.EffectIntent`; the app installs a single
/// closure that performs them (see `AppDelegate.performTrackingEffect`).
struct TrackingRuntimeClient {
    var perform: @Sendable (TrackingFeature.EffectIntent) async -> Void
}

extension TrackingRuntimeClient {
    static let unimplemented = Self(perform: { _ in })
}

private enum TrackingRuntimeClientKey: DependencyKey {
    static let liveValue = TrackingRuntimeClient.unimplemented
    static let testValue = TrackingRuntimeClient.unimplemented
}

extension DependencyValues {
    var trackingRuntime: TrackingRuntimeClient {
        get { self[TrackingRuntimeClientKey.self] }
        set { self[TrackingRuntimeClientKey.self] = newValue }
    }
}
