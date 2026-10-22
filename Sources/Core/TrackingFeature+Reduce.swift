import ComposableArchitecture
import Foundation

extension TrackingFeature {
    func handle(_ action: Action, into state: inout State) -> Effect<Action> {
        switch action {
        case .appLaunched, .setAppState, .toggleEnabled, .setTrackingMode, .setManualSource, .setPreferredSource,
            .setAutoReturnEnabled, .setPostureConfiguration, .pauseOnTheGoSettingChanged, .switchTrackingSource,
            .sourceReadinessChanged:
            return reduceSettings(into: &state, action: action)
        case .postureReadingReceived, .awayStateChanged, .initialSetupEvaluated, .startMonitoringRequested,
            .timedPauseRequested, .timedPauseDeadlineReached, .timedPauseEnded:
            return reduceMonitoring(into: &state, action: action)
        case .airPodsConnectionChanged, .cameraConnected, .cameraDisconnected, .screenLocked, .screenUnlocked,
            .powerSourceChanged, .setPauseOnBatteryEnabled, .displayConfigurationChanged, .cameraSelectionChanged:
            return reduceDeviceEvents(into: &state, action: action)
        case .calibrationAuthorizationDenied, .calibrationOpenSettingsRequested, .calibrationRetryRequested,
            .calibrationAuthorizationGranted, .calibrationStartFailed, .runtimeDetectorStartFailed,
            .calibrationCancelled, .calibrationCompleted:
            return reduceCalibration(into: &state, action: action)
        }
    }

    // MARK: - Settings

    private func reduceSettings(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .setAppState(let appState):
            state.appState = appState
        case .toggleEnabled(let trackingSource, let isCalibrated, let detectorAvailable):
            return toggleEnabled(
                &state, trackingSource, isCalibrated: isCalibrated, detectorAvailable: detectorAvailable)
        case .setTrackingMode(let mode):
            return setTrackingMode(&state, mode)
        case .setManualSource(let source):
            return setManualSource(&state, source)
        case .setPreferredSource(let source):
            return setPreferredSource(&state, source)
        case .setAutoReturnEnabled(let enabled):
            state.autoReturnEnabled = enabled
        case .setPostureConfiguration(let intensity, let warningOnsetDelay):
            state.postureConfig.intensity = CGFloat(intensity)
            state.postureConfig.warningOnsetDelay = warningOnsetDelay
        case .pauseOnTheGoSettingChanged(let isEnabled):
            state.appState = PostureEngine.stateWhenPauseOnTheGoSettingChanges(
                currentState: state.appState,
                isEnabled: isEnabled
            )
        case .switchTrackingSource(let newSource, let isNewSourceCalibrated):
            return switchTrackingSource(&state, newSource, isNewSourceCalibrated: isNewSourceCalibrated)
        case .sourceReadinessChanged(let source, let readiness):
            return sourceReadinessChanged(&state, source, readiness)
        default:
            break
        }
        return .none
    }

    private func toggleEnabled(
        _ state: inout State,
        _ trackingSource: TrackingSource,
        isCalibrated: Bool,
        detectorAvailable: Bool
    ) -> Effect<Action> {
        state.manualSource = trackingSource
        state.activeSource = trackingSource
        if state.appState == .disabled {
            state.appState = PostureEngine.stateWhenEnabling(
                isCalibrated: isCalibrated,
                detectorAvailable: detectorAvailable,
                trackingSource: trackingSource
            )
            if state.appState == .monitoring {
                return perform(.startMonitoring)
            }
        } else {
            state.appState = .disabled
        }
        return .none
    }

    private func setTrackingMode(_ state: inout State, _ mode: TrackingMode) -> Effect<Action> {
        state.trackingMode = mode
        if mode == .automatic {
            return resolveAutomaticSource(&state)
        }
        // Switching back to manual: activeSource follows manualSource
        let previousSource = state.activeSource
        state.activeSource = state.manualSource
        let sourceChanged = state.activeSource != previousSource
        if sourceChanged && state.appState == .monitoring {
            return perform(.beginMonitoringSession)
        }
        return .none
    }

    private func setManualSource(_ state: inout State, _ source: TrackingSource) -> Effect<Action> {
        let previousSource = state.activeSource
        state.manualSource = source
        state.activeSource = source
        if state.activeSource != previousSource && state.appState == .monitoring {
            return perform(.beginMonitoringSession)
        }
        return .none
    }

    private func setPreferredSource(_ state: inout State, _ source: TrackingSource) -> Effect<Action> {
        state.preferredSource = source
        if state.trackingMode == .automatic {
            return resolveAutomaticSource(&state)
        }
        return .none
    }

    private func switchTrackingSource(
        _ state: inout State,
        _ newSource: TrackingSource,
        isNewSourceCalibrated: Bool
    ) -> Effect<Action> {
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
        return perform(intents)
    }

    private func sourceReadinessChanged(
        _ state: inout State,
        _ source: TrackingSource,
        _ readiness: TrackingSourceReadiness
    ) -> Effect<Action> {
        switch source {
        case .camera: state.cameraReadiness = readiness
        case .airpods: state.airPodsReadiness = readiness
        }
        if state.trackingMode == .automatic, state.appState != .disabled {
            return resolveAutomaticSource(&state)
        }
        return .none
    }
}
