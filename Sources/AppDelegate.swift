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
    @MainActor
    final class TrackingCoordinator {
        unowned let appDelegate: AppDelegate

        init(appDelegate: AppDelegate) {
            self.appDelegate = appDelegate
        }
    }

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

    var trackingSource: TrackingSource {
        get { trackingStore.withState { $0.manualSource } }
        set {
            let oldTrackingState = trackingStore.withState { $0 }
            guard oldTrackingState.manualSource != newValue else { return }

            trackingStore.send(.setManualSource(newValue))
            let newTrackingState = trackingStore.withState { $0 }
            applyTrackingStoreTransition(from: oldTrackingState, to: newTrackingState)
        }
    }

    var activeDetector: PostureDetector {
        activeTrackingSource == .camera ? cameraDetector : airPodsDetector
    }

    var activeTrackingSource: TrackingSource {
        trackingStore.withState { $0.activeSource }
    }

    var trackingMode: TrackingMode {
        get { trackingStore.withState { $0.trackingMode } }
        set {
            let oldState = trackingStore.withState { $0 }
            trackingStore.send(.setTrackingMode(newValue))
            let newState = trackingStore.withState { $0 }
            applyTrackingStoreTransition(from: oldState, to: newState)
        }
    }

    // Calibration data storage
    var cameraCalibration: CameraCalibrationData?
    var airPodsCalibration: AirPodsCalibrationData?
    /// Which source is currently being calibrated (nil when not calibrating)
    var calibratingSource: TrackingSource?
    /// Called when calibration completes successfully (for UI refresh)
    var onCalibrationComplete: (() -> Void)?
    /// Called when active source changes (for UI refresh)
    var onActiveSourceChanged: (() -> Void)?

    var currentCalibration: CalibrationData? {
        activeTrackingSource == .camera ? cameraCalibration : airPodsCalibration
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
                Task { @MainActor in
                    await handleAwayStateChange(false)
                }
            }
        }
    }
    var showInDock = false
    var pauseOnTheGo = false
    var settingsWindowController = SettingsWindowController()
    var supportWindowController = SupportWindowController()
    var analyticsWindowController: AnalyticsWindowController?
    var onboardingWindowController: OnboardingWindowController?

    // Observers and monitors
    let displayMonitor = DisplayMonitor()
    let cameraObserver = CameraObserver()
    let screenLockObserver = ScreenLockObserver()
    let hotkeyManager = HotkeyManager()
    private lazy var trackingCoordinator = TrackingCoordinator(appDelegate: self)
    private var trackingActionDispatchDepth = 0
    lazy var trackingStore: StoreOf<TrackingFeature> = {
        Store(initialState: TrackingFeature.State()) {
            TrackingFeature()
        } withDependencies: { [weak self] dependencies in
            dependencies.trackingRuntime.startMonitoring = { [weak self] in
                await self?.runtimeStartMonitoring()
            }
            dependencies.trackingRuntime.beginMonitoringSession = { [weak self] in
                await self?.runtimeBeginMonitoringSession()
            }
            dependencies.trackingRuntime.applyStartupCameraProfile = { [weak self] profile in
                await self?.runtimeApplyStartupCameraProfile(profile)
            }
            dependencies.trackingRuntime.showOnboarding = { [weak self] in
                await self?.runtimeShowOnboarding()
            }
            dependencies.trackingRuntime.switchCameraToMatchingProfile = { [weak self] profile in
                await self?.runtimeSwitchCameraToMatchingProfile(profile)
            }
            dependencies.trackingRuntime.switchCameraToFallback = { [weak self] cameraID, profile in
                await self?.runtimeSwitchCameraToFallback(cameraID: cameraID, profile: profile)
            }
            dependencies.trackingRuntime.switchCameraToSelected = { [weak self] in
                await self?.runtimeSwitchCameraToSelected()
            }
            dependencies.trackingRuntime.syncUI = { [weak self] in
                await self?.runtimeSyncUI()
            }
            dependencies.trackingRuntime.updateBlur = { [weak self] in
                await self?.runtimeUpdateBlur()
            }
            dependencies.trackingRuntime.trackAnalytics = { [weak self] interval, isSlouching in
                await self?.runtimeTrackAnalytics(interval: interval, isSlouching: isSlouching)
            }
            dependencies.trackingRuntime.recordSlouchEvent = { [weak self] in
                await self?.runtimeRecordSlouchEvent()
            }
            dependencies.trackingRuntime.stopDetector = { [weak self] source in
                await self?.runtimeStopDetector(source)
            }
            dependencies.trackingRuntime.persistTrackingSource = { [weak self] in
                await self?.runtimePersistTrackingSource()
            }
            dependencies.trackingRuntime.showCalibrationPermissionDeniedAlert = { [weak self] in
                await self?.runtimeShowCalibrationPermissionDeniedAlert()
            }
            dependencies.trackingRuntime.openPrivacySettings = { [weak self] in
                await self?.runtimeOpenPrivacySettings()
            }
            dependencies.trackingRuntime.showCameraCalibrationRetryAlert = { [weak self] message in
                await self?.runtimeShowCameraCalibrationRetryAlert(message: message)
            }
            dependencies.trackingRuntime.retryCalibration = { [weak self] in
                await self?.runtimeRetryCalibration()
            }
            dependencies.trackingRuntime.startCalibrationForSource = { [weak self] source in
                await self?.runtimeStartCalibrationForSource(source)
            }
        }
    }()
    var trackingEffectIntentObserver: ((TrackingFeature.EffectIntent) -> Void)?
    var calibrationPermissionDeniedAlertDecision: ((TrackingSource) -> Bool)?
    var cameraCalibrationRetryAlertDecision: ((String?) -> Bool)?
    var openPrivacySettingsHandler: (() -> Void)?
    var openSupportURLHandler: ((URL) -> Void)?
    var retryCalibrationHandler: (() -> Void)?
    var beginMonitoringSessionHandler: (() -> Void)?
    var showOnboardingHandler: (() -> Void)?
    var initialSetupContextOverride: (() -> InitialSetupContext)?
    var syncDetectorToStateOverride: (() -> Void)?

    // Computed properties for backward compatibility
    var isCurrentlySlouching: Bool {
        trackingStore.withState { $0.monitoringState.isCurrentlySlouching }
    }
    var isCurrentlyAway: Bool {
        trackingStore.withState { $0.monitoringState.isCurrentlyAway }
    }
    var postureWarningIntensity: CGFloat {
        trackingStore.withState { $0.monitoringState.postureWarningIntensity }
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

    var state: AppState {
        get { trackingStore.withState { $0.appState } }
        set {
            let oldTrackingState = trackingStore.withState { $0 }
            guard oldTrackingState.appState != newValue else { return }

            trackingStore.send(.setAppState(newValue))
            let newTrackingState = trackingStore.withState { $0 }
            applyTrackingStoreTransition(from: oldTrackingState, to: newTrackingState)
        }
    }

    private func applyTrackingStoreTransition(
        from oldTrackingState: TrackingFeature.State,
        to newTrackingState: TrackingFeature.State,
        applyStateTransition: Bool = true
    ) {
        trackingCoordinator.applyTrackingStoreTransition(
            from: oldTrackingState,
            to: newTrackingState,
            applyStateTransition: applyStateTransition
        )
    }

    private func handleStateTransition(from oldState: AppState, to newState: AppState) {
        trackingCoordinator.handleStateTransition(from: oldState, to: newState)
    }

    @discardableResult
    private func sendTrackingAction(
        _ action: TrackingFeature.Action,
        applyStateTransition: Bool = true
    ) async -> (oldState: TrackingFeature.State, newState: TrackingFeature.State) {
        await trackingCoordinator.sendTrackingAction(action, applyStateTransition: applyStateTransition)
    }

    private func syncDetectorToState() {
        trackingCoordinator.syncDetectorToState()
    }

    private func syncUIToState() {
        trackingCoordinator.syncUIToState()
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
        withAccessoryActivationPolicy {
            setupOverlayWindows()

            warningOverlayManager.mode = activeWarningMode
            warningOverlayManager.warningColor = activeWarningColor
            appliedWarningColorData = activeSettingsProfile?.warningColorData
            if activeWarningMode.usesWarningOverlay {
                warningOverlayManager.setupOverlayWindows()
            }
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
        trackingCoordinator.setupDetectors()
    }

    private func handleConnectionStateChange(_ isConnected: Bool) async {
        await trackingCoordinator.handleConnectionStateChange(isConnected)
    }

    private func handlePostureReading(_ reading: PostureReading) async {
        await trackingCoordinator.handlePostureReading(reading)
    }

    private func handleAwayStateChange(_ isAway: Bool) async {
        await trackingCoordinator.handleAwayStateChange(isAway)
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
        menuBarManager.onOpenSupport = { [weak self] in
            Task { @MainActor in
                self?.showSupport()
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
        await trackingCoordinator.toggleEnabled()
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

    func showSupport() {
        supportWindowController.showSupport(appDelegate: self, fromStatusItem: menuBarManager.statusItem)
    }

    private func quit() {
        cameraDetector.stop()
        airPodsDetector.stop()
        NSApplication.shared.terminate(nil)
    }

    func openSupportPage() {
        guard let url = URL(string: "https://buymeacoffee.com/tjohnell") else { return }

        if let openSupportURLHandler {
            openSupportURLHandler(url)
            return
        }

        NSWorkspace.shared.open(url)
    }

    func restoreAccessoryActivationPolicyIfNeeded(excluding windowToIgnore: NSWindow? = nil) {
        guard !showInDock else { return }

        let hasOtherVisibleWindows = NSApp.windows.contains { window in
            guard window != windowToIgnore else { return false }
            return window.isVisible && !window.isMiniaturized
        }

        if !hasOtherVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Runs `block` while the app is temporarily `.accessory`, then restores
    /// the previous policy. Overlay and calibration windows only get Space
    /// semantics that render over a fullscreen app if they're created while
    /// Dorso is `.accessory` — a `.regular` context (onboarding/Settings open)
    /// poisons their Space association. We also capture and restore the key
    /// window so a visible Settings/Onboarding window doesn't get pushed to
    /// the back when the policy flips.
    func withAccessoryActivationPolicy(_ block: () -> Void) {
        let current = NSApp.activationPolicy()
        if current != .accessory {
            let previousKeyWindow = NSApp.keyWindow
            NSApp.setActivationPolicy(.accessory)
            block()
            NSApp.setActivationPolicy(current)
            if let previousKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                previousKeyWindow.makeKeyAndOrderFront(nil)
            }
        } else {
            block()
        }
    }

    // MARK: - Initial Setup Flow

    func initialSetupFlow() async {
        await trackingCoordinator.initialSetupFlow()
    }

    func showOnboarding() {
        trackingCoordinator.showOnboarding()
    }

    // MARK: - Tracking Source Management

    func switchTrackingSource(to source: TrackingSource) async {
        await trackingCoordinator.switchTrackingSource(to: source)
    }

    func setPauseOnTheGoEnabled(_ isEnabled: Bool) async {
        await trackingCoordinator.setPauseOnTheGoEnabled(isEnabled)
    }

    func setTrackingMode(_ mode: TrackingMode) async {
        trackingCoordinator.updateSourceReadiness()
        let oldState = trackingStore.withState { $0 }
        let storeTask = trackingStore.send(.setTrackingMode(mode))
        await storeTask.finish()
        let newState = trackingStore.withState { $0 }
        applyTrackingStoreTransition(from: oldState, to: newState)
        saveSettings()
    }

    func setPreferredSource(_ source: TrackingSource) async {
        trackingCoordinator.updateSourceReadiness()
        let oldState = trackingStore.withState { $0 }
        let storeTask = trackingStore.send(.setPreferredSource(source))
        await storeTask.finish()
        let newState = trackingStore.withState { $0 }
        applyTrackingStoreTransition(from: oldState, to: newState)
        saveSettings()
    }

    func startCalibrationForSource(_ source: TrackingSource) {
        trackingCoordinator.startCalibration(for: source)
    }

    // MARK: - Calibration

    func startCalibration() {
        trackingCoordinator.startCalibration()
    }

    private func startDetectorAndShowCalibration() {
        trackingCoordinator.startDetectorAndShowCalibration()
    }

    func finishCalibration(values: [CalibrationSample]) async {
        await trackingCoordinator.finishCalibration(values: values)
    }

    func cancelCalibration() async {
        await trackingCoordinator.cancelCalibration()
    }

    func startMonitoring() async {
        await trackingCoordinator.startMonitoring()
    }

    // MARK: - Camera Management (for Settings compatibility)

    func getAvailableCameras() -> [AVCaptureDevice] {
        return cameraDetector.getAvailableCameras()
    }

    func restartCamera() {
        guard activeTrackingSource == .camera, selectedCameraID != nil else { return }

        Task { @MainActor in
            await self.applyCameraSelectionTransition()
        }
    }

    func applyDetectionMode() {
        cameraDetector.baseFrameInterval = 1.0 / activeDetectionMode.frameRate
    }

    func applyActiveSettingsProfile() {
        trackingCoordinator.applyActiveSettingsProfile()
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

    private func runtimeStartMonitoring() async {
        await trackingCoordinator.runtimeStartMonitoring()
    }

    private func runtimeBeginMonitoringSession() async {
        await trackingCoordinator.runtimeBeginMonitoringSession()
    }

    private func runtimeApplyStartupCameraProfile(_ matchingProfile: ProfileData?) async {
        await trackingCoordinator.runtimeApplyStartupCameraProfile(matchingProfile)
    }

    private func runtimeShowOnboarding() async {
        await trackingCoordinator.runtimeShowOnboarding()
    }

    private func runtimeSwitchCameraToMatchingProfile(_ matchingProfile: ProfileData?) async {
        await trackingCoordinator.runtimeSwitchCameraToMatchingProfile(matchingProfile)
    }

    private func runtimeSwitchCameraToFallback(
        cameraID: String?,
        profile: ProfileData?
    ) async {
        await trackingCoordinator.runtimeSwitchCameraToFallback(cameraID: cameraID, profile: profile)
    }

    private func runtimeSwitchCameraToSelected() async {
        await trackingCoordinator.runtimeSwitchCameraToSelected()
    }

    private func runtimeSyncUI() async {
        await trackingCoordinator.runtimeSyncUI()
    }

    private func runtimeUpdateBlur() async {
        await trackingCoordinator.runtimeUpdateBlur()
    }

    private func runtimeTrackAnalytics(interval: TimeInterval, isSlouching: Bool) async {
        await trackingCoordinator.runtimeTrackAnalytics(interval: interval, isSlouching: isSlouching)
    }

    private func runtimeRecordSlouchEvent() async {
        await trackingCoordinator.runtimeRecordSlouchEvent()
    }

    private func runtimeStopDetector(_ source: TrackingSource) async {
        await trackingCoordinator.runtimeStopDetector(source)
    }

    private func runtimePersistTrackingSource() async {
        await trackingCoordinator.runtimePersistTrackingSource()
    }

    private func runtimeShowCalibrationPermissionDeniedAlert() async {
        await trackingCoordinator.runtimeShowCalibrationPermissionDeniedAlert()
    }

    private func runtimeOpenPrivacySettings() async {
        await trackingCoordinator.runtimeOpenPrivacySettings()
    }

    private func runtimeShowCameraCalibrationRetryAlert(message: String?) async {
        await trackingCoordinator.runtimeShowCameraCalibrationRetryAlert(message: message)
    }

    private func runtimeRetryCalibration() async {
        await trackingCoordinator.runtimeRetryCalibration()
    }

    private func runtimeStartCalibrationForSource(_ source: TrackingSource) async {
        await trackingCoordinator.runtimeStartCalibrationForSource(source)
    }

    private func showCalibrationPermissionDeniedAlert() async {
        await trackingCoordinator.showCalibrationPermissionDeniedAlert()
    }

    private func openPrivacySettings() {
        trackingCoordinator.openPrivacySettings()
    }

    private func showCameraCalibrationRetryAlert(message: String?) async {
        await trackingCoordinator.showCameraCalibrationRetryAlert(message: message)
    }

    fileprivate struct CameraDisconnectContext {
        let disconnectedCameraIsSelected: Bool
        let hasFallbackCamera: Bool
        let fallbackHasMatchingProfile: Bool
        let fallbackCamera: AVCaptureDevice?
        let fallbackProfile: ProfileData?
    }

    fileprivate struct CameraConnectedContext {
        let hasMatchingProfile: Bool
        let profile: ProfileData?
    }

    private func makeCameraDisconnectContext(for device: AVCaptureDevice) -> CameraDisconnectContext {
        trackingCoordinator.makeCameraDisconnectContext(for: device)
    }

    private func makeCameraConnectedContext(for device: AVCaptureDevice) -> CameraConnectedContext {
        trackingCoordinator.makeCameraConnectedContext(for: device)
    }

    fileprivate struct DisplayConfigurationContext {
        let pauseOnTheGoEnabled: Bool
        let isLaptopOnlyConfiguration: Bool
        let hasAnyCamera: Bool
        let hasMatchingProfileCamera: Bool
        let selectedCameraMatchesProfile: Bool
        let profile: ProfileData?
    }

    private func makeDisplayConfigurationContext() -> DisplayConfigurationContext {
        trackingCoordinator.makeDisplayConfigurationContext()
    }

    private func applyCameraConnectedTransition(
        hasMatchingProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await trackingCoordinator.applyCameraConnectedTransition(
            hasMatchingProfile: hasMatchingProfile,
            matchingProfile: matchingProfile
        )
    }

    private func applyCameraSelectionTransition() async {
        await trackingCoordinator.applyCameraSelectionTransition()
    }

    private func applyDisplayConfigurationTransition(
        pauseOnTheGoEnabled: Bool,
        isLaptopOnlyConfiguration: Bool,
        hasAnyCamera: Bool,
        hasMatchingProfileCamera: Bool,
        selectedCameraMatchesProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await trackingCoordinator.applyDisplayConfigurationTransition(
            pauseOnTheGoEnabled: pauseOnTheGoEnabled,
            isLaptopOnlyConfiguration: isLaptopOnlyConfiguration,
            hasAnyCamera: hasAnyCamera,
            hasMatchingProfileCamera: hasMatchingProfileCamera,
            selectedCameraMatchesProfile: selectedCameraMatchesProfile,
            matchingProfile: matchingProfile
        )
    }

    private func applyCameraDisconnectedTransition(
        disconnectedCameraIsSelected: Bool,
        hasFallbackCamera: Bool,
        fallbackHasMatchingProfile: Bool,
        fallbackCamera: AVCaptureDevice?,
        fallbackProfile: ProfileData?
    ) async {
        await trackingCoordinator.applyCameraDisconnectedTransition(
            disconnectedCameraIsSelected: disconnectedCameraIsSelected,
            hasFallbackCamera: hasFallbackCamera,
            fallbackHasMatchingProfile: fallbackHasMatchingProfile,
            fallbackCamera: fallbackCamera,
            fallbackProfile: fallbackProfile
        )
    }

    private func handleCameraConnected(_ device: AVCaptureDevice) async {
        await trackingCoordinator.handleCameraConnected(device)
    }

    private func handleCameraDisconnected(_ device: AVCaptureDevice) async {
        await trackingCoordinator.handleCameraDisconnected(device)
    }

    // MARK: - Screen Lock Detection

    private func handleScreenLocked() async {
        await trackingCoordinator.handleScreenLocked()
    }

    private func handleScreenUnlocked() async {
        await trackingCoordinator.handleScreenUnlocked()
    }

    // MARK: - Display Configuration

    private func handleDisplayConfigurationChange() async {
        await trackingCoordinator.handleDisplayConfigurationChange()
    }

}

@MainActor
extension AppDelegate.TrackingCoordinator {
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
            appDelegate.onActiveSourceChanged?()
        }
    }

    func handleStateTransition(from oldState: AppState, to newState: AppState) {
        os_log(.info, log: log, "State transition: %{public}@ -> %{public}@", String(describing: oldState), String(describing: newState))
        syncDetectorToState()
        if !newState.isActive {
            appDelegate.clearBlur()
            appDelegate.warningOverlayManager.targetIntensity = 0
            appDelegate.warningOverlayManager.updateWarning()
        }
        if newState == .monitoring {
            applyActiveSettingsProfile()
        }
        syncUIToState()
    }

    @discardableResult
    func sendTrackingAction(
        _ action: TrackingFeature.Action,
        applyStateTransition: Bool = true
    ) async -> (oldState: TrackingFeature.State, newState: TrackingFeature.State) {
        appDelegate.trackingActionDispatchDepth += 1
        defer { appDelegate.trackingActionDispatchDepth -= 1 }

        let oldState = appDelegate.trackingStore.withState { $0 }
        let storeTask = appDelegate.trackingStore.send(action)
        await storeTask.finish()
        let newState = appDelegate.trackingStore.withState { $0 }

        applyTrackingStoreTransition(
            from: oldState,
            to: newState,
            applyStateTransition: applyStateTransition
        )

        return (oldState, newState)
    }

    func syncDetectorToState() {
        if let syncDetectorToStateOverride = appDelegate.syncDetectorToStateOverride {
            syncDetectorToStateOverride()
            return
        }

        let activeSource = appDelegate.activeTrackingSource
        let shouldRun = PostureEngine.shouldDetectorRun(for: appDelegate.state, trackingSource: activeSource)

        // Always stop the other detector so in-flight starts are cancelled
        // even if that detector has not flipped isActive=true yet.
        // But don't stop a detector that's currently being calibrated.
        let calSource = appDelegate.calibratingSource
        let isAutomatic = appDelegate.trackingMode == .automatic
        if activeSource == .camera {
            if calSource != .airpods {
                appDelegate.airPodsDetector.stop()
                // In automatic mode, keep AirPods connection monitoring alive
                // so we can detect when they're put back in for auto-return.
                if isAutomatic {
                    appDelegate.airPodsDetector.startConnectionMonitoring()
                }
            }
        } else {
            if calSource != .camera { appDelegate.cameraDetector.stop() }
            // Stop connection-only monitoring since AirPods detector is now active
            appDelegate.airPodsDetector.stopConnectionMonitoring()
        }

        // Start/stop the active detector
        if shouldRun {
            if !appDelegate.activeDetector.isActive {
                appDelegate.activeDetector.start { [weak self] success, error in
                    if !success, let error = error {
                        os_log(.error, log: log, "Failed to start detector: %{public}@", error)
                        Task { @MainActor in
                            guard let self else { return }
                            await self.sendTrackingAction(
                                .runtimeDetectorStartFailed(
                                    trackingSource: self.appDelegate.trackingSource
                                )
                            )
                        }
                    }
                }
            }
        } else {
            // Always call stop() so in-flight starts are cancelled even if
            // the detector has not yet flipped isActive=true.
            appDelegate.activeDetector.stop()
        }
    }

    func syncUIToState() {
        let uiState = PostureUIState.derive(
            from: appDelegate.state,
            isCalibrated: appDelegate.isCalibrated,
            isCurrentlyAway: appDelegate.isCurrentlyAway,
            isCurrentlySlouching: appDelegate.isCurrentlySlouching,
            trackingSource: appDelegate.activeTrackingSource,
            isOnFallback: appDelegate.trackingStore.withState { $0.isOnFallback }
        )

        appDelegate.menuBarManager.updateStatus(text: uiState.statusText, icon: uiState.icon.menuBarIcon)
        appDelegate.menuBarManager.updateEnabledState(uiState.isEnabled)
        appDelegate.menuBarManager.updateRecalibrateEnabled(uiState.canRecalibrate)
    }

    func updateSourceReadiness() {
        let cameraReadiness = TrackingSourceReadiness(
            permissionGranted: true,
            connected: !appDelegate.cameraDetector.getAvailableCameras().isEmpty,
            calibrated: appDelegate.cameraCalibration?.isValid ?? false,
            available: true
        )
        let airPodsReadiness = TrackingSourceReadiness(
            permissionGranted: true,
            connected: appDelegate.airPodsDetector.isConnected,
            calibrated: appDelegate.airPodsCalibration?.isValid ?? false,
            available: appDelegate.airPodsDetector.isAvailable
        )
        appDelegate.trackingStore.send(.sourceReadinessChanged(source: .camera, readiness: cameraReadiness))
        appDelegate.trackingStore.send(.sourceReadinessChanged(source: .airpods, readiness: airPodsReadiness))
    }

    func setupDetectors() {
        // Configure camera detector
        appDelegate.cameraDetector.blurWhenAway = appDelegate.blurWhenAway
        appDelegate.cameraDetector.baseFrameInterval = 1.0 / appDelegate.activeDetectionMode.frameRate

        appDelegate.cameraDetector.onPostureReading = { [weak self] reading in
            Task { @MainActor in
                await self?.handlePostureReading(reading)
            }
        }

        appDelegate.cameraDetector.onAwayStateChange = { [weak self] isAway in
            Task { @MainActor in
                await self?.handleAwayStateChange(isAway)
            }
        }

        // Configure AirPods detector
        appDelegate.airPodsDetector.onPostureReading = { [weak self] reading in
            Task { @MainActor in
                await self?.handlePostureReading(reading)
            }
        }

        appDelegate.airPodsDetector.onConnectionStateChange = { [weak self] isConnected in
            Task { @MainActor in
                await self?.handleConnectionStateChange(isConnected)
            }
        }
    }

    func handleConnectionStateChange(_ isConnected: Bool) async {
        let transition = await appDelegate.sendTrackingAction(.airPodsConnectionChanged(isConnected))

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

    func handlePostureReading(_ reading: PostureReading) async {
        await appDelegate.sendTrackingAction(
            .postureReadingReceived(reading, isMarketingMode: appDelegate.isMarketingMode),
            applyStateTransition: false
        )
    }

    func handleAwayStateChange(_ isAway: Bool) async {
        await appDelegate.sendTrackingAction(
            .awayStateChanged(isAway, isMarketingMode: appDelegate.isMarketingMode),
            applyStateTransition: false
        )
    }

    func toggleEnabled() async {
        await appDelegate.sendTrackingAction(
            .toggleEnabled(
                trackingSource: appDelegate.trackingSource,
                isCalibrated: appDelegate.isCalibrated,
                detectorAvailable: appDelegate.activeDetector.isAvailable
            )
        )
        appDelegate.saveSettings()
    }

    func initialSetupFlow() async {
        guard !appDelegate.setupComplete else { return }
        appDelegate.setupComplete = true

        updateSourceReadiness()
        let context = appDelegate.makeInitialSetupContext()
        _ = await appDelegate.sendTrackingAction(
            .initialSetupEvaluated(
                isMarketingMode: appDelegate.isMarketingMode,
                hasCameraProfile: context.profile != nil,
                profileCameraAvailable: context.profileCameraAvailable,
                hasValidAirPodsCalibration: context.hasValidAirPodsCalibration,
                cameraProfile: context.profile
            )
        )
    }

    func showOnboarding() {
        appDelegate.onboardingWindowController = OnboardingWindowController()
        appDelegate.onboardingWindowController?.show(
            cameraDetector: appDelegate.cameraDetector,
            airPodsDetector: appDelegate.airPodsDetector
        ) { [weak self] source, cameraID in
            Task { @MainActor in
                guard let self else { return }

                await self.switchTrackingSource(to: source)
                if let cameraID = cameraID {
                    self.appDelegate.cameraDetector.selectedCameraID = cameraID
                }
                self.appDelegate.saveSettings()

                // Start calibration
                self.startCalibration()
            }
        }
    }

    func switchTrackingSource(to source: TrackingSource) async {
        let isNewSourceCalibrated: Bool
        switch source {
        case .camera:
            isNewSourceCalibrated = appDelegate.isMarketingMode || (appDelegate.cameraCalibration?.isValid ?? false)
        case .airpods:
            isNewSourceCalibrated = appDelegate.isMarketingMode || (appDelegate.airPodsCalibration?.isValid ?? false)
        }

        await appDelegate.sendTrackingAction(
            .switchTrackingSource(
                source,
                isNewSourceCalibrated: isNewSourceCalibrated
            )
        )
    }

    func setPauseOnTheGoEnabled(_ isEnabled: Bool) async {
        appDelegate.pauseOnTheGo = isEnabled
        appDelegate.saveSettings()
        await appDelegate.sendTrackingAction(.pauseOnTheGoSettingChanged(isEnabled: isEnabled))
    }

    func startCalibration() {
        // Prevent multiple concurrent calibrations (use calibrationController as the lock)
        guard appDelegate.calibrationController == nil else { return }

        appDelegate.calibratingSource = appDelegate.activeTrackingSource
        os_log(.info, log: log, "Starting calibration for %{public}@", appDelegate.activeTrackingSource.displayName)

        // Request authorization (this shows permission dialog if needed)
        appDelegate.activeDetector.requestAuthorization { [weak self] authorized in
            Task { @MainActor in
                guard let self else { return }

                if !authorized {
                    os_log(.error, log: log, "Authorization denied for %{public}@", self.appDelegate.activeTrackingSource.displayName)
                    self.appDelegate.calibratingSource = nil

                    await self.appDelegate.sendTrackingAction(
                        .calibrationAuthorizationDenied(isCalibrated: self.appDelegate.isCalibrated)
                    )
                    return
                }

                // Authorization granted - now start calibration
                await self.appDelegate.sendTrackingAction(.calibrationAuthorizationGranted)
                self.startDetectorAndShowCalibration()
            }
        }
    }

    func startDetectorAndShowCalibration() {
        // Double-check no calibration controller already exists
        guard appDelegate.calibrationController == nil else {
            os_log(.info, log: log, "Skipping calibration window - already exists")
            return
        }

        appDelegate.activeDetector.start { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }

                if !success {
                    os_log(.error, log: log, "Failed to start detector for calibration: %{public}@", error ?? "unknown")
                    await self.appDelegate.sendTrackingAction(.calibrationStartFailed(errorMessage: error))
                    return
                }

                self.appDelegate.calibrationController = CalibrationWindowController()
                self.appDelegate.calibrationController?.start(
                    detector: self.appDelegate.activeDetector,
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
        guard let calibration = appDelegate.activeDetector.createCalibrationData(from: values) else {
            await cancelCalibration()
            return
        }

        // Store calibration
        if let cameraCalibration = calibration as? CameraCalibrationData {
            appDelegate.cameraCalibration = cameraCalibration
            // Also save as legacy profile
            let profile = ProfileData(
                goodPostureY: cameraCalibration.goodPostureY,
                badPostureY: cameraCalibration.badPostureY,
                neutralY: cameraCalibration.neutralY,
                postureRange: cameraCalibration.postureRange,
                cameraID: cameraCalibration.cameraID
            )
            let configKey = DisplayMonitor.getCurrentConfigKey()
            appDelegate.saveProfile(forKey: configKey, data: profile)
        } else if let airPodsCalibration = calibration as? AirPodsCalibrationData {
            appDelegate.airPodsCalibration = airPodsCalibration
        }

        let calibratedSource = appDelegate.calibratingSource ?? appDelegate.activeTrackingSource
        appDelegate.calibratingSource = nil
        appDelegate.saveSettings()
        appDelegate.calibrationController = nil

        await appDelegate.sendTrackingAction(.calibrationCompleted(source: calibratedSource))
        appDelegate.onCalibrationComplete?()
    }

    func cancelCalibration() async {
        appDelegate.calibratingSource = nil
        appDelegate.calibrationController = nil
        await appDelegate.sendTrackingAction(.calibrationCancelled(isCalibrated: appDelegate.isCalibrated))
    }

    func startMonitoring() async {
        let transition = await appDelegate.sendTrackingAction(
            .startMonitoringRequested(
                isMarketingMode: appDelegate.isMarketingMode,
                trackingSource: appDelegate.trackingSource,
                isCalibrated: appDelegate.isCalibrated,
                isConnected: appDelegate.activeDetector.isConnected
            )
        )

        if transition.newState.appState == .paused(.airPodsRemoved) {
            os_log(.info, log: log, "AirPods not in ears - pausing instead of monitoring")
        }
    }

    func applyActiveSettingsProfile() {
        appDelegate.trackingStore.send(
            .setPostureConfiguration(
                intensity: Double(appDelegate.activeIntensity),
                warningOnsetDelay: appDelegate.activeWarningOnsetDelay
            )
        )
        appDelegate.activeDetector.updateParameters(intensity: appDelegate.activeIntensity, deadZone: appDelegate.activeDeadZone)
        appDelegate.applyDetectionMode()

        guard appDelegate.setupComplete else { return }

        if appDelegate.warningOverlayManager.mode != appDelegate.activeWarningMode {
            appDelegate.switchWarningMode(to: appDelegate.activeWarningMode)
        }

        let desiredColorData = appDelegate.activeSettingsProfile?.warningColorData
        if desiredColorData != appDelegate.appliedWarningColorData {
            appDelegate.appliedWarningColorData = desiredColorData
            appDelegate.updateWarningColor(appDelegate.activeWarningColor)
        }
    }

    func runtimeStartMonitoring() async {
        appDelegate.trackingEffectIntentObserver?(.startMonitoring)
        await startMonitoring()
    }

    func runtimeBeginMonitoringSession() async {
        appDelegate.trackingEffectIntentObserver?(.beginMonitoringSession)
        if let beginMonitoringSessionHandler = appDelegate.beginMonitoringSessionHandler {
            beginMonitoringSessionHandler()
            return
        }
        guard let calibration = appDelegate.currentCalibration else { return }
        appDelegate.activeDetector.beginMonitoring(with: calibration, intensity: appDelegate.activeIntensity, deadZone: appDelegate.activeDeadZone)
    }

    func runtimeApplyStartupCameraProfile(_ matchingProfile: ProfileData?) async {
        appDelegate.trackingEffectIntentObserver?(.applyStartupCameraProfile(matchingProfile))
        guard let matchingProfile else { return }
        appDelegate.cameraDetector.selectedCameraID = matchingProfile.cameraID
        appDelegate.applyCameraCalibration(from: matchingProfile)
    }

    func runtimeShowOnboarding() async {
        appDelegate.trackingEffectIntentObserver?(.showOnboarding)
        if let showOnboardingHandler = appDelegate.showOnboardingHandler {
            showOnboardingHandler()
        } else {
            showOnboarding()
        }
    }

    func runtimeSwitchCameraToMatchingProfile(_ matchingProfile: ProfileData?) async {
        appDelegate.trackingEffectIntentObserver?(.switchCamera(.matchingProfile(matchingProfile)))
        guard let matchingProfile else { return }
        appDelegate.cameraDetector.selectedCameraID = matchingProfile.cameraID
        appDelegate.applyCameraCalibration(from: matchingProfile)
        appDelegate.cameraDetector.switchCamera(to: matchingProfile.cameraID)
    }

    func runtimeSwitchCameraToFallback(
        cameraID: String?,
        profile: ProfileData?
    ) async {
        appDelegate.trackingEffectIntentObserver?(.switchCamera(.fallback(cameraID: cameraID, profile: profile)))
        guard let cameraID else { return }
        appDelegate.cameraDetector.selectedCameraID = cameraID
        if let profile, profile.cameraID == cameraID {
            appDelegate.applyCameraCalibration(from: profile)
        }
        appDelegate.cameraDetector.switchCamera(to: cameraID)
    }

    func runtimeSwitchCameraToSelected() async {
        appDelegate.trackingEffectIntentObserver?(.switchCamera(.selectedCamera))
        guard let selectedCameraID = appDelegate.selectedCameraID else { return }
        appDelegate.cameraDetector.switchCamera(to: selectedCameraID)
    }

    func runtimeSyncUI() async {
        appDelegate.trackingEffectIntentObserver?(.syncUI)
        appDelegate.syncUIToState()
    }

    func runtimeUpdateBlur() async {
        appDelegate.trackingEffectIntentObserver?(.updateBlur)
        appDelegate.updateBlur()
    }

    func runtimeTrackAnalytics(interval: TimeInterval, isSlouching: Bool) async {
        appDelegate.trackingEffectIntentObserver?(
            .trackAnalytics(interval: interval, isSlouching: isSlouching)
        )
        AnalyticsManager.shared.trackTime(interval: interval, isSlouching: isSlouching)
    }

    func runtimeRecordSlouchEvent() async {
        appDelegate.trackingEffectIntentObserver?(.recordSlouchEvent)
        AnalyticsManager.shared.recordSlouchEvent()
    }

    func runtimeStopDetector(_ source: TrackingSource) async {
        appDelegate.trackingEffectIntentObserver?(.stopDetector(source))
        let detector: PostureDetector = source == .camera ? appDelegate.cameraDetector : appDelegate.airPodsDetector
        detector.stop()
    }

    func runtimePersistTrackingSource() async {
        appDelegate.trackingEffectIntentObserver?(.persistTrackingSource)
        appDelegate.saveSettings()
    }

    func runtimeShowCalibrationPermissionDeniedAlert() async {
        appDelegate.trackingEffectIntentObserver?(.showCalibrationPermissionDeniedAlert)
        await showCalibrationPermissionDeniedAlert()
    }

    func runtimeOpenPrivacySettings() async {
        appDelegate.trackingEffectIntentObserver?(.openPrivacySettings)
        openPrivacySettings()
    }

    func runtimeShowCameraCalibrationRetryAlert(message: String?) async {
        appDelegate.trackingEffectIntentObserver?(.showCameraCalibrationRetryAlert(message: message))
        await showCameraCalibrationRetryAlert(message: message)
    }

    func runtimeRetryCalibration() async {
        appDelegate.trackingEffectIntentObserver?(.retryCalibration)
        if let retryCalibrationHandler = appDelegate.retryCalibrationHandler {
            retryCalibrationHandler()
        } else {
            startCalibration()
        }
    }

    func runtimeStartCalibrationForSource(_ source: TrackingSource) async {
        appDelegate.trackingEffectIntentObserver?(.startCalibrationForSource(source))
        startCalibration(for: source)
    }

    func startCalibration(for source: TrackingSource) {
        guard appDelegate.calibrationController == nil else { return }

        appDelegate.calibratingSource = source
        os_log(.info, log: log, "Starting calibration for %{public}@", source.displayName)

        let detector: PostureDetector = source == .camera ? appDelegate.cameraDetector : appDelegate.airPodsDetector
        detector.requestAuthorization { [weak self] authorized in
            Task { @MainActor in
                guard let self else { return }
                if !authorized {
                    await self.appDelegate.sendTrackingAction(
                        .calibrationAuthorizationDenied(isCalibrated: self.appDelegate.isCalibrated)
                    )
                    self.appDelegate.calibratingSource = nil
                    return
                }
                await self.appDelegate.sendTrackingAction(.calibrationAuthorizationGranted)
                self.startDetectorAndShowCalibration(for: source)
            }
        }
    }

    private func startDetectorAndShowCalibration(for source: TrackingSource) {
        guard appDelegate.calibrationController == nil else { return }

        let detector: PostureDetector = source == .camera ? appDelegate.cameraDetector : appDelegate.airPodsDetector
        detector.start { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if !success {
                    self.appDelegate.calibratingSource = nil
                    await self.appDelegate.sendTrackingAction(.calibrationStartFailed(errorMessage: error))
                    return
                }
                self.appDelegate.calibrationController = CalibrationWindowController()
                self.appDelegate.calibrationController?.start(
                    detector: detector,
                    onComplete: { [weak self] values in
                        Task { @MainActor in
                            await self?.finishCalibrationForSource(values: values)
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

    func finishCalibrationForSource(values: [CalibrationSample]) async {
        guard let source = appDelegate.calibratingSource else {
            await finishCalibration(values: values)
            return
        }

        guard values.count >= 4 else {
            await cancelCalibration()
            return
        }

        os_log(.info, log: log, "Finishing calibration for %{public}@ with %d values", source.displayName, values.count)

        let detector: PostureDetector = source == .camera ? appDelegate.cameraDetector : appDelegate.airPodsDetector
        guard let calibration = detector.createCalibrationData(from: values) else {
            await cancelCalibration()
            return
        }

        if let cameraCalibration = calibration as? CameraCalibrationData {
            appDelegate.cameraCalibration = cameraCalibration
            let profile = ProfileData(
                goodPostureY: cameraCalibration.goodPostureY,
                badPostureY: cameraCalibration.badPostureY,
                neutralY: cameraCalibration.neutralY,
                postureRange: cameraCalibration.postureRange,
                cameraID: cameraCalibration.cameraID
            )
            let configKey = DisplayMonitor.getCurrentConfigKey()
            appDelegate.saveProfile(forKey: configKey, data: profile)
        } else if let airPodsCalibration = calibration as? AirPodsCalibrationData {
            appDelegate.airPodsCalibration = airPodsCalibration
        }

        let calibratedSource = source
        appDelegate.calibratingSource = nil
        appDelegate.saveSettings()
        appDelegate.calibrationController = nil

        await appDelegate.sendTrackingAction(.calibrationCompleted(source: calibratedSource))
        appDelegate.onCalibrationComplete?()
    }

    func showCalibrationPermissionDeniedAlert() async {
        if let calibrationPermissionDeniedAlertDecision = appDelegate.calibrationPermissionDeniedAlertDecision {
            if calibrationPermissionDeniedAlertDecision(appDelegate.trackingSource) {
                await appDelegate.sendTrackingAction(.calibrationOpenSettingsRequested)
            }
            return
        }

        let source = appDelegate.calibratingSource ?? appDelegate.activeTrackingSource
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("alert.permissionRequired")
        alert.informativeText = source == .airpods
            ? L("alert.permissionRequired.airpods")
            : L("alert.permissionRequired.camera")
        alert.addButton(withTitle: L("alert.openSettings"))
        alert.addButton(withTitle: L("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            await appDelegate.sendTrackingAction(.calibrationOpenSettingsRequested)
        }
    }

    func openPrivacySettings() {
        if let openPrivacySettingsHandler = appDelegate.openPrivacySettingsHandler {
            openPrivacySettingsHandler()
            return
        }

        let source = appDelegate.calibratingSource ?? appDelegate.activeTrackingSource
        let pane = source == .airpods ? "Privacy_Motion" : "Privacy_Camera"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    func showCameraCalibrationRetryAlert(message: String?) async {
        if let cameraCalibrationRetryAlertDecision = appDelegate.cameraCalibrationRetryAlertDecision {
            if cameraCalibrationRetryAlertDecision(message) {
                await appDelegate.sendTrackingAction(.calibrationRetryRequested)
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
            await appDelegate.sendTrackingAction(.calibrationRetryRequested)
        }
    }

    fileprivate func makeCameraDisconnectContext(
        for device: AVCaptureDevice
    ) -> AppDelegate.CameraDisconnectContext {
        let disconnectedCameraIsSelected = device.uniqueID == appDelegate.selectedCameraID
        let cameras = appDelegate.cameraDetector.getAvailableCameras()
        let fallbackCamera = cameras.first
        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = appDelegate.loadProfile(forKey: configKey)
        let fallbackHasMatchingProfile = fallbackCamera != nil && profile?.cameraID == fallbackCamera?.uniqueID

        return AppDelegate.CameraDisconnectContext(
            disconnectedCameraIsSelected: disconnectedCameraIsSelected,
            hasFallbackCamera: fallbackCamera != nil,
            fallbackHasMatchingProfile: fallbackHasMatchingProfile,
            fallbackCamera: fallbackCamera,
            fallbackProfile: profile
        )
    }

    fileprivate func makeCameraConnectedContext(
        for device: AVCaptureDevice
    ) -> AppDelegate.CameraConnectedContext {
        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = appDelegate.loadProfile(forKey: configKey)

        return AppDelegate.CameraConnectedContext(
            hasMatchingProfile: profile?.cameraID == device.uniqueID,
            profile: profile
        )
    }

    fileprivate func makeDisplayConfigurationContext() -> AppDelegate.DisplayConfigurationContext {
        let cameras = appDelegate.cameraDetector.getAvailableCameras()
        let hasAnyCamera = !cameras.isEmpty
        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = appDelegate.loadProfile(forKey: configKey)
        let hasMatchingProfileCamera = profile.map { profile in
            cameras.contains(where: { $0.uniqueID == profile.cameraID })
        } ?? false
        let selectedCameraMatchesProfile = profile.map { profile in
            appDelegate.selectedCameraID == profile.cameraID
        } ?? false

        return AppDelegate.DisplayConfigurationContext(
            pauseOnTheGoEnabled: appDelegate.pauseOnTheGo,
            isLaptopOnlyConfiguration: DisplayMonitor.isLaptopOnlyConfiguration(),
            hasAnyCamera: hasAnyCamera,
            hasMatchingProfileCamera: hasMatchingProfileCamera,
            selectedCameraMatchesProfile: selectedCameraMatchesProfile,
            profile: profile
        )
    }

    func applyCameraConnectedTransition(
        hasMatchingProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await appDelegate.sendTrackingAction(
            .cameraConnected(
                hasMatchingProfile: hasMatchingProfile,
                matchingProfile: matchingProfile
            )
        )
    }

    func applyCameraSelectionTransition() async {
        await appDelegate.sendTrackingAction(.cameraSelectionChanged)
    }

    func applyDisplayConfigurationTransition(
        pauseOnTheGoEnabled: Bool,
        isLaptopOnlyConfiguration: Bool,
        hasAnyCamera: Bool,
        hasMatchingProfileCamera: Bool,
        selectedCameraMatchesProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await appDelegate.sendTrackingAction(
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

    func applyCameraDisconnectedTransition(
        disconnectedCameraIsSelected: Bool,
        hasFallbackCamera: Bool,
        fallbackHasMatchingProfile: Bool,
        fallbackCamera: AVCaptureDevice?,
        fallbackProfile: ProfileData?
    ) async {
        await appDelegate.sendTrackingAction(
            .cameraDisconnected(
                disconnectedCameraIsSelected: disconnectedCameraIsSelected,
                hasFallbackCamera: hasFallbackCamera,
                fallbackHasMatchingProfile: fallbackHasMatchingProfile,
                fallbackCameraID: fallbackCamera?.uniqueID,
                fallbackProfile: fallbackProfile
            )
        )
    }

    func handleCameraConnected(_ device: AVCaptureDevice) async {
        guard appDelegate.activeTrackingSource == .camera
              || appDelegate.trackingStore.withState({ $0.trackingMode }) == .automatic
        else { return }
        let context = makeCameraConnectedContext(for: device)

        await applyCameraConnectedTransition(
            hasMatchingProfile: context.hasMatchingProfile,
            matchingProfile: context.profile
        )
    }

    func handleCameraDisconnected(_ device: AVCaptureDevice) async {
        guard appDelegate.activeTrackingSource == .camera
              || appDelegate.trackingStore.withState({ $0.trackingMode }) == .automatic
        else { return }
        let context = makeCameraDisconnectContext(for: device)

        await applyCameraDisconnectedTransition(
            disconnectedCameraIsSelected: context.disconnectedCameraIsSelected,
            hasFallbackCamera: context.hasFallbackCamera,
            fallbackHasMatchingProfile: context.fallbackHasMatchingProfile,
            fallbackCamera: context.fallbackCamera,
            fallbackProfile: context.fallbackProfile
        )
    }

    func handleScreenLocked() async {
        await appDelegate.sendTrackingAction(.screenLocked)
    }

    func handleScreenUnlocked() async {
        await appDelegate.sendTrackingAction(.screenUnlocked)
    }

    func handleDisplayConfigurationChange() async {
        appDelegate.rebuildOverlayWindows()

        guard appDelegate.state != .disabled else { return }
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
