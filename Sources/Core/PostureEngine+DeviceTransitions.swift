import Foundation

extension PostureEngine {
    // MARK: - Power Source Transitions

    /// States the battery pause replaces: monitoring, plus the AirPods-removed
    /// pause whose detector keeps running to watch for re-insertion. Calibration
    /// is left alone — the user is actively mid-flow.
    static func shouldPauseOnBattery(from state: AppState) -> Bool {
        state == .monitoring || state == .paused(.airPodsRemoved)
    }

    /// Determine state impact of an AC/battery power source change.
    static func stateWhenPowerSourceChanges(
        currentState: AppState,
        isOnBattery: Bool,
        pauseOnBatteryEnabled: Bool
    ) -> PowerSourceTransitionResult {
        if isOnBattery {
            guard pauseOnBatteryEnabled, shouldPauseOnBattery(from: currentState) else {
                return PowerSourceTransitionResult(newState: currentState, shouldRestartMonitoring: false)
            }
            return PowerSourceTransitionResult(newState: .paused(.onBattery), shouldRestartMonitoring: false)
        }

        guard currentState == .paused(.onBattery) else {
            return PowerSourceTransitionResult(newState: currentState, shouldRestartMonitoring: false)
        }
        return PowerSourceTransitionResult(newState: .monitoring, shouldRestartMonitoring: true)
    }

    /// Determine state impact when the pause-on-battery setting changes.
    static func stateWhenPauseOnBatterySettingChanges(
        currentState: AppState,
        isEnabled: Bool,
        isOnBattery: Bool
    ) -> PowerSourceTransitionResult {
        if isEnabled {
            guard isOnBattery, shouldPauseOnBattery(from: currentState) else {
                return PowerSourceTransitionResult(newState: currentState, shouldRestartMonitoring: false)
            }
            return PowerSourceTransitionResult(newState: .paused(.onBattery), shouldRestartMonitoring: false)
        }

        guard currentState == .paused(.onBattery) else {
            return PowerSourceTransitionResult(newState: currentState, shouldRestartMonitoring: false)
        }
        return PowerSourceTransitionResult(newState: .monitoring, shouldRestartMonitoring: true)
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

        // The battery pause is only lifted by AC power, the setting, or the user.
        guard case .paused(let reason) = currentState, reason != .onBattery else {
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
        guard trackingSource == .camera, currentState != .paused(.onBattery) else {
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
        context: DisplayConfigurationContext
    ) -> DisplayConfigurationTransitionResult {
        guard currentState != .disabled, currentState != .paused(.onBattery) else {
            return DisplayConfigurationTransitionResult(
                newState: currentState,
                shouldSwitchToProfileCamera: false,
                shouldStartMonitoring: false
            )
        }

        if context.pauseOnTheGoEnabled && context.isLaptopOnlyConfiguration {
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

        guard context.hasAnyCamera else {
            return DisplayConfigurationTransitionResult(
                newState: .paused(.cameraDisconnected),
                shouldSwitchToProfileCamera: false,
                shouldStartMonitoring: false
            )
        }

        if context.hasMatchingProfileCamera {
            return DisplayConfigurationTransitionResult(
                newState: .monitoring,
                shouldSwitchToProfileCamera: !context.selectedCameraMatchesProfile,
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
