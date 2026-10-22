import Foundation

extension PostureEngine {
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
    /// If tracking would resume while on battery with pause-on-battery enabled
    /// (e.g. the Mac was unplugged while the lid was closed), land in the
    /// battery pause instead of restarting.
    static func stateWhenScreenUnlocks(
        currentState: AppState,
        stateBeforeLock: AppState?,
        pauseOnBatteryEnabled: Bool = false,
        isOnBattery: Bool = false
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

        if pauseOnBatteryEnabled, isOnBattery, shouldPauseOnBattery(from: previousState) {
            return ScreenUnlockTransitionResult(
                newState: .paused(.onBattery),
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
}
