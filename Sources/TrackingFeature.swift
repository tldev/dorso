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

    enum EffectIntent: Equatable {
        case startMonitoring
        case beginMonitoringSession
        case applyStartupCameraProfile(ProfileData? = nil)
        case showOnboarding
        case switchCamera(CameraSwitchIntent)
        case syncUI
        case stopDetector(TrackingSource)
        case setTrackingSource(TrackingSource)
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

    @Dependency(\.trackingEffectExecutor) var trackingEffectExecutor

    private func executeEffectIntents(
        _ intents: [EffectIntent]
    ) -> Effect<Action> {
        guard !intents.isEmpty else { return .none }
        return .run { [intents] _ in
            for intent in intents {
                await trackingEffectExecutor.execute(intent)
            }
        }
    }

    private func emit(_ intents: [EffectIntent]) -> Effect<Action> {
        executeEffectIntents(intents)
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
                        return emit([.startMonitoring])
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
                return emit(intents)

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
                    return emit([.beginMonitoringSession])
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
                    return emit([.startMonitoring])
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
                    return emit([.switchCamera(.matchingProfile(matchingProfile)), .startMonitoring])
                } else if result.newState == previousState {
                    return emit([.syncUI])
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
                    return emit([.syncUI])
                case .switchToFallback(let startMonitoring):
                    var intents: [EffectIntent] = [.switchCamera(.fallback(cameraID: fallbackCameraID, profile: fallbackProfile))]
                    if startMonitoring {
                        intents.append(.startMonitoring)
                    }
                    return emit(intents)
                }

            case .calibrationAuthorizationDenied(let isCalibrated):
                state.appState = PostureEngine.stateWhenCalibrationAuthorizationDenied(
                    isCalibrated: isCalibrated
                )
                return emit([.showCalibrationPermissionDeniedAlert])

            case .calibrationOpenSettingsRequested:
                return emit([.openPrivacySettings])

            case .calibrationRetryRequested:
                return emit([.retryCalibration])

            case .calibrationAuthorizationGranted:
                state.appState = PostureEngine.stateWhenCalibrationAuthorizationGranted()
                return .none

            case .calibrationStartFailed(let errorMessage):
                state.appState = PostureEngine.unavailableState(for: state.activeSource)
                if state.activeSource == .camera {
                    return emit([.showCameraCalibrationRetryAlert(message: errorMessage)])
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
                    return emit([.startMonitoring])
                }
                return .none

            case .calibrationCompleted:
                state.appState = PostureEngine.stateWhenCalibrationCompletes()
                return emit([.resetMonitoringState, .startMonitoring])

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
                    return emit([.startMonitoring])
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

                var intents: [EffectIntent] = []
                if result.shouldSwitchToProfileCamera {
                    intents.append(.switchCamera(.matchingProfile(matchingProfile)))
                }
                if result.shouldStartMonitoring {
                    intents.append(.startMonitoring)
                }
                return emit(intents)

            case .cameraSelectionChanged:
                state.appState = PostureEngine.stateWhenCameraSelectionChanges(
                    currentState: state.appState,
                    trackingSource: state.activeSource
                )
                if state.activeSource == .camera {
                    return emit([.switchCamera(.selectedCamera)])
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

                var intents: [EffectIntent] = []
                if result.didSwitchSource {
                    intents.append(.stopDetector(previousSource))
                    intents.append(.setTrackingSource(result.newSource))
                    intents.append(.persistTrackingSource)
                }
                if result.shouldStartMonitoring {
                    intents.append(.startMonitoring)
                }
                return emit(intents)
            }
        }
    }
}

struct TrackingEffectExecutorClient {
    var execute: (TrackingFeature.EffectIntent) async -> Void
}

extension TrackingEffectExecutorClient {
    static let unimplemented = Self(execute: { _ in })
}

private enum TrackingEffectExecutorClientKey: DependencyKey {
    static let liveValue = TrackingEffectExecutorClient.unimplemented
    static let testValue = TrackingEffectExecutorClient.unimplemented
}

extension DependencyValues {
    var trackingEffectExecutor: TrackingEffectExecutorClient {
        get { self[TrackingEffectExecutorClientKey.self] }
        set { self[TrackingEffectExecutorClientKey.self] = newValue }
    }
}
