import AppKit
import os.log

private let log = OSLog(subsystem: "com.thelazydeveloper.dorso", category: "Tracking")

/// Context gathered at startup to decide between monitoring and onboarding.
struct InitialSetupContext {
    let profile: ProfileData?
    let profileCameraAvailable: Bool
    let hasValidAirPodsCalibration: Bool
}

extension AppDelegate {
    // MARK: - Store Transition Application

    /// Applies the observable consequences of a tracking-store state change:
    /// state-machine transitions, detector start/stop, and UI refresh.
    func applyTrackingStoreTransition(
        from oldTrackingState: TrackingFeature.State,
        to newTrackingState: TrackingFeature.State,
        applyStateTransition: Bool = true
    ) {
        if applyStateTransition, oldTrackingState.appState != newTrackingState.appState {
            handleStateTransition(from: oldTrackingState.appState, to: newTrackingState.appState)
        } else if oldTrackingState.activeSource != newTrackingState.activeSource {
            syncDetectorToState()
            syncUIToState()
        } else if oldTrackingState.manualSource != newTrackingState.manualSource {
            syncDetectorToState()
        }
        if oldTrackingState.activeSource != newTrackingState.activeSource {
            onActiveSourceChanged?()
        }
    }

    private func handleStateTransition(from oldState: AppState, to newState: AppState) {
        os_log(.info, log: log, "State transition: %{public}@ -> %{public}@", String(describing: oldState), String(describing: newState))
        syncDetectorToState()
        if !newState.isActive {
            clearBlur()
            warningOverlayManager.targetIntensity = 0
            warningOverlayManager.updateWarning()
        }
        if newState == .monitoring {
            applyActiveSettingsProfile()
        }
        syncUIToState()
    }

    // MARK: - Detector and UI Sync

    func syncDetectorToState() {
        if let syncDetectorToStateOverride {
            syncDetectorToStateOverride()
            return
        }

        let activeSource = activeTrackingSource
        let shouldRun = PostureEngine.shouldDetectorRun(for: state, trackingSource: activeSource)

        // Always stop the other detector so in-flight starts are cancelled
        // even if that detector has not flipped isActive=true yet.
        // But don't stop a detector that's currently being calibrated.
        let calSource = calibratingSource
        let isAutomatic = trackingMode == .automatic
        if activeSource == .camera {
            if calSource != .airpods {
                airPodsDetector.stop()
                // In automatic mode, keep AirPods connection monitoring alive
                // so we can detect when they're put back in for auto-return.
                if isAutomatic {
                    airPodsDetector.startConnectionMonitoring()
                }
            }
        } else {
            if calSource != .camera { cameraDetector.stop() }
            // Stop connection-only monitoring since AirPods detector is now active
            airPodsDetector.stopConnectionMonitoring()
        }

        // Start/stop the active detector
        if shouldRun {
            if !activeDetector.isActive {
                activeDetector.start { [weak self] success, error in
                    if !success, let error = error {
                        os_log(.error, log: log, "Failed to start detector: %{public}@", error)
                        Task { @MainActor in
                            guard let self else { return }
                            await self.sendTrackingAction(
                                .runtimeDetectorStartFailed(trackingSource: self.trackingSource)
                            )
                        }
                    }
                }
            }
        } else {
            // Always call stop() so in-flight starts are cancelled even if
            // the detector has not yet flipped isActive=true.
            activeDetector.stop()
        }
    }

    func syncUIToState() {
        let uiState = PostureUIState.derive(
            from: state,
            isCalibrated: isCalibrated,
            isCurrentlyAway: isCurrentlyAway,
            isCurrentlySlouching: isCurrentlySlouching,
            trackingSource: activeTrackingSource,
            isOnFallback: trackingStore.withState { $0.isOnFallback }
        )

        menuBarManager.updateStatus(text: uiState.statusText, icon: uiState.icon.menuBarIcon)
        menuBarManager.updateEnabledState(uiState.isEnabled)
        menuBarManager.updateRecalibrateEnabled(uiState.canRecalibrate)
    }

    func updateSourceReadiness() {
        let cameraReadiness = TrackingSourceReadiness(
            permissionGranted: true,
            connected: !cameraDetector.getAvailableCameras().isEmpty,
            calibrated: cameraCalibration?.isValid ?? false,
            available: true
        )
        let airPodsReadiness = TrackingSourceReadiness(
            permissionGranted: true,
            connected: airPodsDetector.isConnected,
            calibrated: airPodsCalibration?.isValid ?? false,
            available: airPodsDetector.isAvailable
        )
        applyTrackingAction(.sourceReadinessChanged(source: .camera, readiness: cameraReadiness))
        applyTrackingAction(.sourceReadinessChanged(source: .airpods, readiness: airPodsReadiness))
    }

    // MARK: - Detector Setup

    func setupDetectors() {
        // Configure camera detector
        cameraDetector.blurWhenAway = blurWhenAway
        cameraDetector.baseFrameInterval = 1.0 / activeDetectionMode.frameRate

        cameraDetector.onPostureReading = { [weak self] reading in
            Task { @MainActor in
                await self?.handlePostureReading(reading)
            }
        }

        cameraDetector.onAwayStateChange = { [weak self] isAway in
            Task { @MainActor in
                await self?.handleAwayStateChange(isAway)
            }
        }

        // Configure AirPods detector
        airPodsDetector.onPostureReading = { [weak self] reading in
            Task { @MainActor in
                await self?.handlePostureReading(reading)
            }
        }

        airPodsDetector.onConnectionStateChange = { [weak self] isConnected in
            Task { @MainActor in
                await self?.handleConnectionStateChange(isConnected)
            }
        }
    }

    // MARK: - Detector Events

    private func handleConnectionStateChange(_ isConnected: Bool) async {
        let transition = await sendTrackingAction(.airPodsConnectionChanged(isConnected))

        if isConnected,
           transition.oldState.appState == .paused(.airPodsRemoved),
           transition.newState.appState == .monitoring {
            os_log(.info, log: log, "AirPods back in ears - resuming monitoring")
        } else if !isConnected,
                  transition.oldState.appState == .monitoring,
                  transition.newState.appState == .paused(.airPodsRemoved) {
            os_log(.info, log: log, "AirPods removed - pausing monitoring")
        }
    }

    private func handlePostureReading(_ reading: PostureReading) async {
        await sendTrackingAction(
            .postureReadingReceived(reading, isMarketingMode: isMarketingMode),
            applyStateTransition: false
        )
    }

    func handleAwayStateChange(_ isAway: Bool) async {
        await sendTrackingAction(
            .awayStateChanged(isAway, isMarketingMode: isMarketingMode),
            applyStateTransition: false
        )
    }

    // MARK: - Enable/Disable

    func toggleEnabled() async {
        await sendTrackingAction(
            .toggleEnabled(
                trackingSource: trackingSource,
                isCalibrated: isCalibrated,
                detectorAvailable: activeDetector.isAvailable
            )
        )
        saveSettings()
    }

    // MARK: - Initial Setup Flow

    func initialSetupFlow() async {
        guard !setupComplete else { return }
        setupComplete = true

        updateSourceReadiness()
        let context = makeInitialSetupContext()
        await sendTrackingAction(
            .initialSetupEvaluated(
                isMarketingMode: isMarketingMode,
                hasCameraProfile: context.profile != nil,
                profileCameraAvailable: context.profileCameraAvailable,
                hasValidAirPodsCalibration: context.hasValidAirPodsCalibration,
                cameraProfile: context.profile
            )
        )
    }

    private func makeInitialSetupContext() -> InitialSetupContext {
        if let initialSetupContextOverride {
            return initialSetupContextOverride()
        }

        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = loadProfile(forKey: configKey)
        let cameras = cameraDetector.getAvailableCameras()
        let profileCameraAvailable = profile.map { profile in
            cameras.contains(where: { $0.uniqueID == profile.cameraID })
        } ?? false

        return InitialSetupContext(
            profile: profile,
            profileCameraAvailable: profileCameraAvailable,
            hasValidAirPodsCalibration: airPodsCalibration?.isValid ?? false
        )
    }

    func showOnboarding() {
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.show(
            appDelegate: self,
            cameraDetector: cameraDetector,
            airPodsDetector: airPodsDetector
        ) { [weak self] source, cameraID in
            Task { @MainActor in
                guard let self else { return }

                await self.switchTrackingSource(to: source)
                if let cameraID = cameraID {
                    self.cameraDetector.selectedCameraID = cameraID
                }
                self.saveSettings()

                // Start calibration
                self.startCalibration()
            }
        }
    }

    // MARK: - Tracking Source Management

    func switchTrackingSource(to source: TrackingSource) async {
        let isNewSourceCalibrated: Bool
        switch source {
        case .camera:
            isNewSourceCalibrated = isMarketingMode || (cameraCalibration?.isValid ?? false)
        case .airpods:
            isNewSourceCalibrated = isMarketingMode || (airPodsCalibration?.isValid ?? false)
        }

        await sendTrackingAction(
            .switchTrackingSource(
                source,
                isNewSourceCalibrated: isNewSourceCalibrated
            )
        )
    }

    func setTrackingMode(_ mode: TrackingMode) async {
        updateSourceReadiness()
        await sendTrackingAction(.setTrackingMode(mode))
        saveSettings()
    }

    func setPreferredSource(_ source: TrackingSource) async {
        updateSourceReadiness()
        await sendTrackingAction(.setPreferredSource(source))
        saveSettings()
    }

    func setPauseOnTheGoEnabled(_ isEnabled: Bool) async {
        pauseOnTheGo = isEnabled
        saveSettings()
        await sendTrackingAction(.pauseOnTheGoSettingChanged(isEnabled: isEnabled))
    }

    // MARK: - Monitoring

    func startMonitoring() async {
        let transition = await sendTrackingAction(
            .startMonitoringRequested(
                isMarketingMode: isMarketingMode,
                trackingSource: trackingSource,
                isCalibrated: isCalibrated,
                isConnected: activeDetector.isConnected
            )
        )

        if transition.newState.appState == .paused(.airPodsRemoved) {
            os_log(.info, log: log, "AirPods not in ears - pausing instead of monitoring")
        }
    }

    // MARK: - Settings Profile

    func applyActiveSettingsProfile() {
        applyTrackingAction(
            .setPostureConfiguration(
                intensity: Double(activeIntensity),
                warningOnsetDelay: activeWarningOnsetDelay
            )
        )
        activeDetector.updateParameters(intensity: activeIntensity, deadZone: activeDeadZone)
        applyDetectionMode()

        guard setupComplete else { return }

        if warningOverlayManager.mode != activeWarningMode {
            switchWarningMode()
        }

        let desiredColorData = activeSettingsProfile?.warningColorData
        if desiredColorData != appliedWarningColorData {
            appliedWarningColorData = desiredColorData
            updateWarningColor(activeWarningColor)
        }
    }
}
