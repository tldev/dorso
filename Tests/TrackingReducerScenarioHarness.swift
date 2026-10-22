import ComposableArchitecture
import Foundation

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

extension TrackingRuntimeClient {
    fileprivate static func recording(_ recorder: IntentRecorder) -> Self {
        Self(perform: { intent in await recorder.append(intent) })
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
        stateBeforeLock: AppState? = nil,
        trackingMode: TrackingMode = .manual,
        preferredSource: TrackingSource = .camera,
        cameraReadiness: TrackingSourceReadiness = TrackingSourceReadiness(),
        airPodsReadiness: TrackingSourceReadiness = TrackingSourceReadiness()
    ) {
        reducerState = TrackingFeature.State(
            appState: state,
            trackingMode: trackingMode,
            manualSource: trackingSource,
            preferredSource: preferredSource,
            autoReturnEnabled: true,
            cameraReadiness: cameraReadiness,
            airPodsReadiness: airPodsReadiness,
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
            reducerState.activeSource = source
        case .setCalibrated(let calibrated):
            isCalibrated = calibrated
        case .setDetectorAvailable(let available):
            detectorAvailable = available
        case .startMonitoringRequested(let isMarketingMode, let isConnected):
            self.isConnected = isConnected
            syncCalibration(for: reducerState.manualSource)
            reducerState.isMarketingMode = isMarketingMode
            intents = await dispatch(.startMonitoringRequested(isConnected: isConnected))
            reducerState.isMarketingMode = false
        case .switchTrackingSource(let newSource, let newSourceCalibrated):
            isCalibrated = newSourceCalibrated
            syncCalibration(for: newSource)
            intents = await dispatch(.switchTrackingSource(newSource))
        case .toggleEnabled:
            syncCalibration(for: reducerState.manualSource)
            intents = await dispatch(.toggleEnabled(detectorAvailable: detectorAvailable))
        case .calibrationAuthorizationDenied:
            syncCalibration(for: reducerState.activeSource)
            intents = await dispatch(.calibrationAuthorizationDenied)
        case .calibrationAuthorizationGranted:
            intents = await dispatch(.calibrationAuthorizationGranted)
        case .calibrationStartFailed:
            intents = await dispatch(.calibrationStartFailed(errorMessage: nil))
        case .runtimeDetectorStartFailed:
            intents = await dispatch(.runtimeDetectorStartFailed)
        case .calibrationCancelled:
            syncCalibration(for: reducerState.activeSource)
            intents = await dispatch(.calibrationCancelled)
        case .calibrationCompleted:
            let completed: TrackingFeature.CompletedCalibration =
                reducerState.activeSource == .camera ? .camera(.valid(cameraID: Camera.selected)) : .airPods(.valid)
            intents = await dispatch(.calibrationCompleted(completed))
            isCalibrated = true
        case .airPodsConnectionChanged(let isConnected):
            self.isConnected = isConnected
            intents = await dispatch(.airPodsConnectionChanged(isConnected))
        case .cameraConnected(let hasMatchingProfile):
            let profile = hasMatchingProfile ? Self.profile(cameraID: Camera.connected) : nil
            intents = await dispatch(.cameraConnected(matchingProfile: profile))
        case .cameraDisconnected(let isSelected, let hasFallback, let fallbackMatches):
            reducerState.selectedCameraID = Camera.selected
            intents = await dispatch(
                .cameraDisconnected(
                    cameraID: isSelected ? Camera.selected : Camera.other,
                    fallbackCameraID: hasFallback ? Camera.fallback : nil,
                    profile: fallbackMatches ? Self.profile(cameraID: Camera.fallback) : nil
                )
            )
        case .displayConfigurationChanged(
            let pauseOnTheGoEnabled,
            let isLaptopOnlyConfiguration,
            let hasAnyCamera,
            let hasMatchingProfileCamera,
            let selectedCameraMatchesProfile
        ):
            reducerState.pauseOnTheGoEnabled = pauseOnTheGoEnabled
            reducerState.selectedCameraID = Camera.selected
            let profileCamera = selectedCameraMatchesProfile ? Camera.selected : Camera.profile
            let hasProfile = hasMatchingProfileCamera || selectedCameraMatchesProfile
            intents = await dispatch(
                .displayConfigurationChanged(
                    isLaptopOnlyConfiguration: isLaptopOnlyConfiguration,
                    hasAnyCamera: hasAnyCamera,
                    hasMatchingProfileCamera: hasMatchingProfileCamera,
                    matchingProfile: hasProfile ? Self.profile(cameraID: profileCamera) : nil
                )
            )
        case .cameraSelectionChanged:
            intents = await dispatch(.cameraSelectionChanged(Camera.selected))
        case .screenLocked:
            intents = await dispatch(.screenLocked)
        case .screenUnlocked:
            intents = await dispatch(.screenUnlocked)
        case .setTrackingMode(let mode):
            intents = await dispatch(.setTrackingMode(mode))
        case .setPreferredSource(let source):
            intents = await dispatch(.setPreferredSource(source))
        case .sourceReadinessChanged(let source, let readiness):
            intents = await dispatch(.sourceReadinessChanged(source: source, readiness: readiness))
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
        let resetMonitoringRequested: Bool
        switch event {
        case .calibrationCompleted:
            resetMonitoringRequested = true
        default:
            resetMonitoringRequested = false
        }
        let fallbackSwitchRequested = intents.contains { intent in
            if case .switchCamera(to: Camera.fallback) = intent {
                return true
            }
            return false
        }
        let selectedCameraSwitchRequested = intents.contains { intent in
            if case .switchCamera(let cameraID) = intent {
                return cameraID != Camera.fallback
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

    /// Camera IDs standing in for real devices
    private enum Camera {
        static let selected = "selected-camera"
        static let fallback = "fallback-camera"
        static let connected = "connected-camera"
        static let profile = "profile-camera"
        static let other = "other-camera"
    }

    private static func profile(cameraID: String) -> ProfileData {
        ProfileData(goodPostureY: 0.6, badPostureY: 0.4, neutralY: 0.5, postureRange: 0.2, cameraID: cameraID)
    }

    /// The scenarios describe calibration as a flag; the reducer reads it from state
    private mutating func syncCalibration(for source: TrackingSource) {
        switch source {
        case .camera:
            reducerState.cameraCalibration = isCalibrated ? .valid(cameraID: Camera.selected) : nil
        case .airpods:
            reducerState.airPodsCalibration = isCalibrated ? .valid : nil
        }
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
