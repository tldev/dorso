import AppKit
import AVFoundation
import Vision
import os.log
import ComposableArchitecture

private let log = OSLog(subsystem: "com.thelazydeveloper.dorso", category: "AppDelegate")

// MARK: - MenuBarIconType to MenuBarIcon Conversion

extension MenuBarIconType {
    var menuBarIcon: MenuBarIcon {
        switch self {
        case .good: return .good
        case .bad: return .bad
        case .away: return .away
        case .paused: return .paused
        case .calibrating: return .calibrating
        }
    }
}

struct InitialSetupContext {
    let profile: ProfileData?
    let profileCameraAvailable: Bool
    let hasValidAirPodsCalibration: Bool
}

// MARK: - App Delegate

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    // UI Components
    let menuBarManager = MenuBarManager()

    // Overlay windows and blur
    var windows: [NSWindow] = []
    var blurViews: [NSVisualEffectView] = []
    var currentBlurRadius: Int32 = 0
    var targetBlurRadius: Int32 = 0

    // Warning overlay (alternative to blur)
    var warningOverlayManager = WarningOverlayManager()
    let settingsProfileManager = SettingsProfileManager()
    private var appliedWarningColorData: Data?

    // MARK: - Posture Detectors

    let cameraDetector = CameraPostureDetector()
    let airPodsDetector = AirPodsPostureDetector()

    var trackingSource: TrackingSource = .camera {
        didSet {
            if oldValue != trackingSource {
                syncDetectorToState()
                if trackingActionDispatchDepth == 0 {
                    trackingStore.send(.setManualSource(trackingSource))
                }
            }
        }
    }

    var activeDetector: PostureDetector {
        trackingSource == .camera ? cameraDetector : airPodsDetector
    }

    // Calibration data storage
    var cameraCalibration: CameraCalibrationData?
    var airPodsCalibration: AirPodsCalibrationData?

    var currentCalibration: CalibrationData? {
        trackingSource == .camera ? cameraCalibration : airPodsCalibration
    }

    // Legacy camera ID accessor for settings
    var selectedCameraID: String? {
        get { cameraDetector.selectedCameraID }
        set { cameraDetector.selectedCameraID = newValue }
    }

    // Calibration
    var calibrationController: CalibrationWindowController?
    var isCalibrated: Bool {
        isMarketingMode || (currentCalibration?.isValid ?? false)
    }

    // Settings
    var useCompatibilityMode = false
    var blurWhenAway = false {
        didSet {
            cameraDetector.blurWhenAway = blurWhenAway
            if !blurWhenAway {
                handleAwayStateChange(false)
            }
        }
    }
    var showInDock = false
    var pauseOnTheGo = false
    var settingsWindowController = SettingsWindowController()
    var analyticsWindowController: AnalyticsWindowController?
    var onboardingWindowController: OnboardingWindowController?

    // Observers and monitors
    let displayMonitor = DisplayMonitor()
    let cameraObserver = CameraObserver()
    let screenLockObserver = ScreenLockObserver()
    let hotkeyManager = HotkeyManager()
    var stateBeforeLock: AppState?
    private var trackingActionDispatchDepth = 0
    lazy var trackingStore: StoreOf<TrackingFeature> = {
        Store(initialState: TrackingFeature.State()) {
            TrackingFeature()
        } withDependencies: { [weak self] dependencies in
            dependencies.trackingEffectExecutor.execute = { intent in
                guard let self else { return }
                await self.executeTrackingEffectIntent(intent)
            }
        }
    }()
    var trackingEffectIntentObserver: ((TrackingFeature.EffectIntent) -> Void)?
    var calibrationPermissionDeniedAlertDecision: ((TrackingSource) -> Bool)?
    var cameraCalibrationRetryAlertDecision: ((String?) -> Bool)?
    var openPrivacySettingsHandler: (() -> Void)?
    var retryCalibrationHandler: (() -> Void)?
    var beginMonitoringSessionHandler: (() -> Void)?
    var showOnboardingHandler: (() -> Void)?
    var initialSetupContextOverride: (() -> InitialSetupContext)?
    var syncDetectorToStateOverride: (() -> Void)?

    // Detection state - consolidated into PostureEngine types
    var monitoringState = PostureMonitoringState()
    var postureConfig = PostureConfig()
    private var lastPostureReadingTime: Date?

    // Computed properties for backward compatibility
    var isCurrentlySlouching: Bool {
        get { monitoringState.isCurrentlySlouching }
        set { monitoringState.isCurrentlySlouching = newValue }
    }
    var isCurrentlyAway: Bool {
        get { monitoringState.isCurrentlyAway }
        set { monitoringState.isCurrentlyAway = newValue }
    }
    var postureWarningIntensity: CGFloat {
        get { monitoringState.postureWarningIntensity }
        set { monitoringState.postureWarningIntensity = newValue }
    }

    // Global keyboard shortcut
    var toggleShortcutEnabled = true
    var toggleShortcut = KeyboardShortcut.defaultShortcut

    // Frame throttling
    var frameInterval: TimeInterval {
        isCurrentlySlouching ? 0.1 : (1.0 / activeDetectionMode.frameRate)
    }

    var activeSettingsProfile: SettingsProfile? {
        settingsProfileManager.activeProfile
    }

    var activeWarningMode: WarningMode {
        activeSettingsProfile?.warningMode ?? .blur
    }

    var activeWarningColor: NSColor {
        activeSettingsProfile?.warningColor ?? WarningDefaults.color
    }

    var activeDeadZone: CGFloat {
        CGFloat(activeSettingsProfile?.deadZone ?? 0.03)
    }

    var activeIntensity: CGFloat {
        CGFloat(activeSettingsProfile?.intensity ?? 1.0)
    }

    var activeWarningOnsetDelay: Double {
        activeSettingsProfile?.warningOnsetDelay ?? 0.0
    }

    var activeDetectionMode: DetectionMode {
        activeSettingsProfile?.detectionMode ?? .balanced
    }

    var setupComplete = false
    var marketingModeOverride: Bool?

    var isMarketingMode: Bool {
        if let marketingModeOverride {
            return marketingModeOverride
        }
        return UserDefaults.standard.bool(forKey: "MarketingMode")
            || CommandLine.arguments.contains("--marketing-mode")
    }

    // MARK: - State Machine

    private var _state: AppState = .disabled
    var state: AppState {
        get { _state }
        set {
            guard newValue != _state else { return }
            let oldState = _state
            _state = newValue
            handleStateTransition(from: oldState, to: newValue)
            if trackingActionDispatchDepth == 0 {
                trackingStore.send(.setAppState(newValue))
            }
        }
    }

    private func handleStateTransition(from oldState: AppState, to newState: AppState) {
        os_log(.info, log: log, "State transition: %{public}@ -> %{public}@", String(describing: oldState), String(describing: newState))
        syncDetectorToState()
        if !newState.isActive {
            monitoringState.reset()
            clearBlur()
            postureWarningIntensity = 0
            warningOverlayManager.targetIntensity = 0
            warningOverlayManager.updateWarning()
        }
        if newState == .monitoring {
            applyActiveSettingsProfile()
        }
        syncUIToState()
    }

    @discardableResult
    private func sendTrackingAction(
        _ action: TrackingFeature.Action,
        applyStateTransition: Bool = true
    ) async -> (oldState: TrackingFeature.State, newState: TrackingFeature.State) {
        trackingActionDispatchDepth += 1
        defer { trackingActionDispatchDepth -= 1 }

        let oldState = trackingStore.withState { $0 }
        let storeTask = trackingStore.send(action)
        await storeTask.finish()
        let newState = trackingStore.withState { $0 }

        stateBeforeLock = newState.stateBeforeLock

        if applyStateTransition {
            if newState.appState != state {
                state = newState.appState
            }
        }

        return (oldState, newState)
    }

    private func syncDetectorToState() {
        if let syncDetectorToStateOverride {
            syncDetectorToStateOverride()
            return
        }

        let shouldRun = PostureEngine.shouldDetectorRun(for: state, trackingSource: trackingSource)

        // Always stop the other detector so in-flight starts are cancelled
        // even if that detector has not flipped isActive=true yet.
        if trackingSource == .camera {
            airPodsDetector.stop()
        } else {
            cameraDetector.stop()
        }

        // Start/stop the active detector
        if shouldRun {
            if !activeDetector.isActive {
                activeDetector.start { [weak self] success, error in
                    if !success, let error = error {
                        os_log(.error, log: log, "Failed to start detector: %{public}@", error)
                        Task { @MainActor in
                            guard let self else { return }
                            await self.sendTrackingAction(.runtimeDetectorStartFailed(trackingSource: self.trackingSource))
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

    private func syncUIToState() {
        let uiState = PostureUIState.derive(
            from: state,
            isCalibrated: isCalibrated,
            isCurrentlyAway: isCurrentlyAway,
            isCurrentlySlouching: isCurrentlySlouching,
            trackingSource: trackingSource
        )

        menuBarManager.updateStatus(text: uiState.statusText, icon: uiState.icon.menuBarIcon)
        menuBarManager.updateEnabledState(uiState.isEnabled)
        menuBarManager.updateRecalibrateEnabled(uiState.canRecalibrate)
    }

    // MARK: - App Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure analytics storage migration runs as soon as the app launches.
        _ = AnalyticsManager.shared

        loadSettings()

        if showInDock {
            NSApp.setActivationPolicy(.regular)
        }

        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = applyMacOSIconMask(to: icon)
        }

        setupDetectors()
        setupMenuBar()
        setupOverlayWindows()

        warningOverlayManager.mode = activeWarningMode
        warningOverlayManager.warningColor = activeWarningColor
        appliedWarningColorData = activeSettingsProfile?.warningColorData
        if activeWarningMode.usesWarningOverlay {
            warningOverlayManager.setupOverlayWindows()
        }

        setupObservers()

        Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBlur()
            }
        }

        if isMarketingMode {
            AnalyticsManager.shared.injectMarketingData()
        }

        Task { @MainActor in
            await self.initialSetupFlow()
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarManager.statusItem.button?.performClick(nil)
        return false
    }

    // MARK: - Detector Setup

    private func setupDetectors() {
        // Configure camera detector
        cameraDetector.blurWhenAway = blurWhenAway
        cameraDetector.baseFrameInterval = 1.0 / activeDetectionMode.frameRate

        cameraDetector.onPostureReading = { [weak self] reading in
            Task { @MainActor in
                self?.handlePostureReading(reading)
            }
        }

        cameraDetector.onAwayStateChange = { [weak self] isAway in
            Task { @MainActor in
                self?.handleAwayStateChange(isAway)
            }
        }

        // Configure AirPods detector
        airPodsDetector.onPostureReading = { [weak self] reading in
            Task { @MainActor in
                self?.handlePostureReading(reading)
            }
        }

        airPodsDetector.onConnectionStateChange = { [weak self] isConnected in
            Task { @MainActor in
                await self?.handleConnectionStateChange(isConnected)
            }
        }
    }

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

    private func handlePostureReading(_ reading: PostureReading) {
        guard state == .monitoring else { return }

        if isMarketingMode {
            monitoringState.isCurrentlySlouching = false
            monitoringState.postureWarningIntensity = 0
            monitoringState.consecutiveBadFrames = 0
            syncUIToState()
            updateBlur()
            return
        }

        // Use the detector's capture timestamp for consistency
        let readingTime = reading.timestamp

        // Calculate actual elapsed time since last reading for accurate analytics.
        // Skip analytics on the first reading (no prior reference point).
        let actualElapsed: TimeInterval?
        if let last = lastPostureReadingTime {
            let raw = readingTime.timeIntervalSince(last)
            // Clamp: ignore negative deltas (clock adjustment) and cap at 2s
            // to avoid a single huge chunk after sleep/stall.
            actualElapsed = min(max(0, raw), 2.0)
        } else {
            actualElapsed = nil
        }
        lastPostureReadingTime = readingTime

        // Use PostureEngine for pure logic
        let result = PostureEngine.processReading(
            reading,
            state: monitoringState,
            config: postureConfig,
            currentTime: readingTime,
            frameInterval: actualElapsed ?? 0
        )

        // Update state
        monitoringState = result.newState

        // Execute effects
        for effect in result.effects {
            switch effect {
            case .trackAnalytics(let interval, let isSlouching):
                if actualElapsed != nil {
                    AnalyticsManager.shared.trackTime(interval: interval, isSlouching: isSlouching)
                }
            case .recordSlouchEvent:
                AnalyticsManager.shared.recordSlouchEvent()
            case .updateUI:
                syncUIToState()
            case .updateBlur:
                updateBlur()
            }
        }
    }

    private func handleAwayStateChange(_ isAway: Bool) {
        guard state == .monitoring else { return }
        if isMarketingMode { return }

        let result = PostureEngine.processAwayChange(isAway: isAway, state: monitoringState)
        monitoringState = result.newState

        if result.shouldUpdateUI {
            syncUIToState()
        }
    }

    // MARK: - Observers Setup

    private func setupObservers() {
        // Display configuration changes
        displayMonitor.onDisplayConfigurationChange = { [weak self] in
            Task { @MainActor in
                await self?.handleDisplayConfigurationChange()
            }
        }
        displayMonitor.startMonitoring()

        // Camera hot-plug
        cameraObserver.onCameraConnected = { [weak self] device in
            Task { @MainActor in
                await self?.handleCameraConnected(device)
            }
        }
        cameraObserver.onCameraDisconnected = { [weak self] device in
            Task { @MainActor in
                await self?.handleCameraDisconnected(device)
            }
        }
        cameraObserver.startObserving()

        // Screen lock/unlock
        screenLockObserver.onScreenLocked = { [weak self] in
            Task { @MainActor in
                await self?.handleScreenLocked()
            }
        }
        screenLockObserver.onScreenUnlocked = { [weak self] in
            Task { @MainActor in
                await self?.handleScreenUnlocked()
            }
        }
        screenLockObserver.startObserving()

        // Global hotkey
        hotkeyManager.configure(
            enabled: toggleShortcutEnabled,
            shortcut: toggleShortcut,
            onToggle: { [weak self] in
                Task { @MainActor in
                    await self?.toggleEnabled()
                }
            }
        )
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        menuBarManager.setup()
        menuBarManager.updateShortcut(enabled: toggleShortcutEnabled, shortcut: toggleShortcut)

        menuBarManager.onToggleEnabled = { [weak self] in
            Task { @MainActor in
                await self?.toggleEnabled()
            }
        }
        menuBarManager.onRecalibrate = { [weak self] in
            Task { @MainActor in
                self?.startCalibration()
            }
        }
        menuBarManager.onShowAnalytics = { [weak self] in
            Task { @MainActor in
                self?.showAnalytics()
            }
        }
        menuBarManager.onOpenSettings = { [weak self] in
            Task { @MainActor in
                self?.openSettings()
            }
        }
        menuBarManager.onQuit = { [weak self] in
            Task { @MainActor in
                self?.quit()
            }
        }
    }

    // MARK: - Menu Actions

    private func toggleEnabled() async {
        await sendTrackingAction(
            .toggleEnabled(
                trackingSource: trackingSource,
                isCalibrated: isCalibrated,
                detectorAvailable: activeDetector.isAvailable
            )
        )
        saveSettings()
    }

    private func showAnalytics() {
        if analyticsWindowController == nil {
            analyticsWindowController = AnalyticsWindowController()
        }
        analyticsWindowController?.showWindow(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettings() {
        settingsWindowController.showSettings(appDelegate: self, fromStatusItem: menuBarManager.statusItem)
    }

    private func quit() {
        cameraDetector.stop()
        airPodsDetector.stop()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Initial Setup Flow

    func initialSetupFlow() async {
        guard !setupComplete else { return }
        setupComplete = true

        let context = makeInitialSetupContext()
        _ = await sendTrackingAction(
            .initialSetupEvaluated(
                isMarketingMode: isMarketingMode,
                hasCameraProfile: context.profile != nil,
                profileCameraAvailable: context.profileCameraAvailable,
                hasValidAirPodsCalibration: context.hasValidAirPodsCalibration,
                cameraProfile: context.profile
            )
        )
    }

    func showOnboarding() {
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.show(
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

    func setPauseOnTheGoEnabled(_ isEnabled: Bool) async {
        pauseOnTheGo = isEnabled
        saveSettings()
        await sendTrackingAction(.pauseOnTheGoSettingChanged(isEnabled: isEnabled))
    }

    // MARK: - Calibration

    func startCalibration() {
        // Prevent multiple concurrent calibrations (use calibrationController as the lock)
        guard calibrationController == nil else { return }

        os_log(.info, log: log, "Starting calibration for %{public}@", trackingSource.displayName)

        // Request authorization (this shows permission dialog if needed)
        activeDetector.requestAuthorization { [weak self] authorized in
            Task { @MainActor in
                guard let self else { return }

                if !authorized {
                    os_log(.error, log: log, "Authorization denied for %{public}@", self.trackingSource.displayName)

                    await self.sendTrackingAction(
                        .calibrationAuthorizationDenied(isCalibrated: self.isCalibrated)
                    )
                    return
                }

                // Authorization granted - now start calibration
                await self.sendTrackingAction(.calibrationAuthorizationGranted)
                self.startDetectorAndShowCalibration()
            }
        }
    }

    private func startDetectorAndShowCalibration() {
        // Double-check no calibration controller already exists
        guard calibrationController == nil else {
            os_log(.info, log: log, "Skipping calibration window - already exists")
            return
        }

        activeDetector.start { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }

                if !success {
                    os_log(.error, log: log, "Failed to start detector for calibration: %{public}@", error ?? "unknown")
                    await self.sendTrackingAction(.calibrationStartFailed(errorMessage: error))
                    return
                }

                self.calibrationController = CalibrationWindowController()
                self.calibrationController?.start(
                    detector: self.activeDetector,
                    onComplete: { [weak self] values in
                        Task { @MainActor in
                            await self?.finishCalibration(values: values)
                        }
                    },
                    onCancel: { [weak self] in
                        Task { @MainActor in
                            await self?.cancelCalibration()
                        }
                    }
                )
            }
        }
    }

    func finishCalibration(values: [CalibrationSample]) async {
        guard values.count >= 4 else {
            await cancelCalibration()
            return
        }

        os_log(.info, log: log, "Finishing calibration with %d values", values.count)

        // Create calibration data using the detector
        guard let calibration = activeDetector.createCalibrationData(from: values) else {
            await cancelCalibration()
            return
        }

        // Store calibration
        if let cameraCalibration = calibration as? CameraCalibrationData {
            self.cameraCalibration = cameraCalibration
            // Also save as legacy profile
            let profile = ProfileData(
                goodPostureY: cameraCalibration.goodPostureY,
                badPostureY: cameraCalibration.badPostureY,
                neutralY: cameraCalibration.neutralY,
                postureRange: cameraCalibration.postureRange,
                cameraID: cameraCalibration.cameraID
            )
            let configKey = DisplayMonitor.getCurrentConfigKey()
            saveProfile(forKey: configKey, data: profile)
        } else if let airPodsCalibration = calibration as? AirPodsCalibrationData {
            self.airPodsCalibration = airPodsCalibration
        }

        saveSettings()
        calibrationController = nil

        await sendTrackingAction(.calibrationCompleted)
    }

    func cancelCalibration() async {
        calibrationController = nil
        await sendTrackingAction(.calibrationCancelled(isCalibrated: isCalibrated))
    }

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

    // MARK: - Camera Management (for Settings compatibility)

    func getAvailableCameras() -> [AVCaptureDevice] {
        return cameraDetector.getAvailableCameras()
    }

    func restartCamera() {
        guard trackingSource == .camera, selectedCameraID != nil else { return }

        Task { @MainActor in
            await self.applyCameraSelectionTransition()
        }
    }

    func applyDetectionMode() {
        cameraDetector.baseFrameInterval = 1.0 / activeDetectionMode.frameRate
    }

    func applyActiveSettingsProfile() {
        postureConfig.intensity = activeIntensity
        postureConfig.warningOnsetDelay = activeWarningOnsetDelay
        activeDetector.updateParameters(intensity: activeIntensity, deadZone: activeDeadZone)
        applyDetectionMode()

        guard setupComplete else { return }

        if warningOverlayManager.mode != activeWarningMode {
            switchWarningMode(to: activeWarningMode)
        }

        let desiredColorData = activeSettingsProfile?.warningColorData
        if desiredColorData != appliedWarningColorData {
            appliedWarningColorData = desiredColorData
            updateWarningColor(activeWarningColor)
        }
    }


    // MARK: - Camera Hot-Plug

    private func applyCameraCalibration(from profile: ProfileData) {
        cameraCalibration = CameraCalibrationData(
            goodPostureY: profile.goodPostureY,
            badPostureY: profile.badPostureY,
            neutralY: profile.neutralY,
            postureRange: profile.postureRange,
            cameraID: profile.cameraID
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

    private func executeTrackingEffectIntent(_ intent: TrackingFeature.EffectIntent) async {
        trackingEffectIntentObserver?(intent)

        switch intent {
        case .applyStartupCameraProfile(let matchingProfile):
            guard let matchingProfile else { return }
            cameraDetector.selectedCameraID = matchingProfile.cameraID
            applyCameraCalibration(from: matchingProfile)
        case .startMonitoring:
            await startMonitoring()
        case .beginMonitoringSession:
            if let beginMonitoringSessionHandler {
                beginMonitoringSessionHandler()
                return
            }
            guard let calibration = currentCalibration else { return }
            lastPostureReadingTime = nil
            activeDetector.beginMonitoring(with: calibration, intensity: activeIntensity, deadZone: activeDeadZone)
        case .showOnboarding:
            if let showOnboardingHandler {
                showOnboardingHandler()
            } else {
                showOnboarding()
            }
        case .syncUI:
            syncUIToState()
        case .stopDetector(let source):
            let detector: PostureDetector = source == .camera ? cameraDetector : airPodsDetector
            detector.stop()
        case .setTrackingSource(let source):
            trackingSource = source
        case .persistTrackingSource:
            saveSettings()
        case .resetMonitoringState:
            monitoringState.reset()
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
        case .switchCamera(let switchIntent):
            switch switchIntent {
            case .matchingProfile(let matchingProfile):
                guard let matchingProfile else { return }
                cameraDetector.selectedCameraID = matchingProfile.cameraID
                applyCameraCalibration(from: matchingProfile)
                cameraDetector.switchCamera(to: matchingProfile.cameraID)
            case let .fallback(fallbackCameraID, fallbackProfile):
                guard let fallbackCameraID else { return }
                cameraDetector.selectedCameraID = fallbackCameraID
                if let fallbackProfile, fallbackProfile.cameraID == fallbackCameraID {
                    applyCameraCalibration(from: fallbackProfile)
                }
                cameraDetector.switchCamera(to: fallbackCameraID)
            case .selectedCamera:
                guard let selectedCameraID else { return }
                cameraDetector.switchCamera(to: selectedCameraID)
            }
        }
    }

    private func showCalibrationPermissionDeniedAlert() async {
        if let calibrationPermissionDeniedAlertDecision {
            if calibrationPermissionDeniedAlertDecision(trackingSource) {
                await sendTrackingAction(.calibrationOpenSettingsRequested)
            }
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("alert.permissionRequired")
        alert.informativeText = trackingSource == .airpods
            ? L("alert.permissionRequired.airpods")
            : L("alert.permissionRequired.camera")
        alert.addButton(withTitle: L("alert.openSettings"))
        alert.addButton(withTitle: L("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            await sendTrackingAction(.calibrationOpenSettingsRequested)
        }
    }

    private func openPrivacySettings() {
        if let openPrivacySettingsHandler {
            openPrivacySettingsHandler()
            return
        }

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else { return }
        NSWorkspace.shared.open(url)
    }

    private func showCameraCalibrationRetryAlert(message: String?) async {
        if let cameraCalibrationRetryAlertDecision {
            if cameraCalibrationRetryAlertDecision(message) {
                await sendTrackingAction(.calibrationRetryRequested)
            }
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("alert.cameraNotAvailable")
        alert.informativeText = message ?? L("alert.cameraNotAvailable.message")
        alert.addButton(withTitle: L("alert.tryAgain"))
        alert.addButton(withTitle: L("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            await sendTrackingAction(.calibrationRetryRequested)
        }
    }

    private struct CameraDisconnectContext {
        let disconnectedCameraIsSelected: Bool
        let hasFallbackCamera: Bool
        let fallbackHasMatchingProfile: Bool
        let fallbackCamera: AVCaptureDevice?
        let fallbackProfile: ProfileData?
    }

    private struct CameraConnectedContext {
        let hasMatchingProfile: Bool
        let profile: ProfileData?
    }

    private func makeCameraDisconnectContext(for device: AVCaptureDevice) -> CameraDisconnectContext {
        let disconnectedCameraIsSelected = device.uniqueID == selectedCameraID
        let cameras = cameraDetector.getAvailableCameras()
        let fallbackCamera = cameras.first
        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = loadProfile(forKey: configKey)
        let fallbackHasMatchingProfile = fallbackCamera != nil && profile?.cameraID == fallbackCamera?.uniqueID

        return CameraDisconnectContext(
            disconnectedCameraIsSelected: disconnectedCameraIsSelected,
            hasFallbackCamera: fallbackCamera != nil,
            fallbackHasMatchingProfile: fallbackHasMatchingProfile,
            fallbackCamera: fallbackCamera,
            fallbackProfile: profile
        )
    }

    private func makeCameraConnectedContext(for device: AVCaptureDevice) -> CameraConnectedContext {
        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = loadProfile(forKey: configKey)

        return CameraConnectedContext(
            hasMatchingProfile: profile?.cameraID == device.uniqueID,
            profile: profile
        )
    }

    private struct DisplayConfigurationContext {
        let pauseOnTheGoEnabled: Bool
        let isLaptopOnlyConfiguration: Bool
        let hasAnyCamera: Bool
        let hasMatchingProfileCamera: Bool
        let selectedCameraMatchesProfile: Bool
        let profile: ProfileData?
    }

    private func makeDisplayConfigurationContext() -> DisplayConfigurationContext {
        let cameras = cameraDetector.getAvailableCameras()
        let hasAnyCamera = !cameras.isEmpty
        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = loadProfile(forKey: configKey)
        let hasMatchingProfileCamera = profile.map { profile in
            cameras.contains(where: { $0.uniqueID == profile.cameraID })
        } ?? false
        let selectedCameraMatchesProfile = profile.map { profile in
            selectedCameraID == profile.cameraID
        } ?? false

        return DisplayConfigurationContext(
            pauseOnTheGoEnabled: pauseOnTheGo,
            isLaptopOnlyConfiguration: DisplayMonitor.isLaptopOnlyConfiguration(),
            hasAnyCamera: hasAnyCamera,
            hasMatchingProfileCamera: hasMatchingProfileCamera,
            selectedCameraMatchesProfile: selectedCameraMatchesProfile,
            profile: profile
        )
    }

    private func applyCameraConnectedTransition(
        hasMatchingProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await sendTrackingAction(
            .cameraConnected(
                hasMatchingProfile: hasMatchingProfile,
                matchingProfile: matchingProfile
            )
        )
    }

    private func applyCameraSelectionTransition() async {
        await sendTrackingAction(.cameraSelectionChanged)
    }

    private func applyDisplayConfigurationTransition(
        pauseOnTheGoEnabled: Bool,
        isLaptopOnlyConfiguration: Bool,
        hasAnyCamera: Bool,
        hasMatchingProfileCamera: Bool,
        selectedCameraMatchesProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await sendTrackingAction(
            .displayConfigurationChanged(
                pauseOnTheGoEnabled: pauseOnTheGoEnabled,
                isLaptopOnlyConfiguration: isLaptopOnlyConfiguration,
                hasAnyCamera: hasAnyCamera,
                hasMatchingProfileCamera: hasMatchingProfileCamera,
                selectedCameraMatchesProfile: selectedCameraMatchesProfile,
                matchingProfile: matchingProfile
            )
        )
    }

    private func applyCameraDisconnectedTransition(
        disconnectedCameraIsSelected: Bool,
        hasFallbackCamera: Bool,
        fallbackHasMatchingProfile: Bool,
        fallbackCamera: AVCaptureDevice?,
        fallbackProfile: ProfileData?
    ) async {
        await sendTrackingAction(
            .cameraDisconnected(
                disconnectedCameraIsSelected: disconnectedCameraIsSelected,
                hasFallbackCamera: hasFallbackCamera,
                fallbackHasMatchingProfile: fallbackHasMatchingProfile,
                fallbackCameraID: fallbackCamera?.uniqueID,
                fallbackProfile: fallbackProfile
            )
        )
    }

    private func handleCameraConnected(_ device: AVCaptureDevice) async {
        guard trackingSource == .camera else { return }
        let context = makeCameraConnectedContext(for: device)

        await applyCameraConnectedTransition(
            hasMatchingProfile: context.hasMatchingProfile,
            matchingProfile: context.profile
        )
    }

    private func handleCameraDisconnected(_ device: AVCaptureDevice) async {
        guard trackingSource == .camera else { return }
        let context = makeCameraDisconnectContext(for: device)

        await applyCameraDisconnectedTransition(
            disconnectedCameraIsSelected: context.disconnectedCameraIsSelected,
            hasFallbackCamera: context.hasFallbackCamera,
            fallbackHasMatchingProfile: context.fallbackHasMatchingProfile,
            fallbackCamera: context.fallbackCamera,
            fallbackProfile: context.fallbackProfile
        )
    }

    // MARK: - Screen Lock Detection

    private func handleScreenLocked() async {
        await sendTrackingAction(.screenLocked)
    }

    private func handleScreenUnlocked() async {
        await sendTrackingAction(.screenUnlocked)
    }

    // MARK: - Display Configuration

    private func handleDisplayConfigurationChange() async {
        rebuildOverlayWindows()

        guard state != .disabled else { return }
        let context = makeDisplayConfigurationContext()

        await applyDisplayConfigurationTransition(
            pauseOnTheGoEnabled: context.pauseOnTheGoEnabled,
            isLaptopOnlyConfiguration: context.isLaptopOnlyConfiguration,
            hasAnyCamera: context.hasAnyCamera,
            hasMatchingProfileCamera: context.hasMatchingProfileCamera,
            selectedCameraMatchesProfile: context.selectedCameraMatchesProfile,
            matchingProfile: context.profile
        )
    }

}

extension AppDelegate {
    func dispatchCameraConnectedTransitionForTesting(
        hasMatchingProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await applyCameraConnectedTransition(
            hasMatchingProfile: hasMatchingProfile,
            matchingProfile: matchingProfile
        )
    }

    func dispatchCameraSelectionTransitionForTesting() async {
        await applyCameraSelectionTransition()
    }

    func dispatchDisplayConfigurationTransitionForTesting(
        pauseOnTheGoEnabled: Bool,
        isLaptopOnlyConfiguration: Bool,
        hasAnyCamera: Bool,
        hasMatchingProfileCamera: Bool,
        selectedCameraMatchesProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await applyDisplayConfigurationTransition(
            pauseOnTheGoEnabled: pauseOnTheGoEnabled,
            isLaptopOnlyConfiguration: isLaptopOnlyConfiguration,
            hasAnyCamera: hasAnyCamera,
            hasMatchingProfileCamera: hasMatchingProfileCamera,
            selectedCameraMatchesProfile: selectedCameraMatchesProfile,
            matchingProfile: matchingProfile
        )
    }

    func dispatchCameraDisconnectedTransitionForTesting(
        disconnectedCameraIsSelected: Bool,
        hasFallbackCamera: Bool,
        fallbackHasMatchingProfile: Bool,
        fallbackCamera: AVCaptureDevice?,
        fallbackProfile: ProfileData?
    ) async {
        await applyCameraDisconnectedTransition(
            disconnectedCameraIsSelected: disconnectedCameraIsSelected,
            hasFallbackCamera: hasFallbackCamera,
            fallbackHasMatchingProfile: fallbackHasMatchingProfile,
            fallbackCamera: fallbackCamera,
            fallbackProfile: fallbackProfile
        )
    }

    func dispatchScreenLockedTransitionForTesting() async {
        await sendTrackingAction(.screenLocked)
    }

    func dispatchScreenUnlockedTransitionForTesting() async {
        await sendTrackingAction(.screenUnlocked)
    }

    func dispatchCalibrationAuthorizationDeniedTransitionForTesting() async {
        await sendTrackingAction(
            .calibrationAuthorizationDenied(isCalibrated: isCalibrated)
        )
    }

    func dispatchCalibrationStartFailedTransitionForTesting(
        errorMessage: String?
    ) async {
        await sendTrackingAction(.calibrationStartFailed(errorMessage: errorMessage))
    }

    func dispatchSwitchTrackingSourceTransitionForTesting(
        _ source: TrackingSource
    ) async {
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
}
