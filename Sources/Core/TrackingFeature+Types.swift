import Foundation

extension TrackingFeature {
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
        case scheduleTimedPauseEnd(Date)
        case cancelTimedPauseEnd
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
        var pauseOnBatteryEnabled: Bool = false
        var isOnBattery: Bool = false
        /// End of a user-requested pause. Layered over `appState` rather than
        /// replacing it, so device and power transitions keep running
        /// underneath and decide what tracking resumes into.
        var timedPauseEnd: Date?

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
            lastPostureReadingTime: Date? = nil,
            pauseOnBatteryEnabled: Bool = false,
            isOnBattery: Bool = false,
            timedPauseEnd: Date? = nil
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
            self.pauseOnBatteryEnabled = pauseOnBatteryEnabled
            self.isOnBattery = isOnBattery
            self.timedPauseEnd = timedPauseEnd
        }

        /// The state the user experiences: `appState`, masked by an active
        /// timed pause. Detectors, posture processing, and UI follow this.
        var effectiveAppState: AppState {
            guard let timedPauseEnd, appState != .disabled, appState != .calibrating else {
                return appState
            }
            return .paused(.timed(until: timedPauseEnd))
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
        case powerSourceChanged(isOnBattery: Bool)
        case setPauseOnBatteryEnabled(Bool)
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
        case timedPauseRequested(until: Date)
        case timedPauseEnded
        /// Sent by the end timer with the deadline it was scheduled for, so a
        /// callback from a replaced timer cannot end a newer pause.
        case timedPauseDeadlineReached(Date)
    }
}
