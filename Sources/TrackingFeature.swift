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
        case stopDetector(TrackingSource)
        case persistTrackingSource
        case resetMonitoringState
        case showCalibrationPermissionDeniedAlert
        case openPrivacySettings
        case showCameraCalibrationRetryAlert(message: String?)
        case retryCalibration
    }

    struct State: Equatable {
        var appState: AppState = .disabled

        // Manual mode remains the runtime policy during migration.
        var trackingMode: TrackingMode = .manual
        var manualSource: TrackingSource = .camera
        var preferredSource: TrackingSource = .camera
        var autoReturnEnabled: Bool = false

        var stateBeforeLock: AppState?

        var activeSource: TrackingSource { manualSource }
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
        case pauseOnTheGoSettingChanged(isEnabled: Bool)
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
        case calibrationCompleted
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
    }

    @Dependency(\.trackingRuntime) var trackingRuntime

    private func run(
        _ operation: @escaping @Sendable (TrackingRuntimeClient) async -> Void
    ) -> Effect<Action> {
        .run { _ in
            await operation(trackingRuntime)
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appLaunched:
                return .none

            case .setAppState(let appState):
                state.appState = appState
                return .none

            case let .toggleEnabled(trackingSource, isCalibrated, detectorAvailable):
                state.manualSource = trackingSource
                if state.appState == .disabled {
                    state.appState = PostureEngine.stateWhenEnabling(
                        isCalibrated: isCalibrated,
                        detectorAvailable: detectorAvailable,
                        trackingSource: trackingSource
                    )
                    if state.appState == .monitoring {
                        return run { runtime in
                            await runtime.startMonitoring()
                        }
                    }
                } else {
                    state.appState = .disabled
                }
                return .none

            case .setTrackingMode(let mode):
                state.trackingMode = mode
                return .none

            case .setManualSource(let source):
                state.manualSource = source
                return .none

            case .setPreferredSource(let source):
                state.preferredSource = source
                return .none

            case .setAutoReturnEnabled(let enabled):
                state.autoReturnEnabled = enabled
                return .none

            case .pauseOnTheGoSettingChanged(let isEnabled):
                state.appState = PostureEngine.stateWhenPauseOnTheGoSettingChanges(
                    currentState: state.appState,
                    isEnabled: isEnabled
                )
                return .none

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

                guard result.shouldApplyStartupCameraProfile || result.shouldStartMonitoring || result.shouldShowOnboarding else {
                    return .none
                }

                return run { runtime in
                    if result.shouldApplyStartupCameraProfile {
                        await runtime.applyStartupCameraProfile(cameraProfile)
                    }
                    if result.shouldStartMonitoring {
                        await runtime.startMonitoring()
                    }
                    if result.shouldShowOnboarding {
                        await runtime.showOnboarding()
                    }
                }

            case let .startMonitoringRequested(isMarketingMode, trackingSource, isCalibrated, isConnected):
                state.manualSource = trackingSource
                let result = PostureEngine.stateWhenMonitoringStarts(
                    isMarketingMode: isMarketingMode,
                    trackingSource: trackingSource,
                    isCalibrated: isCalibrated,
                    isConnected: isConnected
                )
                state.appState = result.newState
                if result.shouldBeginMonitoringSession {
                    return run { runtime in
                        await runtime.beginMonitoringSession()
                    }
                }
                return .none

            case .airPodsConnectionChanged(let isConnected):
                let result = PostureEngine.stateWhenAirPodsConnectionChanges(
                    currentState: state.appState,
                    trackingSource: state.activeSource,
                    isConnected: isConnected
                )
                state.appState = result.newState
                if result.shouldRestartMonitoring {
                    return run { runtime in
                        await runtime.startMonitoring()
                    }
                }
                return .none

            case .cameraConnected(let hasMatchingProfile, let matchingProfile):
                let previousState = state.appState
                let result = PostureEngine.stateWhenCameraConnects(
                    currentState: state.appState,
                    trackingSource: state.activeSource,
                    hasMatchingProfileForConnectedCamera: hasMatchingProfile
                )
                state.appState = result.newState

                if result.shouldSelectAndStartMonitoring {
                    return run { runtime in
                        await runtime.switchCameraToMatchingProfile(matchingProfile)
                        await runtime.startMonitoring()
                    }
                }

                if result.newState == previousState {
                    return run { runtime in
                        await runtime.syncUI()
                    }
                }
                return .none

            case .cameraDisconnected(
                let disconnectedCameraIsSelected,
                let hasFallbackCamera,
                let fallbackHasMatchingProfile,
                let fallbackCameraID,
                let fallbackProfile
            ):
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
                    return .none
                case .syncUIOnly:
                    return run { runtime in
                        await runtime.syncUI()
                    }
                case .switchToFallback(let startMonitoring):
                    return run { runtime in
                        await runtime.switchCameraToFallback(fallbackCameraID, fallbackProfile)
                        if startMonitoring {
                            await runtime.startMonitoring()
                        }
                    }
                }

            case .calibrationAuthorizationDenied(let isCalibrated):
                state.appState = PostureEngine.stateWhenCalibrationAuthorizationDenied(
                    isCalibrated: isCalibrated
                )
                return run { runtime in
                    await runtime.showCalibrationPermissionDeniedAlert()
                }

            case .calibrationOpenSettingsRequested:
                return run { runtime in
                    await runtime.openPrivacySettings()
                }

            case .calibrationRetryRequested:
                return run { runtime in
                    await runtime.retryCalibration()
                }

            case .calibrationAuthorizationGranted:
                state.appState = PostureEngine.stateWhenCalibrationAuthorizationGranted()
                return .none

            case .calibrationStartFailed(let errorMessage):
                state.appState = PostureEngine.unavailableState(for: state.activeSource)
                if state.activeSource == .camera {
                    return run { runtime in
                        await runtime.showCameraCalibrationRetryAlert(errorMessage)
                    }
                }
                return .none

            case .runtimeDetectorStartFailed(let trackingSource):
                state.manualSource = trackingSource
                state.appState = PostureEngine.unavailableState(for: trackingSource)
                return .none

            case .calibrationCancelled(let isCalibrated):
                state.appState = PostureEngine.stateWhenCalibrationCancels(
                    isCalibrated: isCalibrated
                )
                if isCalibrated {
                    return run { runtime in
                        await runtime.startMonitoring()
                    }
                }
                return .none

            case .calibrationCompleted:
                state.appState = PostureEngine.stateWhenCalibrationCompletes()
                return run { runtime in
                    await runtime.resetMonitoringState()
                    await runtime.startMonitoring()
                }

            case .screenLocked:
                let result = PostureEngine.stateWhenScreenLocks(
                    currentState: state.appState,
                    trackingSource: state.activeSource,
                    stateBeforeLock: state.stateBeforeLock
                )
                state.appState = result.newState
                state.stateBeforeLock = result.stateBeforeLock
                return .none

            case .screenUnlocked:
                let result = PostureEngine.stateWhenScreenUnlocks(
                    currentState: state.appState,
                    stateBeforeLock: state.stateBeforeLock
                )
                state.appState = result.newState
                state.stateBeforeLock = result.stateBeforeLock
                if result.shouldRestartMonitoring {
                    return run { runtime in
                        await runtime.startMonitoring()
                    }
                }
                return .none

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

                guard result.shouldSwitchToProfileCamera || result.shouldStartMonitoring else {
                    return .none
                }

                return run { runtime in
                    if result.shouldSwitchToProfileCamera {
                        await runtime.switchCameraToMatchingProfile(matchingProfile)
                    }
                    if result.shouldStartMonitoring {
                        await runtime.startMonitoring()
                    }
                }

            case .cameraSelectionChanged:
                state.appState = PostureEngine.stateWhenCameraSelectionChanges(
                    currentState: state.appState,
                    trackingSource: state.activeSource
                )
                if state.activeSource == .camera {
                    return run { runtime in
                        await runtime.switchCameraToSelected()
                    }
                }
                return .none

            case .switchTrackingSource(let newSource, let isNewSourceCalibrated):
                let previousSource = state.activeSource
                let result = PostureEngine.stateWhenSwitchingTrackingSource(
                    currentState: state.appState,
                    currentSource: previousSource,
                    newSource: newSource,
                    isNewSourceCalibrated: isNewSourceCalibrated
                )

                state.manualSource = result.newSource
                state.appState = result.newState

                guard result.didSwitchSource || result.shouldStartMonitoring else {
                    return .none
                }

                return run { runtime in
                    if result.didSwitchSource {
                        await runtime.stopDetector(previousSource)
                        await runtime.persistTrackingSource()
                    }
                    if result.shouldStartMonitoring {
                        await runtime.startMonitoring()
                    }
                }
            }
        }
    }
}

struct TrackingRuntimeClient {
    var startMonitoring: @Sendable () async -> Void
    var beginMonitoringSession: @Sendable () async -> Void
    var applyStartupCameraProfile: @Sendable (ProfileData?) async -> Void
    var showOnboarding: @Sendable () async -> Void
    var switchCameraToMatchingProfile: @Sendable (ProfileData?) async -> Void
    var switchCameraToFallback: @Sendable (String?, ProfileData?) async -> Void
    var switchCameraToSelected: @Sendable () async -> Void
    var syncUI: @Sendable () async -> Void
    var stopDetector: @Sendable (TrackingSource) async -> Void
    var persistTrackingSource: @Sendable () async -> Void
    var resetMonitoringState: @Sendable () async -> Void
    var showCalibrationPermissionDeniedAlert: @Sendable () async -> Void
    var openPrivacySettings: @Sendable () async -> Void
    var showCameraCalibrationRetryAlert: @Sendable (String?) async -> Void
    var retryCalibration: @Sendable () async -> Void
}

extension TrackingRuntimeClient {
    static let unimplemented = Self(
        startMonitoring: {},
        beginMonitoringSession: {},
        applyStartupCameraProfile: { _ in },
        showOnboarding: {},
        switchCameraToMatchingProfile: { _ in },
        switchCameraToFallback: { _, _ in },
        switchCameraToSelected: {},
        syncUI: {},
        stopDetector: { _ in },
        persistTrackingSource: {},
        resetMonitoringState: {},
        showCalibrationPermissionDeniedAlert: {},
        openPrivacySettings: {},
        showCameraCalibrationRetryAlert: { _ in },
        retryCalibration: {}
    )
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
