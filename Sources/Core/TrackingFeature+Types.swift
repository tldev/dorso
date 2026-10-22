import Foundation

extension TrackingFeature {
    // Observer/testing surface for runtime calls.
    enum EffectIntent: Equatable {
        case startMonitoring
        case beginMonitoringSession
        case showOnboarding
        /// Points the camera detector at a device; the reducer has already
        /// updated the selected camera and calibration in state
        case switchCamera(to: String)
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

        var cameraCalibration: CameraCalibrationData?
        var airPodsCalibration: AirPodsCalibrationData?
        var selectedCameraID: String?
        /// Demo mode for screenshots: every source counts as calibrated and
        /// posture readings never warn
        var isMarketingMode = false

        var stateBeforeLock: AppState?
        var monitoringState = PostureMonitoringState()
        var postureConfig = PostureConfig()
        var lastPostureReadingTime: Date?
        var pauseOnTheGoEnabled = false
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
            cameraCalibration: CameraCalibrationData? = nil,
            airPodsCalibration: AirPodsCalibrationData? = nil,
            selectedCameraID: String? = nil,
            isMarketingMode: Bool = false,
            stateBeforeLock: AppState? = nil,
            monitoringState: PostureMonitoringState = PostureMonitoringState(),
            postureConfig: PostureConfig = PostureConfig(),
            lastPostureReadingTime: Date? = nil,
            pauseOnTheGoEnabled: Bool = false,
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
            self.cameraCalibration = cameraCalibration
            self.airPodsCalibration = airPodsCalibration
            self.selectedCameraID = selectedCameraID
            self.isMarketingMode = isMarketingMode
            self.stateBeforeLock = stateBeforeLock
            self.monitoringState = monitoringState
            self.postureConfig = postureConfig
            self.lastPostureReadingTime = lastPostureReadingTime
            self.pauseOnTheGoEnabled = pauseOnTheGoEnabled
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

        func calibration(for source: TrackingSource) -> CalibrationData? {
            switch source {
            case .camera: return cameraCalibration
            case .airpods: return airPodsCalibration
            }
        }

        func isCalibrated(_ source: TrackingSource) -> Bool {
            isMarketingMode || (calibration(for: source)?.isValid ?? false)
        }

        // MARK: - Calibration Mutations
        // The only writers of the calibrations, so readiness never drifts from them

        mutating func setCameraCalibration(_ calibration: CameraCalibrationData?) {
            cameraCalibration = calibration
            cameraReadiness.calibrated = calibration?.isValid ?? false
        }

        mutating func setAirPodsCalibration(_ calibration: AirPodsCalibrationData?) {
            airPodsCalibration = calibration
            airPodsReadiness.calibrated = calibration?.isValid ?? false
        }

        /// Selects a saved profile's camera and loads its calibration. Returns
        /// whether the selected camera changed.
        @discardableResult
        mutating func applyCameraProfile(_ profile: ProfileData) -> Bool {
            let cameraChanged = selectedCameraID != profile.cameraID
            selectedCameraID = profile.cameraID
            setCameraCalibration(CameraCalibrationData(profile: profile))
            return cameraChanged
        }
    }

    enum CompletedCalibration: Equatable {
        case camera(CameraCalibrationData)
        case airPods(AirPodsCalibrationData)

        var source: TrackingSource {
            switch self {
            case .camera: return .camera
            case .airPods: return .airpods
            }
        }
    }

    enum Action: Equatable {
        case appLaunched
        case setAppState(AppState)
        case setMarketingMode(Bool)
        case cameraCalibrationChanged(CameraCalibrationData?)
        case airPodsCalibrationChanged(AirPodsCalibrationData?)
        case setSelectedCamera(String?)
        case toggleEnabled(detectorAvailable: Bool)
        case setTrackingMode(TrackingMode)
        case setManualSource(TrackingSource)
        case setPreferredSource(TrackingSource)
        case setAutoReturnEnabled(Bool)
        case setPostureConfiguration(intensity: Double, warningOnsetDelay: TimeInterval)
        case pauseOnTheGoSettingChanged(isEnabled: Bool)
        case postureReadingReceived(PostureReading)
        case awayStateChanged(Bool)
        case initialSetupEvaluated(cameraProfile: ProfileData?, profileCameraAvailable: Bool)
        case startMonitoringRequested(isConnected: Bool)
        case airPodsConnectionChanged(Bool)
        /// `matchingProfile` is the display setup's saved profile when it was
        /// calibrated with the camera that just connected
        case cameraConnected(matchingProfile: ProfileData?)
        case cameraDisconnected(cameraID: String, fallbackCameraID: String?, profile: ProfileData?)
        case calibrationAuthorizationDenied
        case calibrationOpenSettingsRequested
        case calibrationRetryRequested
        case calibrationAuthorizationGranted
        case calibrationStartFailed(errorMessage: String?)
        case runtimeDetectorStartFailed
        case calibrationCancelled
        case calibrationCompleted(CompletedCalibration)
        case screenLocked
        case screenUnlocked
        case powerSourceChanged(isOnBattery: Bool)
        case setPauseOnBatteryEnabled(Bool)
        case displayConfigurationChanged(
            isLaptopOnlyConfiguration: Bool,
            hasAnyCamera: Bool,
            hasMatchingProfileCamera: Bool,
            matchingProfile: ProfileData?
        )
        case cameraSelectionChanged(String)
        /// A desk was chosen; its profile is applied when its camera is connected
        case deskProfileApplied(ProfileData?, isCameraAvailable: Bool)
        case switchTrackingSource(TrackingSource)
        case sourceReadinessChanged(source: TrackingSource, readiness: TrackingSourceReadiness)
        case timedPauseRequested(until: Date)
        case timedPauseEnded
        /// Sent by the end timer with the deadline it was scheduled for, so a
        /// callback from a replaced timer cannot end a newer pause.
        case timedPauseDeadlineReached(Date)
    }
}
