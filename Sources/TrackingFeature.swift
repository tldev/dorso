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
        case startCalibrationForSource(TrackingSource)
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

    private func run(
        _ operation: @escaping @Sendable (TrackingRuntimeClient) async -> Void
    ) -> Effect<Action> {
        .run { _ in
            await operation(trackingRuntime)
        }
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
                        return finish(run { runtime in
                            await runtime.startMonitoring()
                        })
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
                    return finish(run { runtime in
                        await runtime.beginMonitoringSession()
                    })
                }
                return finish()

            case .setManualSource(let source):
                let previousSource = state.activeSource
                state.manualSource = source
                state.activeSource = source
                if state.activeSource != previousSource && state.appState == .monitoring {
                    return finish(run { runtime in
                        await runtime.beginMonitoringSession()
                    })
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
                    return finish(run { runtime in
                        await runtime.syncUI()
                        await runtime.updateBlur()
                    })
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

                return finish(run { runtime in
                    for effect in result.effects {
                        switch effect {
                        case .trackAnalytics(let interval, let isSlouching):
                            if actualElapsed != nil {
                                await runtime.trackAnalytics(interval, isSlouching)
                            }
                        case .recordSlouchEvent:
                            await runtime.recordSlouchEvent()
                        case .updateUI:
                            await runtime.syncUI()
                        case .updateBlur:
                            await runtime.updateBlur()
                        }
                    }
                })

            case let .awayStateChanged(isAway, isMarketingMode):
                guard state.appState == .monitoring, !isMarketingMode else { return finish() }

                let result = PostureEngine.processAwayChange(
                    isAway: isAway,
                    state: state.monitoringState
                )
                state.monitoringState = result.newState

                guard result.shouldUpdateUI else { return finish() }
                return finish(run { runtime in
                    await runtime.syncUI()
                    await runtime.updateBlur()
                })

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
                    return finish()
                }

                return finish(run { runtime in
                    if result.shouldApplyStartupCameraProfile {
                        await runtime.applyStartupCameraProfile(cameraProfile)
                    }
                    if result.shouldStartMonitoring {
                        await runtime.startMonitoring()
                    }
                    if result.shouldShowOnboarding {
                        await runtime.showOnboarding()
                    }
                })

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
                    return finish(run { runtime in
                        await runtime.beginMonitoringSession()
                    })
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
                    return finish(run { runtime in
                        await runtime.startMonitoring()
                    })
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
                    return finish(run { runtime in
                        await runtime.switchCameraToMatchingProfile(matchingProfile)
                        await runtime.startMonitoring()
                    })
                }

                if result.newState == previousState {
                    return finish(run { runtime in
                        await runtime.syncUI()
                    })
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
                    return finish(run { runtime in
                        await runtime.syncUI()
                    })
                case .switchToFallback(let startMonitoring):
                    return finish(run { runtime in
                        await runtime.switchCameraToFallback(fallbackCameraID, fallbackProfile)
                        if startMonitoring {
                            await runtime.startMonitoring()
                        }
                    })
                }

            case .calibrationAuthorizationDenied(let isCalibrated):
                state.appState = PostureEngine.stateWhenCalibrationAuthorizationDenied(
                    isCalibrated: isCalibrated
                )
                return finish(run { runtime in
                    await runtime.showCalibrationPermissionDeniedAlert()
                })

            case .calibrationOpenSettingsRequested:
                return finish(run { runtime in
                    await runtime.openPrivacySettings()
                })

            case .calibrationRetryRequested:
                return finish(run { runtime in
                    await runtime.retryCalibration()
                })

            case .calibrationAuthorizationGranted:
                state.appState = PostureEngine.stateWhenCalibrationAuthorizationGranted()
                return finish()

            case .calibrationStartFailed(let errorMessage):
                state.appState = PostureEngine.unavailableState(for: state.activeSource)
                if state.activeSource == .camera {
                    return finish(run { runtime in
                        await runtime.showCameraCalibrationRetryAlert(errorMessage)
                    })
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
                    return finish(run { runtime in
                        await runtime.startMonitoring()
                    })
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
                return finish(run { runtime in
                    await runtime.startMonitoring()
                })

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
                    return finish(run { runtime in
                        await runtime.startMonitoring()
                    })
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

                guard result.shouldSwitchToProfileCamera || result.shouldStartMonitoring else {
                    return finish()
                }

                return finish(run { runtime in
                    if result.shouldSwitchToProfileCamera {
                        await runtime.switchCameraToMatchingProfile(matchingProfile)
                    }
                    if result.shouldStartMonitoring {
                        await runtime.startMonitoring()
                    }
                })

            case .cameraSelectionChanged:
                state.appState = PostureEngine.stateWhenCameraSelectionChanges(
                    currentState: state.appState,
                    trackingSource: state.activeSource
                )
                if state.activeSource == .camera {
                    return finish(run { runtime in
                        await runtime.switchCameraToSelected()
                    })
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

                guard result.didSwitchSource || result.shouldStartMonitoring else {
                    return finish()
                }

                return finish(run { runtime in
                    if result.didSwitchSource {
                        await runtime.stopDetector(previousSource)
                        await runtime.persistTrackingSource()
                    }
                    if result.shouldStartMonitoring {
                        await runtime.startMonitoring()
                    }
                })

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
        return run { runtime in
            if needsStopOld {
                await runtime.stopDetector(previousSource)
            }
            if needsBeginMonitoring {
                await runtime.beginMonitoringSession()
            }
            await runtime.persistTrackingSource()
            await runtime.syncUI()
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
    var updateBlur: @Sendable () async -> Void
    var trackAnalytics: @Sendable (TimeInterval, Bool) async -> Void
    var recordSlouchEvent: @Sendable () async -> Void
    var stopDetector: @Sendable (TrackingSource) async -> Void
    var persistTrackingSource: @Sendable () async -> Void
    var showCalibrationPermissionDeniedAlert: @Sendable () async -> Void
    var openPrivacySettings: @Sendable () async -> Void
    var showCameraCalibrationRetryAlert: @Sendable (String?) async -> Void
    var retryCalibration: @Sendable () async -> Void
    var startCalibrationForSource: @Sendable (TrackingSource) async -> Void
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
        updateBlur: {},
        trackAnalytics: { _, _ in },
        recordSlouchEvent: {},
        stopDetector: { _ in },
        persistTrackingSource: {},
        showCalibrationPermissionDeniedAlert: {},
        openPrivacySettings: {},
        showCameraCalibrationRetryAlert: { _ in },
        retryCalibration: {},
        startCalibrationForSource: { _ in }
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
