import ComposableArchitecture
import Foundation

extension TrackingFeature {
    func reduceCalibration(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .calibrationAuthorizationDenied:
            state.appState = PostureEngine.stateWhenCalibrationAuthorizationDenied(
                isCalibrated: state.isCalibrated(state.activeSource))
            return perform(.showCalibrationPermissionDeniedAlert)
        case .calibrationOpenSettingsRequested:
            return perform(.openPrivacySettings)
        case .calibrationRetryRequested:
            return perform(.retryCalibration)
        case .calibrationAuthorizationGranted:
            state.appState = PostureEngine.stateWhenCalibrationAuthorizationGranted()
            // .calibrating counts as active, so finish() won't clear the warning
            state.monitoringState.reset()
            state.lastPostureReadingTime = nil
            return .none
        case .calibrationStartFailed(let errorMessage):
            state.appState = PostureEngine.unavailableState(for: state.activeSource)
            if state.activeSource == .camera {
                return perform(.showCameraCalibrationRetryAlert(message: errorMessage))
            }
            return .none
        case .runtimeDetectorStartFailed:
            let trackingSource = state.manualSource
            state.activeSource = trackingSource
            state.appState = PostureEngine.unavailableState(for: trackingSource)
            return .none
        case .calibrationCancelled:
            let isCalibrated = state.isCalibrated(state.activeSource)
            state.appState = PostureEngine.stateWhenCalibrationCancels(isCalibrated: isCalibrated)
            return isCalibrated ? perform(.startMonitoring) : .none
        case .calibrationCompleted(let calibration):
            return calibrationCompleted(&state, calibration)
        case .cameraCalibrationChanged(let calibration):
            state.setCameraCalibration(calibration)
            return .none
        case .airPodsCalibrationChanged(let calibration):
            state.setAirPodsCalibration(calibration)
            return .none
        default:
            return .none
        }
    }

    private func calibrationCompleted(_ state: inout State, _ calibration: CompletedCalibration) -> Effect<Action> {
        state.monitoringState.reset()
        state.lastPostureReadingTime = nil
        switch calibration {
        case .camera(let data): state.setCameraCalibration(data)
        case .airPods(let data): state.setAirPodsCalibration(data)
        }
        if state.trackingMode == .automatic {
            return resolveAutomaticSource(&state)
        }
        state.appState = PostureEngine.stateWhenCalibrationCompletes()
        return perform(.startMonitoring)
    }

    // MARK: - Automatic Mode Source Resolution

    func resolveAutomaticSource(_ state: inout State) -> Effect<Action> {
        // The battery pause is sticky: source readiness changes must not resume
        // tracking. AC power, the setting, or a direct user action lifts it.
        guard state.appState != .paused(.onBattery) else { return .none }

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
        let needsBeginMonitoring =
            result.newState == .monitoring
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
