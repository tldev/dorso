import Foundation
import ComposableArchitecture
@testable import DorsoCore

private actor IntentRecorder {
    private var intents: [TrackingFeature.EffectIntent] = []

    func append(_ intent: TrackingFeature.EffectIntent) {
        intents.append(intent)
    }

    func snapshot() -> [TrackingFeature.EffectIntent] {
        intents
    }
}

private extension TrackingRuntimeClient {
    static func recording(_ recorder: IntentRecorder) -> Self {
        Self(
            startMonitoring: { await recorder.append(.startMonitoring) },
            beginMonitoringSession: { await recorder.append(.beginMonitoringSession) },
            applyStartupCameraProfile: { profile in
                await recorder.append(.applyStartupCameraProfile(profile))
            },
            showOnboarding: { await recorder.append(.showOnboarding) },
            switchCameraToMatchingProfile: { profile in
                await recorder.append(.switchCamera(.matchingProfile(profile)))
            },
            switchCameraToFallback: { cameraID, profile in
                await recorder.append(.switchCamera(.fallback(cameraID: cameraID, profile: profile)))
            },
            switchCameraToSelected: {
                await recorder.append(.switchCamera(.selectedCamera))
            },
            syncUI: { await recorder.append(.syncUI) },
            stopDetector: { source in await recorder.append(.stopDetector(source)) },
            persistTrackingSource: { await recorder.append(.persistTrackingSource) },
            resetMonitoringState: { await recorder.append(.resetMonitoringState) },
            showCalibrationPermissionDeniedAlert: {
                await recorder.append(.showCalibrationPermissionDeniedAlert)
            },
            openPrivacySettings: { await recorder.append(.openPrivacySettings) },
            showCameraCalibrationRetryAlert: { message in
                await recorder.append(.showCameraCalibrationRetryAlert(message: message))
            },
            retryCalibration: { await recorder.append(.retryCalibration) }
        )
    }
}

@MainActor
struct TrackingReducerScenarioHarness {
    private var reducerState: TrackingFeature.State
    private var isCalibrated: Bool
    private var detectorAvailable: Bool
    private var isConnected: Bool

    private(set) var timeline: [TrackingScenarioSnapshot] = []

    init(
        state: AppState,
        trackingSource: TrackingSource,
        isCalibrated: Bool,
        detectorAvailable: Bool,
        stateBeforeLock: AppState? = nil
    ) {
        reducerState = TrackingFeature.State(
            appState: state,
            trackingMode: .manual,
            manualSource: trackingSource,
            preferredSource: .camera,
            autoReturnEnabled: false,
            stateBeforeLock: stateBeforeLock
        )
        self.isCalibrated = isCalibrated
        self.detectorAvailable = detectorAvailable
        self.isConnected = true

        record(.initial, restartMonitoringRequested: false)
    }

    mutating func send(_ event: TrackingScenarioEvent) async {
        var intents: [TrackingFeature.EffectIntent] = []

        switch event {
        case .initial:
            break
        case .setState(let nextState):
            reducerState.appState = nextState
        case .setTrackingSource(let source):
            reducerState.manualSource = source
        case .setCalibrated(let calibrated):
            isCalibrated = calibrated
        case .setDetectorAvailable(let available):
            detectorAvailable = available
        case .startMonitoringRequested(let isMarketingMode, let isConnected):
            self.isConnected = isConnected
            intents = await dispatch(
                .startMonitoringRequested(
                    isMarketingMode: isMarketingMode,
                    trackingSource: reducerState.manualSource,
                    isCalibrated: isCalibrated,
                    isConnected: isConnected
                )
            )
        case .switchTrackingSource(let newSource, let newSourceCalibrated):
            intents = await dispatch(
                .switchTrackingSource(
                    newSource,
                    isNewSourceCalibrated: newSourceCalibrated
                )
            )
            isCalibrated = newSourceCalibrated
        case .toggleEnabled:
            intents = await dispatch(
                .toggleEnabled(
                    trackingSource: reducerState.manualSource,
                    isCalibrated: isCalibrated,
                    detectorAvailable: detectorAvailable
                )
            )
        case .calibrationAuthorizationDenied:
            intents = await dispatch(.calibrationAuthorizationDenied(isCalibrated: isCalibrated))
        case .calibrationAuthorizationGranted:
            intents = await dispatch(.calibrationAuthorizationGranted)
        case .calibrationStartFailed:
            intents = await dispatch(.calibrationStartFailed(errorMessage: nil))
        case .runtimeDetectorStartFailed:
            intents = await dispatch(.runtimeDetectorStartFailed(trackingSource: reducerState.manualSource))
        case .calibrationCancelled:
            intents = await dispatch(.calibrationCancelled(isCalibrated: isCalibrated))
        case .calibrationCompleted:
            intents = await dispatch(.calibrationCompleted)
            isCalibrated = true
        case .airPodsConnectionChanged(let isConnected):
            self.isConnected = isConnected
            intents = await dispatch(.airPodsConnectionChanged(isConnected))
        case .cameraConnected(let hasMatchingProfile):
            intents = await dispatch(.cameraConnected(hasMatchingProfile: hasMatchingProfile))
        case .cameraDisconnected(
            let disconnectedCameraIsSelected,
            let hasFallbackCamera,
            let fallbackHasMatchingProfile
        ):
            intents = await dispatch(
                .cameraDisconnected(
                    disconnectedCameraIsSelected: disconnectedCameraIsSelected,
                    hasFallbackCamera: hasFallbackCamera,
                    fallbackHasMatchingProfile: fallbackHasMatchingProfile
                )
            )
        case .displayConfigurationChanged(
            let pauseOnTheGoEnabled,
            let isLaptopOnlyConfiguration,
            let hasAnyCamera,
            let hasMatchingProfileCamera,
            let selectedCameraMatchesProfile
        ):
            intents = await dispatch(
                .displayConfigurationChanged(
                    pauseOnTheGoEnabled: pauseOnTheGoEnabled,
                    isLaptopOnlyConfiguration: isLaptopOnlyConfiguration,
                    hasAnyCamera: hasAnyCamera,
                    hasMatchingProfileCamera: hasMatchingProfileCamera,
                    selectedCameraMatchesProfile: selectedCameraMatchesProfile
                )
            )
        case .cameraSelectionChanged:
            intents = await dispatch(.cameraSelectionChanged)
        case .screenLocked:
            intents = await dispatch(.screenLocked)
        case .screenUnlocked:
            intents = await dispatch(.screenUnlocked)
        }

        let startMonitoringRequested = intents.contains { intent in
            if case .startMonitoring = intent {
                return true
            }
            return false
        }
        let beginMonitoringRequested = intents.contains { intent in
            if case .beginMonitoringSession = intent {
                return true
            }
            return false
        }
        let stopDetectorRequested = intents.contains { intent in
            if case .stopDetector = intent {
                return true
            }
            return false
        }
        let persistSourceRequested = intents.contains { intent in
            if case .persistTrackingSource = intent {
                return true
            }
            return false
        }
        let resetMonitoringRequested = intents.contains { intent in
            if case .resetMonitoringState = intent {
                return true
            }
            return false
        }
        let fallbackSwitchRequested = intents.contains { intent in
            if case .switchCamera(.fallback(cameraID: _, profile: _)) = intent {
                return true
            }
            return false
        }
        let selectedCameraSwitchRequested = intents.contains { intent in
            if case .switchCamera(.matchingProfile(_)) = intent {
                return true
            }
            if case .switchCamera(.selectedCamera) = intent {
                return true
            }
            return false
        }
        let uiSyncRequested = intents.contains { intent in
            if case .syncUI = intent {
                return true
            }
            return false
        }

        let restartMonitoringRequested: Bool
        switch event {
        case .airPodsConnectionChanged, .screenUnlocked:
            restartMonitoringRequested = startMonitoringRequested
        default:
            restartMonitoringRequested = false
        }

        record(
            event,
            restartMonitoringRequested: restartMonitoringRequested,
            startMonitoringRequested: startMonitoringRequested,
            beginMonitoringRequested: beginMonitoringRequested,
            stopDetectorRequested: stopDetectorRequested,
            persistSourceRequested: persistSourceRequested,
            resetMonitoringRequested: resetMonitoringRequested,
            fallbackSwitchRequested: fallbackSwitchRequested,
            selectedCameraSwitchRequested: selectedCameraSwitchRequested,
            uiSyncRequested: uiSyncRequested
        )
    }

    private mutating func dispatch(_ action: TrackingFeature.Action) async -> [TrackingFeature.EffectIntent] {
        let intentRecorder = IntentRecorder()
        let store = Store(initialState: reducerState) {
            TrackingFeature()
        } withDependencies: {
            $0.trackingRuntime = .recording(intentRecorder)
        }

        let actionTask = store.send(action)
        await actionTask.finish()
        reducerState = store.withState { $0 }
        return await intentRecorder.snapshot()
    }

    private mutating func record(
        _ event: TrackingScenarioEvent,
        restartMonitoringRequested: Bool,
        startMonitoringRequested: Bool = false,
        beginMonitoringRequested: Bool = false,
        stopDetectorRequested: Bool = false,
        persistSourceRequested: Bool = false,
        resetMonitoringRequested: Bool = false,
        fallbackSwitchRequested: Bool = false,
        selectedCameraSwitchRequested: Bool = false,
        uiSyncRequested: Bool = false
    ) {
        timeline.append(
            TrackingScenarioSnapshot(
                event: event,
                state: reducerState.appState,
                trackingSource: reducerState.manualSource,
                stateBeforeLock: reducerState.stateBeforeLock,
                detectorShouldRun: PostureEngine.shouldDetectorRun(
                    for: reducerState.appState,
                    trackingSource: reducerState.manualSource
                ),
                restartMonitoringRequested: restartMonitoringRequested,
                startMonitoringRequested: startMonitoringRequested,
                beginMonitoringRequested: beginMonitoringRequested,
                stopDetectorRequested: stopDetectorRequested,
                persistSourceRequested: persistSourceRequested,
                resetMonitoringRequested: resetMonitoringRequested,
                fallbackSwitchRequested: fallbackSwitchRequested,
                selectedCameraSwitchRequested: selectedCameraSwitchRequested,
                uiSyncRequested: uiSyncRequested
            )
        )
    }
}
