import Foundation
@testable import DorsoCore

enum TrackingScenarioEvent: Equatable {
    case initial
    case setState(AppState)
    case setTrackingSource(TrackingSource)
    case setCalibrated(Bool)
    case setDetectorAvailable(Bool)
    case startMonitoringRequested(isMarketingMode: Bool, isConnected: Bool)
    case switchTrackingSource(to: TrackingSource, isCalibrated: Bool)
    case toggleEnabled
    case calibrationAuthorizationDenied
    case calibrationAuthorizationGranted
    case calibrationStartFailed
    case runtimeDetectorStartFailed
    case calibrationCancelled
    case calibrationCompleted
    case airPodsConnectionChanged(Bool)
    case cameraConnected(hasMatchingProfile: Bool)
    case cameraDisconnected(
        disconnectedCameraIsSelected: Bool,
        hasFallbackCamera: Bool,
        fallbackHasMatchingProfile: Bool
    )
    case displayConfigurationChanged(
        pauseOnTheGoEnabled: Bool,
        isLaptopOnlyConfiguration: Bool,
        hasAnyCamera: Bool,
        hasMatchingProfileCamera: Bool,
        selectedCameraMatchesProfile: Bool
    )
    case cameraSelectionChanged
    case screenLocked
    case screenUnlocked
    case setTrackingMode(TrackingMode)
    case setPreferredSource(TrackingSource)
    case sourceReadinessChanged(source: TrackingSource, readiness: TrackingSourceReadiness)
}

struct TrackingScenarioSnapshot: Equatable {
    let event: TrackingScenarioEvent
    let state: AppState
    let trackingSource: TrackingSource
    let stateBeforeLock: AppState?
    let detectorShouldRun: Bool
    let restartMonitoringRequested: Bool
    let startMonitoringRequested: Bool
    let beginMonitoringRequested: Bool
    let stopDetectorRequested: Bool
    let persistSourceRequested: Bool
    let resetMonitoringRequested: Bool
    let fallbackSwitchRequested: Bool
    let selectedCameraSwitchRequested: Bool
    let uiSyncRequested: Bool
}

struct TrackingScenarioHarness {
    var state: AppState
    var trackingSource: TrackingSource
    var isCalibrated: Bool
    var detectorAvailable: Bool
    var stateBeforeLock: AppState?

    private(set) var timeline: [TrackingScenarioSnapshot] = []

    init(
        state: AppState,
        trackingSource: TrackingSource,
        isCalibrated: Bool,
        detectorAvailable: Bool,
        stateBeforeLock: AppState? = nil
    ) {
        self.state = state
        self.trackingSource = trackingSource
        self.isCalibrated = isCalibrated
        self.detectorAvailable = detectorAvailable
        self.stateBeforeLock = stateBeforeLock
        record(.initial, restartMonitoringRequested: false)
    }

    mutating func send(_ event: TrackingScenarioEvent) {
        var restartMonitoringRequested = false
        var startMonitoringRequested = false
        var beginMonitoringRequested = false
        var stopDetectorRequested = false
        var persistSourceRequested = false
        var resetMonitoringRequested = false
        var fallbackSwitchRequested = false
        var selectedCameraSwitchRequested = false
        var uiSyncRequested = false

        switch event {
        case .initial:
            break
        case .setState(let nextState):
            state = nextState
        case .setTrackingSource(let source):
            trackingSource = source
        case .setCalibrated(let calibrated):
            isCalibrated = calibrated
        case .setDetectorAvailable(let available):
            detectorAvailable = available
        case .startMonitoringRequested(let isMarketingMode, let isConnected):
            let result = PostureEngine.stateWhenMonitoringStarts(
                isMarketingMode: isMarketingMode,
                trackingSource: trackingSource,
                isCalibrated: isCalibrated,
                isConnected: isConnected
            )
            state = result.newState
            beginMonitoringRequested = result.shouldBeginMonitoringSession
        case .switchTrackingSource(let newSource, let newSourceCalibrated):
            let result = PostureEngine.stateWhenSwitchingTrackingSource(
                currentState: state,
                currentSource: trackingSource,
                newSource: newSource,
                isNewSourceCalibrated: newSourceCalibrated
            )
            state = result.newState
            if result.didSwitchSource {
                trackingSource = result.newSource
                isCalibrated = newSourceCalibrated
                stopDetectorRequested = true
                persistSourceRequested = true
            }
            startMonitoringRequested = result.shouldStartMonitoring
        case .toggleEnabled:
            if state == .disabled {
                let nextState = PostureEngine.stateWhenEnabling(
                    isCalibrated: isCalibrated,
                    detectorAvailable: detectorAvailable,
                    trackingSource: trackingSource
                )
                state = nextState
                startMonitoringRequested = nextState == .monitoring
            } else {
                state = .disabled
            }
        case .calibrationAuthorizationDenied:
            state = PostureEngine.stateWhenCalibrationAuthorizationDenied(
                isCalibrated: isCalibrated
            )
        case .calibrationAuthorizationGranted:
            state = PostureEngine.stateWhenCalibrationAuthorizationGranted()
        case .calibrationStartFailed:
            state = PostureEngine.unavailableState(for: trackingSource)
        case .runtimeDetectorStartFailed:
            state = PostureEngine.unavailableState(for: trackingSource)
        case .calibrationCancelled:
            state = PostureEngine.stateWhenCalibrationCancels(
                isCalibrated: isCalibrated
            )
            startMonitoringRequested = isCalibrated
        case .calibrationCompleted:
            state = PostureEngine.stateWhenCalibrationCompletes()
            isCalibrated = true
            resetMonitoringRequested = true
            startMonitoringRequested = true
        case .airPodsConnectionChanged(let isConnected):
            let result = PostureEngine.stateWhenAirPodsConnectionChanges(
                currentState: state,
                trackingSource: trackingSource,
                isConnected: isConnected
            )
            state = result.newState
            restartMonitoringRequested = result.shouldRestartMonitoring
            startMonitoringRequested = result.shouldRestartMonitoring
        case .cameraConnected(let hasMatchingProfile):
            let result = PostureEngine.stateWhenCameraConnects(
                currentState: state,
                trackingSource: trackingSource,
                hasMatchingProfileForConnectedCamera: hasMatchingProfile
            )
            state = result.newState
            startMonitoringRequested = result.shouldSelectAndStartMonitoring
        case .cameraDisconnected(
            let disconnectedCameraIsSelected,
            let hasFallbackCamera,
            let fallbackHasMatchingProfile
        ):
            let result = PostureEngine.stateWhenCameraDisconnects(
                currentState: state,
                trackingSource: trackingSource,
                disconnectedCameraIsSelected: disconnectedCameraIsSelected,
                hasFallbackCamera: hasFallbackCamera,
                fallbackMatchesProfile: fallbackHasMatchingProfile
            )
            state = result.newState
            switch result.action {
            case .none:
                break
            case .syncUIOnly:
                uiSyncRequested = true
            case .switchToFallback(let startMonitoringAfterSwitch):
                fallbackSwitchRequested = true
                startMonitoringRequested = startMonitoringAfterSwitch
            }
        case .displayConfigurationChanged(
            let pauseOnTheGoEnabled,
            let isLaptopOnlyConfiguration,
            let hasAnyCamera,
            let hasMatchingProfileCamera,
            let selectedCameraMatchesProfile
        ):
            let result = PostureEngine.stateWhenDisplayConfigurationChanges(
                currentState: state,
                trackingSource: trackingSource,
                pauseOnTheGoEnabled: pauseOnTheGoEnabled,
                isLaptopOnlyConfiguration: isLaptopOnlyConfiguration,
                hasAnyCamera: hasAnyCamera,
                hasMatchingProfileCamera: hasMatchingProfileCamera,
                selectedCameraMatchesProfile: selectedCameraMatchesProfile
            )
            state = result.newState
            selectedCameraSwitchRequested = result.shouldSwitchToProfileCamera
            startMonitoringRequested = result.shouldStartMonitoring
        case .cameraSelectionChanged:
            state = PostureEngine.stateWhenCameraSelectionChanges(
                currentState: state,
                trackingSource: trackingSource
            )
            selectedCameraSwitchRequested = trackingSource == .camera
        case .screenLocked:
            let result = PostureEngine.stateWhenScreenLocks(
                currentState: state,
                trackingSource: trackingSource,
                stateBeforeLock: stateBeforeLock
            )
            state = result.newState
            stateBeforeLock = result.stateBeforeLock
        case .screenUnlocked:
            let result = PostureEngine.stateWhenScreenUnlocks(
                currentState: state,
                stateBeforeLock: stateBeforeLock
            )
            state = result.newState
            stateBeforeLock = result.stateBeforeLock
            restartMonitoringRequested = result.shouldRestartMonitoring
            startMonitoringRequested = result.shouldRestartMonitoring
        case .setTrackingMode, .setPreferredSource, .sourceReadinessChanged:
            // These are handled by the reducer harness only
            break
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
                state: state,
                trackingSource: trackingSource,
                stateBeforeLock: stateBeforeLock,
                detectorShouldRun: PostureEngine.shouldDetectorRun(for: state, trackingSource: trackingSource),
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
