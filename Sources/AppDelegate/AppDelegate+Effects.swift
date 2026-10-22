import AppKit

extension AppDelegate {
    // MARK: - Reducer Effect Execution

    /// The single funnel through which every reducer-requested side effect
    /// runs. Fires the test observer, then executes the effect.
    func performTrackingEffect(_ intent: TrackingFeature.EffectIntent) async {
        trackingEffectIntentObserver?(intent)

        switch intent {
        case .startMonitoring:
            await startMonitoring()

        case .beginMonitoringSession:
            beginMonitoringSession()

        case .applyStartupCameraProfile(let profile):
            guard let profile else { return }
            cameraDetector.selectedCameraID = profile.cameraID
            applyCameraCalibration(from: profile)

        case .showOnboarding:
            if let showOnboardingHandler {
                showOnboardingHandler()
            } else {
                showOnboarding()
            }

        case .switchCamera(let switchIntent):
            switchCamera(switchIntent)

        case .syncUI:
            syncUIToState()

        case .updateBlur:
            updateBlur()

        case .trackAnalytics(let interval, let isSlouching):
            AnalyticsManager.shared.trackTime(interval: interval, isSlouching: isSlouching)

        case .recordSlouchEvent:
            AnalyticsManager.shared.recordSlouchEvent()

        case .stopDetector(let source):
            detector(for: source).stop()

        case .persistTrackingSource:
            saveSettings()

        case .showCalibrationPermissionDeniedAlert, .openPrivacySettings, .showCameraCalibrationRetryAlert,
            .retryCalibration:
            await performCalibrationEffect(intent)

        case .scheduleTimedPauseEnd(let date):
            scheduleTimedPauseEnd(at: date)

        case .cancelTimedPauseEnd:
            cancelTimedPauseEnd()
        }
    }

    private func beginMonitoringSession() {
        if let beginMonitoringSessionHandler {
            beginMonitoringSessionHandler()
            return
        }
        guard let calibration = currentCalibration else { return }
        activeDetector.beginMonitoring(
            with: calibration,
            intensity: activeIntensity,
            deadZone: activeDeadZone
        )
    }

    private func switchCamera(_ switchIntent: TrackingFeature.CameraSwitchIntent) {
        switch switchIntent {
        case .matchingProfile(let profile):
            guard let profile else { return }
            cameraDetector.selectedCameraID = profile.cameraID
            applyCameraCalibration(from: profile)
            cameraDetector.switchCamera(to: profile.cameraID)

        case .fallback(let cameraID, let profile):
            guard let cameraID else { return }
            cameraDetector.selectedCameraID = cameraID
            if let profile, profile.cameraID == cameraID {
                applyCameraCalibration(from: profile)
            }
            cameraDetector.switchCamera(to: cameraID)

        case .selectedCamera:
            guard let selectedCameraID else { return }
            cameraDetector.switchCamera(to: selectedCameraID)
        }
    }

    private func performCalibrationEffect(_ intent: TrackingFeature.EffectIntent) async {
        switch intent {
        case .showCalibrationPermissionDeniedAlert:
            await showCalibrationPermissionDeniedAlert()

        case .openPrivacySettings:
            openPrivacySettings()

        case .showCameraCalibrationRetryAlert(let message):
            await showCameraCalibrationRetryAlert(message: message)

        case .retryCalibration:
            if let retryCalibrationHandler {
                retryCalibrationHandler()
            } else {
                startCalibration()
            }

        default:
            break
        }
    }

    func applyCameraCalibration(from profile: ProfileData) {
        cameraCalibration = CameraCalibrationData(
            goodPostureY: profile.goodPostureY,
            badPostureY: profile.badPostureY,
            neutralY: profile.neutralY,
            postureRange: profile.postureRange,
            cameraID: profile.cameraID
        )
    }
}
