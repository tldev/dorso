import AppKit
import AVFoundation
import CoreMotion
import Vision
import os.log

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
    private var appliedWarningColorData: Data?

    // MARK: - Posture Detectors

    let cameraDetector = CameraPostureDetector()
    let airPodsDetector = AirPodsPostureDetector()

    var trackingSource: TrackingSource = .camera {
        didSet {
            if oldValue != trackingSource {
                activeSourceSince = Date()
                preferredReadySince = nil
                syncDetectorToState()
            }
        }
    }

    var trackingPolicyMode: TrackingPolicyMode = .manual
    var preferredTrackingSource: TrackingSource = .camera
    var manualTrackingSource: TrackingSource = .camera
    var autoReturnEnabled = true

    var trackingPolicy: TrackingPolicy {
        get {
            switch trackingPolicyMode {
            case .manual:
                return .manual(source: manualTrackingSource)
            case .automatic:
                return .automatic(preferred: preferredTrackingSource, autoReturn: autoReturnEnabled)
            }
        }
        set {
            switch newValue {
            case .manual(let source):
                trackingPolicyMode = .manual
                manualTrackingSource = source
                trackingSource = source
            case .automatic(let preferred, let autoReturn):
                trackingPolicyMode = .automatic
                preferredTrackingSource = preferred
                autoReturnEnabled = autoReturn
            }
        }
    }

    private(set) var latestSourceReadiness: [TrackingSource: SourceReadiness] = [:]
    private(set) var latestTrackingDecision: TrackingDecision?
    private var activeSourceSince: Date = Date()
    private var preferredReadySince: Date?
    private var policyEvaluationTimer: Timer?
    private var permissionRequestInFlight: Set<TrackingSource> = []
    private var calibrationStartInFlight = false

    private var isOnboardingActive: Bool {
        onboardingWindowController?.window?.isVisible == true
    }

    var activeDetector: PostureDetector {
        trackingSource == .camera ? cameraDetector : airPodsDetector
    }

    func detector(for source: TrackingSource) -> PostureDetector {
        source == .camera ? cameraDetector : airPodsDetector
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

    func isCalibrated(for source: TrackingSource) -> Bool {
        if isMarketingMode {
            return true
        }
        switch source {
        case .camera:
            return cameraCalibration?.isValid ?? false
        case .airpods:
            return airPodsCalibration?.isValid ?? false
        }
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

    var isMarketingMode: Bool {
        UserDefaults.standard.bool(forKey: "MarketingMode")
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
        if case .monitoring = newState {
            applyActiveSettingsProfile()
        }
        syncUIToState()
    }

    private func syncDetectorToState() {
        let activeShouldRun = PostureEngine.shouldDetectorRun(for: state, trackingSource: trackingSource)

        for source in TrackingSource.allCases {
            let detector = self.detector(for: source)
            let shouldRun: Bool

            if source == trackingSource {
                shouldRun = activeShouldRun
            } else {
                shouldRun = shouldRunProbe(for: source)
            }

            if shouldRun {
                if !detector.isActive {
                    detector.start { [weak self] success, error in
                        guard let self else { return }
                        guard !success else { return }

                        if source == self.trackingSource {
                            os_log(.error, log: log, "Failed to start active detector: %{public}@", error ?? "unknown")
                            Task { @MainActor in
                                self.pauseForSourceUnavailable(
                                    source: source,
                                    blockers: [.needsConnection],
                                    isFallback: self.trackingPolicyMode == .automatic
                                )
                            }
                        } else {
                            os_log(.error, log: log, "Failed to start probe detector: %{public}@", error ?? "unknown")
                        }
                    }
                }
            } else {
                detector.stop()
            }
        }
    }

    private func shouldRunProbe(for source: TrackingSource) -> Bool {
        guard source == .airpods else { return false }
        guard trackingPolicyMode == .automatic else { return false }
        guard autoReturnEnabled else { return false }
        guard preferredTrackingSource == .airpods else { return false }
        guard trackingSource != .airpods else { return false }
        guard calibrationController == nil else { return false }

        switch state {
        case .disabled, .paused(.screenLocked, _):
            return false
        default:
            return true
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

        policyEvaluationTimer?.invalidate()
        policyEvaluationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateTrackingPolicy(force: false)
            }
        }

        if isMarketingMode {
            AnalyticsManager.shared.injectMarketingData()
        }

        initialSetupFlow()
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
                self?.handleConnectionStateChange(isConnected)
            }
        }
    }

    private func handleConnectionStateChange(_ isConnected: Bool) {
        if trackingSource == .airpods, case .monitoring(.airpods) = state, !isConnected {
            os_log(.info, log: log, "AirPods disconnected while active source; evaluating fallback.")
        }
        evaluateTrackingPolicy(force: true)
    }

    private func handlePostureReading(_ reading: PostureReading) {
        guard case .monitoring = state else { return }

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
        guard case .monitoring = state else { return }
        if isMarketingMode { return }

        let result = PostureEngine.processAwayChange(isAway: isAway, state: monitoringState)
        monitoringState = result.newState

        if result.shouldUpdateUI {
            syncUIToState()
        }
    }

    // MARK: - Tracking Orchestration

    func refreshSourceReadiness() {
        latestSourceReadiness = Dictionary(uniqueKeysWithValues: TrackingSource.allCases.map { source in
            (source, sourceReadiness(for: source))
        })
    }

    func sourceReadiness(for source: TrackingSource) -> SourceReadiness {
        let permission = permissionState(for: source)
        let connection = connectionState(for: source)
        let calibration = calibrationState(for: source)

        var blockers: [SourceBlocker] = []

        switch permission {
        case .authorized:
            break
        case .notDetermined:
            blockers.append(.needsPermission)
        case .denied:
            blockers.append(.permissionDenied)
        }

        if connection == .disconnected {
            blockers.append(.needsConnection)
        }

        if calibration == .notCalibrated {
            blockers.append(.needsCalibration)
        }

        blockers.sort { $0.priority < $1.priority }

        return SourceReadiness(
            source: source,
            permissionState: permission,
            connectionState: connection,
            calibrationState: calibration,
            blockers: blockers
        )
    }

    private func permissionState(for source: TrackingSource) -> PermissionState {
        switch source {
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                return .authorized
            case .notDetermined:
                return .notDetermined
            case .denied, .restricted:
                return .denied
            @unknown default:
                return .denied
            }
        case .airpods:
            guard #available(macOS 14.0, *) else {
                return .denied
            }

            switch CMHeadphoneMotionManager.authorizationStatus() {
            case .authorized:
                return .authorized
            case .notDetermined:
                return .notDetermined
            case .denied, .restricted:
                return .denied
            @unknown default:
                return .denied
            }
        }
    }

    private func connectionState(for source: TrackingSource) -> ConnectionState {
        switch source {
        case .camera:
            return cameraDetector.getAvailableCameras().isEmpty ? .disconnected : .connected
        case .airpods:
            // AirPods must be in-ear and actively streaming motion to be usable.
            return airPodsDetector.isConnected ? .connected : .disconnected
        }
    }

    private func calibrationState(for source: TrackingSource) -> CalibrationState {
        switch source {
        case .camera:
            guard let calibration = cameraCalibration, calibration.isValid else {
                return .notCalibrated
            }
            guard let selectedCameraID else {
                return .notCalibrated
            }
            return calibration.cameraID == selectedCameraID ? .calibrated : .notCalibrated
        case .airpods:
            return (airPodsCalibration?.isValid ?? false) ? .calibrated : .notCalibrated
        }
    }

    func evaluateTrackingPolicy(force: Bool, allowFromDisabled: Bool = false) {
        refreshSourceReadiness()

        guard !isMarketingMode else {
            if case .disabled = state {
                return
            }
            state = .monitoring(trackingSource)
            return
        }

        switch state {
        case .disabled:
            guard allowFromDisabled else {
                latestTrackingDecision = nil
                return
            }
        case .paused(.screenLocked, _), .paused(.onTheGo, _):
            latestTrackingDecision = nil
            return
        case .calibrating:
            // Stay in calibrating only while the calibration UI is active.
            // After completion/cancel we clear calibrationController, and the
            // next forced evaluation should transition to monitoring/paused.
            if calibrationController != nil || calibrationStartInFlight || !force {
                return
            }
        default:
            break
        }

        let policy = trackingPolicy
        let decision = TrackingResolver.resolve(
            policy: policy,
            currentActiveSource: trackingSource,
            readiness: latestSourceReadiness
        )

        if !isOnboardingActive,
           case .automatic(let preferred, _) = policy,
           decision.activeSource == preferred.other,
           let preferredReadiness = latestSourceReadiness[preferred] {
            _ = triggerAutomaticRemediation(for: preferred, readiness: preferredReadiness)
        }

        if case .automatic(let preferred, let autoReturn) = policy,
           autoReturn,
           decision.activeSource == preferred,
           trackingSource != preferred,
           !force {
            let now = Date()

            if preferredReadySince == nil {
                preferredReadySince = now
                return
            }

            if let readySince = preferredReadySince, now.timeIntervalSince(readySince) < 3 {
                return
            }

            if now.timeIntervalSince(activeSourceSince) < 20 {
                return
            }
        } else if decision.activeSource != preferredTrackingSource {
            preferredReadySince = nil
        }

        latestTrackingDecision = decision
        applyTrackingDecision(decision)
    }

    private func applyTrackingDecision(_ decision: TrackingDecision) {
        if let source = decision.activeSource {
            if source == .camera {
                ensureSelectedCameraIsAvailable()
            }

            if trackingSource != source {
                trackingSource = source
            }

            if case .monitoring(let currentSource) = state, currentSource == source {
                return
            }

            startMonitoring(for: source)
            return
        }

        if let pauseContext = decision.pauseContext {
            pauseForSourceUnavailable(
                source: pauseContext.targetSource,
                blockers: pauseContext.blockers,
                isFallback: pauseContext.isFallback
            )
            if !isOnboardingActive {
                let readiness = latestSourceReadiness[pauseContext.targetSource] ?? sourceReadiness(for: pauseContext.targetSource)
                _ = triggerAutomaticRemediation(for: pauseContext.targetSource, readiness: readiness)
            }
        }
    }

    @discardableResult
    private func triggerAutomaticRemediation(for source: TrackingSource, readiness: SourceReadiness) -> Bool {
        guard let blocker = readiness.blockers.first else { return false }

        switch blocker {
        case .needsPermission:
            guard !permissionRequestInFlight.contains(source) else {
                return true
            }

            permissionRequestInFlight.insert(source)
            detector(for: source).requestAuthorization { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.permissionRequestInFlight.remove(source)

                    if granted {
                        let updatedReadiness = self.sourceReadiness(for: source)
                        if updatedReadiness.blockers.first == .needsCalibration {
                            self.startCalibration(for: source)
                        } else {
                            self.evaluateTrackingPolicy(force: true)
                        }
                    } else {
                        self.evaluateTrackingPolicy(force: true)
                    }
                }
            }
            return true

        case .needsCalibration:
            startCalibration(for: source)
            return true

        case .permissionDenied, .needsConnection:
            return false
        }
    }

    private func ensureSelectedCameraIsAvailable() {
        let cameras = cameraDetector.getAvailableCameras()
        guard !cameras.isEmpty else { return }

        if let selectedCameraID,
           cameras.contains(where: { $0.uniqueID == selectedCameraID }) {
            return
        }

        if let fallback = cameras.first {
            cameraDetector.selectedCameraID = fallback.uniqueID
            cameraDetector.switchCamera(to: fallback.uniqueID)
            loadCameraCalibrationForCurrentDisplayIfAvailable(cameraID: fallback.uniqueID)
        }
    }

    private func loadCameraCalibrationForCurrentDisplayIfAvailable(cameraID: String) {
        let configKey = DisplayMonitor.getCurrentConfigKey()
        guard let profile = loadProfile(forKey: configKey), profile.cameraID == cameraID else {
            return
        }

        cameraCalibration = CameraCalibrationData(
            goodPostureY: profile.goodPostureY,
            badPostureY: profile.badPostureY,
            neutralY: profile.neutralY,
            postureRange: profile.postureRange,
            cameraID: profile.cameraID
        )
    }

    func pauseForSourceUnavailable(source: TrackingSource, blockers: [SourceBlocker], isFallback: Bool) {
        let context = PauseContext(targetSource: source, blockers: blockers.sorted { $0.priority < $1.priority }, isFallback: isFallback)
        state = .paused(.sourceUnavailable, context: context)
    }

    func performPrimaryTrackingAction(for source: TrackingSource? = nil) {
        refreshSourceReadiness()

        let targetSource: TrackingSource
        if let source {
            targetSource = source
        } else if case .paused(.sourceUnavailable, let context) = state,
                  let context {
            targetSource = context.targetSource
        } else if trackingPolicyMode == .automatic {
            targetSource = preferredTrackingSource.other
        } else {
            targetSource = manualTrackingSource
        }

        let readiness = latestSourceReadiness[targetSource] ?? sourceReadiness(for: targetSource)
        guard let blocker = readiness.blockers.first else {
            evaluateTrackingPolicy(force: true)
            return
        }

        switch blocker {
        case .needsPermission:
            detector(for: targetSource).requestAuthorization { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        let updatedReadiness = self.sourceReadiness(for: targetSource)
                        let remaining = updatedReadiness.blockers
                        if remaining.first == .needsCalibration {
                            self.startCalibration(for: targetSource)
                        } else {
                            self.evaluateTrackingPolicy(force: true)
                        }
                    } else {
                        self.evaluateTrackingPolicy(force: true)
                    }
                }
            }
        case .permissionDenied:
            openPrivacySettings(for: targetSource)
        case .needsConnection:
            presentConnectionHelp(for: targetSource)
        case .needsCalibration:
            startCalibration(for: targetSource)
        }
    }

    @discardableResult
    func openPrivacySettings(for source: TrackingSource) -> Bool {
        let candidates: [String]
        switch source {
        case .camera:
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
            ]
        case .airpods:
            // Core Motion permission for AirPods head tracking can map to different anchors across macOS versions.
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_MotionUsage"
            ]
        }

        for rawURL in candidates {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        guard let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else {
            return false
        }
        return NSWorkspace.shared.open(privacyURL)
    }

    private func presentConnectionHelp(for source: TrackingSource) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = source == .airpods
            ? L("alert.connectAirPods.title")
            : L("alert.connectCamera.title")
        alert.informativeText = source == .airpods
            ? L("alert.connectAirPods.message")
            : L("alert.connectCamera.message")
        alert.addButton(withTitle: source == .airpods ? L("alert.openBluetooth") : L("common.ok"))
        alert.addButton(withTitle: L("common.cancel"))

        NSApp.activate(ignoringOtherApps: true)
        if source == .airpods, alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Bluetooth")!)
        }
    }

    // MARK: - Observers Setup

    private func setupObservers() {
        // Display configuration changes
        displayMonitor.onDisplayConfigurationChange = { [weak self] in
            Task { @MainActor in
                self?.handleDisplayConfigurationChange()
            }
        }
        displayMonitor.startMonitoring()

        // Camera hot-plug
        cameraObserver.onCameraConnected = { [weak self] device in
            Task { @MainActor in
                self?.handleCameraConnected(device)
            }
        }
        cameraObserver.onCameraDisconnected = { [weak self] device in
            Task { @MainActor in
                self?.handleCameraDisconnected(device)
            }
        }
        cameraObserver.startObserving()

        // Screen lock/unlock
        screenLockObserver.onScreenLocked = { [weak self] in
            Task { @MainActor in
                self?.handleScreenLocked()
            }
        }
        screenLockObserver.onScreenUnlocked = { [weak self] in
            Task { @MainActor in
                self?.handleScreenUnlocked()
            }
        }
        screenLockObserver.startObserving()

        // Global hotkey
        hotkeyManager.configure(
            enabled: toggleShortcutEnabled,
            shortcut: toggleShortcut,
            onToggle: { [weak self] in
                Task { @MainActor in
                    self?.toggleEnabled()
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
                self?.toggleEnabled()
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

    private func toggleEnabled() {
        if case .disabled = state {
            if trackingPolicyMode == .manual {
                trackingSource = manualTrackingSource
            }
            evaluateTrackingPolicy(force: true, allowFromDisabled: true)
        } else {
            state = .disabled
        }
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
        policyEvaluationTimer?.invalidate()
        policyEvaluationTimer = nil
        cameraDetector.stop()
        airPodsDetector.stop()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Initial Setup Flow

    func initialSetupFlow() {
        guard !setupComplete else { return }
        setupComplete = true

        if isMarketingMode {
            startMonitoring()
            return
        }

        let configKey = DisplayMonitor.getCurrentConfigKey()
        if let profile = loadProfile(forKey: configKey) {
            let cameras = cameraDetector.getAvailableCameras()
            if cameras.contains(where: { $0.uniqueID == profile.cameraID }) {
                cameraDetector.selectedCameraID = profile.cameraID
                cameraCalibration = CameraCalibrationData(
                    goodPostureY: profile.goodPostureY,
                    badPostureY: profile.badPostureY,
                    neutralY: profile.neutralY,
                    postureRange: profile.postureRange,
                    cameraID: profile.cameraID
                )
            }
        }

        if trackingPolicyMode == .manual {
            trackingSource = manualTrackingSource
            if isCalibrated(for: manualTrackingSource) {
                evaluateTrackingPolicy(force: true, allowFromDisabled: true)
                return
            }
        } else {
            if isCalibrated(for: .camera) || isCalibrated(for: .airpods) {
                evaluateTrackingPolicy(force: true, allowFromDisabled: true)
                return
            }
        }

        // No valid calibration - show onboarding
        showOnboarding()
    }

    func showOnboarding() {
        onboardingWindowController = OnboardingWindowController()
        onboardingWindowController?.show(
            cameraDetector: cameraDetector,
            airPodsDetector: airPodsDetector
        ) { [weak self] source, cameraID in
            Task { @MainActor in
                guard let self else { return }

                self.onboardingWindowController = nil
                self.trackingPolicyMode = .manual
                self.manualTrackingSource = source
                self.preferredTrackingSource = source
                self.trackingSource = source
                if let cameraID = cameraID {
                    self.cameraDetector.selectedCameraID = cameraID
                }
                self.saveSettings()

                // Start calibration
                self.startCalibration(for: source)
            }
        }
    }

    // MARK: - Tracking Source Management

    func setTrackingPolicyMode(_ mode: TrackingPolicyMode) {
        trackingPolicyMode = mode
        if mode == .manual {
            trackingSource = manualTrackingSource
        }
        // Policy changes can alter probe requirements even when state/source stay the same.
        syncDetectorToState()
        saveSettings()
        evaluateTrackingPolicy(force: true)
    }

    func setPreferredTrackingSource(_ source: TrackingSource) {
        preferredTrackingSource = source
        if trackingPolicyMode == .automatic {
            // Preferred source updates can require starting/stopping AirPods probe immediately.
            syncDetectorToState()
            evaluateTrackingPolicy(force: true)
        }
        saveSettings()
    }

    func setManualTrackingSource(_ source: TrackingSource) {
        manualTrackingSource = source
        if trackingPolicyMode == .manual {
            trackingSource = source
            evaluateTrackingPolicy(force: true)
        }
        saveSettings()
    }

    func setAutoReturnEnabled(_ enabled: Bool) {
        autoReturnEnabled = enabled
        syncDetectorToState()
        saveSettings()
        evaluateTrackingPolicy(force: true)
    }

    func switchTrackingSource(to source: TrackingSource) {
        setManualTrackingSource(source)
    }

    // MARK: - Calibration

    func startCalibration(for source: TrackingSource? = nil) {
        let targetSource = source ?? trackingSource
        if targetSource != trackingSource {
            trackingSource = targetSource
        }

        // Prevent multiple concurrent calibrations.
        guard !calibrationStartInFlight, calibrationController == nil else { return }
        calibrationStartInFlight = true

        let calibrationDetector = detector(for: targetSource)
        os_log(.info, log: log, "Starting calibration for %{public}@", targetSource.displayName)

        // Request authorization (this shows permission dialog if needed)
        calibrationDetector.requestAuthorization { [weak self] authorized in
            Task { @MainActor in
                guard let self else { return }
                self.calibrationStartInFlight = false

                if !authorized {
                    os_log(.error, log: log, "Authorization denied for %{public}@", targetSource.displayName)

                    // During onboarding/first-run, denial can happen while the app is still
                    // disabled; force an actionable paused state so Settings/menu reflect
                    // the blocker and can surface the privacy CTA.
                    let blocker: SourceBlocker = self.permissionState(for: targetSource) == .notDetermined
                        ? .needsPermission
                        : .permissionDenied
                    self.pauseForSourceUnavailable(
                        source: targetSource,
                        blockers: [blocker],
                        isFallback: self.trackingPolicyMode == .automatic && targetSource != self.preferredTrackingSource
                    )

                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = L("alert.permissionRequired")
                    alert.informativeText = targetSource == .airpods
                        ? L("alert.permissionRequired.airpods")
                        : L("alert.permissionRequired.camera")
                    alert.addButton(withTitle: L("alert.openSettings"))
                    alert.addButton(withTitle: L("common.cancel"))
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertFirstButtonReturn {
                        self.openPrivacySettings(for: targetSource)
                    }
                    return
                }

                if self.trackingSource != targetSource {
                    self.trackingSource = targetSource
                }

                // Authorization granted - now start calibration
                self.state = .calibrating(targetSource)
                self.startDetectorAndShowCalibration(source: targetSource, detector: calibrationDetector)
            }
        }
    }

    private func startDetectorAndShowCalibration(source: TrackingSource, detector: PostureDetector) {
        // Double-check no calibration controller already exists
        guard calibrationController == nil else {
            calibrationStartInFlight = false
            os_log(.info, log: log, "Skipping calibration window - already exists")
            return
        }

        calibrationStartInFlight = true
        let controller = CalibrationWindowController()
        calibrationController = controller

        detector.start { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.calibrationStartInFlight = false

                if !success {
                    self.calibrationController = nil
                    os_log(.error, log: log, "Failed to start detector for calibration (%{public}@): %{public}@", source.displayName, error ?? "unknown")
                    self.pauseForSourceUnavailable(
                        source: source,
                        blockers: [.needsConnection],
                        isFallback: self.trackingPolicyMode == .automatic && source != self.preferredTrackingSource
                    )
                    if source == .camera {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = L("alert.cameraNotAvailable")
                        alert.informativeText = error ?? L("alert.cameraNotAvailable.message")
                        alert.addButton(withTitle: L("alert.tryAgain"))
                        alert.addButton(withTitle: L("common.cancel"))
                        NSApp.activate(ignoringOtherApps: true)
                        if alert.runModal() == .alertFirstButtonReturn {
                            self.startCalibration(for: source)
                        }
                    }
                    return
                }

                guard let controller = self.calibrationController else { return }
                controller.start(
                    detector: detector,
                    onComplete: { [weak self] values in
                        Task { @MainActor in
                            self?.finishCalibration(values: values)
                        }
                    },
                    onCancel: { [weak self] in
                        Task { @MainActor in
                            self?.cancelCalibration()
                        }
                    }
                )
            }
        }
    }

    func finishCalibration(values: [CalibrationSample]) {
        guard values.count >= 4 else {
            cancelCalibration()
            return
        }

        os_log(.info, log: log, "Finishing calibration with %d values", values.count)

        // Create calibration data using the source that produced the captured samples.
        // This avoids retrigger loops if trackingSource changed while calibration was in flight.
        let calibrationSource = inferredCalibrationSource(from: values) ?? trackingSource
        let calibrationDetector = detector(for: calibrationSource)
        guard let calibration = calibrationDetector.createCalibrationData(from: values) else {
            cancelCalibration()
            return
        }

        if trackingSource != calibrationSource {
            trackingSource = calibrationSource
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
        calibrationStartInFlight = false
        calibrationController = nil

        monitoringState.reset()

        evaluateTrackingPolicy(force: true)
    }

    private func inferredCalibrationSource(from values: [CalibrationSample]) -> TrackingSource? {
        var cameraSamples = 0
        var airPodsSamples = 0

        for sample in values {
            switch sample {
            case .camera:
                cameraSamples += 1
            case .airPods:
                airPodsSamples += 1
            }
        }

        if cameraSamples == 0, airPodsSamples == 0 {
            return nil
        }
        if airPodsSamples > cameraSamples {
            return .airpods
        }
        if cameraSamples > airPodsSamples {
            return .camera
        }

        // Tie-break with current source to keep behavior stable.
        return trackingSource
    }

    func cancelCalibration() {
        calibrationStartInFlight = false
        calibrationController = nil
        evaluateTrackingPolicy(force: true)
    }

    func startMonitoring(for source: TrackingSource? = nil) {
        if let source, source != trackingSource {
            trackingSource = source
        }

        if isMarketingMode {
            state = .monitoring(trackingSource)
            return
        }

        guard let calibration = currentCalibration else {
            pauseForSourceUnavailable(
                source: trackingSource,
                blockers: [.needsCalibration],
                isFallback: trackingPolicyMode == .automatic && trackingSource != preferredTrackingSource
            )
            return
        }

        // For AirPods, check if they're actually in ears before monitoring
        if trackingSource == .airpods && !activeDetector.isConnected {
            os_log(.info, log: log, "AirPods not in ears - pausing instead of monitoring")
            activeDetector.beginMonitoring(with: calibration, intensity: activeIntensity, deadZone: activeDeadZone)
            pauseForSourceUnavailable(
                source: .airpods,
                blockers: [.needsConnection],
                isFallback: trackingPolicyMode == .automatic && trackingSource != preferredTrackingSource
            )
            return
        }

        lastPostureReadingTime = nil
        activeDetector.beginMonitoring(with: calibration, intensity: activeIntensity, deadZone: activeDeadZone)
        state = .monitoring(trackingSource)
    }

    // MARK: - Camera Management (for Settings compatibility)

    func getAvailableCameras() -> [AVCaptureDevice] {
        return cameraDetector.getAvailableCameras()
    }

    func restartCamera() {
        guard trackingSource == .camera, let cameraID = selectedCameraID else { return }
        cameraDetector.switchCamera(to: cameraID)
        cameraCalibration = nil
        evaluateTrackingPolicy(force: true)
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

    private func handleCameraConnected(_ device: AVCaptureDevice) {
        if selectedCameraID == nil {
            cameraDetector.selectedCameraID = device.uniqueID
        }
        loadCameraCalibrationForCurrentDisplayIfAvailable(cameraID: device.uniqueID)
        evaluateTrackingPolicy(force: true)
    }

    private func handleCameraDisconnected(_ device: AVCaptureDevice) {
        guard device.uniqueID == selectedCameraID else {
            evaluateTrackingPolicy(force: true)
            return
        }

        let cameras = cameraDetector.getAvailableCameras()
        if let fallbackCamera = cameras.first {
            cameraDetector.selectedCameraID = fallbackCamera.uniqueID
            cameraDetector.switchCamera(to: fallbackCamera.uniqueID)
            loadCameraCalibrationForCurrentDisplayIfAvailable(cameraID: fallbackCamera.uniqueID)
        } else {
            cameraCalibration = nil
        }

        evaluateTrackingPolicy(force: true)
    }

    // MARK: - Screen Lock Detection

    private func handleScreenLocked() {
        if case .disabled = state { return }
        if case .paused(.screenLocked, _) = state { return }
        stateBeforeLock = state
        state = .paused(.screenLocked, context: nil)
    }

    private func handleScreenUnlocked() {
        guard case .paused(.screenLocked, _) = state else { return }

        if let previousState = stateBeforeLock {
            stateBeforeLock = nil
            switch previousState {
            case .monitoring(let source):
                // Re-enter monitoring via startMonitoring() so detector monitoring
                // state and calibration are re-applied after the pause stopped them.
                startMonitoring(for: source)
            default:
                state = previousState
            }
        } else {
            evaluateTrackingPolicy(force: true)
        }
    }

    // MARK: - Display Configuration

    private func handleDisplayConfigurationChange() {
        rebuildOverlayWindows()

        guard case .disabled = state else {
            if pauseOnTheGo && DisplayMonitor.isLaptopOnlyConfiguration() {
                state = .paused(.onTheGo, context: nil)
                return
            }

            if let selectedCameraID {
                let configKey = DisplayMonitor.getCurrentConfigKey()
                if let profile = loadProfile(forKey: configKey), profile.cameraID == selectedCameraID {
                    cameraCalibration = CameraCalibrationData(
                        goodPostureY: profile.goodPostureY,
                        badPostureY: profile.badPostureY,
                        neutralY: profile.neutralY,
                        postureRange: profile.postureRange,
                        cameraID: profile.cameraID
                    )
                } else {
                    cameraCalibration = nil
                }
            }

            evaluateTrackingPolicy(force: true)
            return
        }
    }

}
