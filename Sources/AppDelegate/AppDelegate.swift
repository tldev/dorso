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
    var appliedWarningColorData: Data?

    // MARK: - Posture Detectors

    let cameraDetector = CameraPostureDetector()
    let airPodsDetector = AirPodsPostureDetector()

    func detector(for source: TrackingSource) -> PostureDetector {
        source == .camera ? cameraDetector : airPodsDetector
    }

    var activeDetector: PostureDetector {
        detector(for: activeTrackingSource)
    }

    var activeTrackingSource: TrackingSource {
        trackingStore.withState { $0.activeSource }
    }

    var trackingSource: TrackingSource {
        get { trackingStore.withState { $0.manualSource } }
        set {
            guard trackingStore.withState({ $0.manualSource }) != newValue else { return }
            applyTrackingAction(.setManualSource(newValue))
        }
    }

    var trackingMode: TrackingMode {
        get { trackingStore.withState { $0.trackingMode } }
        set { applyTrackingAction(.setTrackingMode(newValue)) }
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
                    await self.handleAwayStateChange(false)
                }
            }
        }
    }
    var showInDock = false
    var pauseOnTheGo = false
    var useFullScreenOverlay = false
    var settingsWindowController = SettingsWindowController()
    var supportWindowController = SupportWindowController()
    var analyticsWindowController: AnalyticsWindowController?
    var onboardingWindowController: OnboardingWindowController?

    // Observers and monitors
    let displayMonitor = DisplayMonitor()
    let cameraObserver = CameraObserver()
    let screenLockObserver = ScreenLockObserver()
    let hotkeyManager = HotkeyManager()

    lazy var trackingStore: StoreOf<TrackingFeature> = {
        Store(initialState: TrackingFeature.State()) {
            TrackingFeature()
        } withDependencies: { [weak self] dependencies in
            dependencies.trackingRuntime.perform = { [weak self] intent in
                await self?.performTrackingEffect(intent)
            }
        }
    }()

    // MARK: - Test Seams
    // Closures installed by integration tests to observe reducer effects and
    // stub side effects that would touch real devices, alerts, or windows.

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

    // Convenience accessors into the tracking store's monitoring state
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
            guard trackingStore.withState({ $0.appState }) != newValue else { return }
            applyTrackingAction(.setAppState(newValue))
        }
    }

    // MARK: - Tracking Store Dispatch

    /// Synchronously sends an action to the tracking store and applies the
    /// resulting transition (detector/UI sync). Effects requested by the
    /// reducer run asynchronously after this returns.
    @discardableResult
    func applyTrackingAction(
        _ action: TrackingFeature.Action,
        applyStateTransition: Bool = true
    ) -> (oldState: TrackingFeature.State, newState: TrackingFeature.State) {
        let oldState = trackingStore.withState { $0 }
        trackingStore.send(action)
        let newState = trackingStore.withState { $0 }
        applyTrackingStoreTransition(
            from: oldState,
            to: newState,
            applyStateTransition: applyStateTransition
        )
        return (oldState, newState)
    }

    /// Sends an action to the tracking store, waits for its effects to
    /// finish, then applies the resulting transition.
    @discardableResult
    func sendTrackingAction(
        _ action: TrackingFeature.Action,
        applyStateTransition: Bool = true
    ) async -> (oldState: TrackingFeature.State, newState: TrackingFeature.State) {
        let oldState = trackingStore.withState { $0 }
        let storeTask = trackingStore.send(action)
        await storeTask.finish()
        let newState = trackingStore.withState { $0 }
        applyTrackingStoreTransition(
            from: oldState,
            to: newState,
            applyStateTransition: applyStateTransition
        )
        return (oldState, newState)
    }

    // MARK: - Reducer Effect Execution

    /// The single funnel through which every reducer-requested side effect
    /// runs. Fires the test observer, then executes the effect.
    func performTrackingEffect(_ intent: TrackingFeature.EffectIntent) async {
        trackingEffectIntentObserver?(intent)

        switch intent {
        case .startMonitoring:
            await startMonitoring()

        case .beginMonitoringSession:
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

        case .switchCamera(.matchingProfile(let profile)):
            guard let profile else { return }
            cameraDetector.selectedCameraID = profile.cameraID
            applyCameraCalibration(from: profile)
            cameraDetector.switchCamera(to: profile.cameraID)

        case .switchCamera(.fallback(let cameraID, let profile)):
            guard let cameraID else { return }
            cameraDetector.selectedCameraID = cameraID
            if let profile, profile.cameraID == cameraID {
                applyCameraCalibration(from: profile)
            }
            cameraDetector.switchCamera(to: cameraID)

        case .switchCamera(.selectedCamera):
            guard let selectedCameraID else { return }
            cameraDetector.switchCamera(to: selectedCameraID)

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

            syncWarningOverlaySettings()
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

    private func showAnalytics() {
        if analyticsWindowController == nil {
            analyticsWindowController = AnalyticsWindowController()
        }
        analyticsWindowController?.appDelegate = self
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

    // MARK: - Activation Policy

    func restoreAccessoryActivationPolicyIfNeeded(excluding windowToIgnore: NSWindow? = nil) {
        guard !showInDock else { return }

        // Only titled windows (Settings, Support, Analytics, Onboarding) justify
        // staying .regular. The borderless overlay windows are visible for the
        // app's entire lifetime, so counting them here would keep the app in
        // the Dock and Cmd+Tab switcher forever after the first window opened.
        let hasOtherVisibleTitledWindows = NSApp.windows.contains { window in
            guard window != windowToIgnore else { return false }
            return window.isVisible && !window.isMiniaturized && window.styleMask.contains(.titled)
        }

        if !hasOtherVisibleTitledWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Runs `block` while the app is temporarily `.accessory`, then restores
    /// the previous policy. Overlay and calibration windows only get Space
    /// semantics that render over a fullscreen app if they're created while
    /// Dorso is `.accessory` — a `.regular` context (onboarding/Settings open)
    /// poisons their Space association. After the policy flip back we also
    /// re-front whatever window was key beforehand, so a visible
    /// Settings/Onboarding window doesn't get pushed behind other apps
    /// when the block runs while it was in the foreground.
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
}
