import AppKit
import AVFoundation
import Vision
import Carbon.HIToolbox

// MARK: - Icon Masking Utility

func applyMacOSIconMask(to image: NSImage) -> NSImage {
    let size = NSSize(width: 512, height: 512)

    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return image }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)

    let cornerRadius = size.width * 0.2237
    let rect = NSRect(origin: .zero, size: size)

    NSColor.clear.setFill()
    rect.fill()

    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    let result = NSImage(size: size)
    result.addRepresentation(bitmapRep)
    return result
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    // UI Components
    var statusItem: NSStatusItem!
    var statusMenuItem: NSMenuItem!
    var enabledMenuItem: NSMenuItem!
    var recalibrateMenuItem: NSMenuItem!

    // Overlay windows and blur
    var windows: [NSWindow] = []
    var blurViews: [NSVisualEffectView] = []
    var currentBlurRadius: Int32 = 0
    var targetBlurRadius: Int32 = 0

    // Warning overlay (alternative to blur)
    var warningOverlayManager = WarningOverlayManager()
    var warningMode: WarningMode = .blur
    var warningColor: NSColor = WarningDefaults.color

    // Camera
    var captureSession: AVCaptureSession?
    var videoOutput: AVCaptureVideoDataOutput?
    let captureQueue = DispatchQueue(label: "capture.queue")
    var selectedCameraID: String?

    // Calibration
    var calibrationController: CalibrationWindowController?
    var isCalibrated = false
    var goodPostureY: CGFloat = 0.6
    var badPostureY: CGFloat = 0.4
    var neutralY: CGFloat = 0.5
    var postureRange: CGFloat = 0.2

    // Settings
    var intensity: CGFloat = 1.0
    var deadZone: CGFloat = 0.03
    var useCompatibilityMode = false
    var blurWhenAway = false
    var showInDock = false
    var pauseOnTheGo = false
    var detectionMode: DetectionMode = .balanced
    var settingsWindowController = SettingsWindowController()
    var analyticsWindowController: AnalyticsWindowController?

    // Tracking Source (Camera or AirPods)
    var trackingSource: TrackingSource = .camera {
        didSet {
            syncCameraToState()
            syncAirPodsToState()
            
            DispatchQueue.main.async { [weak self] in
                 self?.updateTrackingMenu()
            }
        }
    }
    var headphoneMotionManager = HeadphoneMotionManager()
    var airPodsProfile: AirPodsProfile?

    // Display management
    var displayDebounceTimer: Timer?

    // Camera observers
    var cameraConnectedObserver: NSObjectProtocol?
    var cameraDisconnectedObserver: NSObjectProtocol?

    // Screen lock observers
    var screenLockObserver: NSObjectProtocol?
    var screenUnlockObserver: NSObjectProtocol?
    var stateBeforeLock: AppState?

    // Detection state
    var lastDetectionTime = Date()
    var consecutiveBadFrames = 0
    var consecutiveGoodFrames = 0
    var consecutiveNoDetectionFrames = 0
    let frameThreshold = 8
    let awayFrameThreshold = 15

    // Smoothing
    var noseYHistory: [CGFloat] = []
    let smoothingWindow = 5
    var smoothedNoseY: CGFloat = 0.5
    var currentNoseY: CGFloat = 0.5

    // Hysteresis
    var isCurrentlySlouching = false
    var isCurrentlyAway = false

    // Separate intensities for different concerns (0.0 to 1.0)
    var postureWarningIntensity: CGFloat = 0  // Posture-based warning
    // Privacy blur is derived from isCurrentlyAway (always full blur when away)

    // Blur onset delay
    var warningOnsetDelay: Double = 0.0
    var badPostureStartTime: Date?

    // Global keyboard shortcut (Carbon API)
    var toggleShortcutEnabled = true
    var toggleShortcut = KeyboardShortcut.defaultShortcut
    var carbonHotKeyRef: EventHotKeyRef?
    var carbonEventHandler: EventHandlerRef?

    // Frame throttling
    var lastFrameTime: Date = .distantPast
    // Use fast polling (10 fps) when slouching for quick recovery detection
    var frameInterval: TimeInterval {
        isCurrentlySlouching ? 0.1 : (1.0 / detectionMode.frameRate)
    }

    var cameraSetupComplete = false
    var waitingForPermission = false

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
        syncCameraToState()
        syncAirPodsToState()
        if !newState.isActive {
            targetBlurRadius = 0
            postureWarningIntensity = 0  // Clear any active posture warning
        }
        syncUIToState()
    }

    private func syncAirPodsToState() {
        let shouldRun: Bool
        switch state {
        case .calibrating, .monitoring:
            shouldRun = (trackingSource == .airpods)
        case .disabled, .paused:
            shouldRun = false
        }
        
        if shouldRun {
            if !headphoneMotionManager.isActive {
                headphoneMotionManager.startTracking()
            }
        } else {
            if headphoneMotionManager.isActive {
                headphoneMotionManager.stopTracking()
            }
        }
    }

    private func syncCameraToState() {
        let shouldRun: Bool
        switch state {
        case .calibrating, .monitoring:
            shouldRun = (trackingSource == .camera)
        case .disabled, .paused:
            shouldRun = false
        }


        if shouldRun {
            ensureCameraInput()

            if !(captureSession?.isRunning ?? false) {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.captureSession?.startRunning()
                    DispatchQueue.main.async {
                    }
                }
            }
        } else if captureSession?.isRunning ?? false {
            captureSession?.stopRunning()
        }
    }

    private func syncUIToState() {
        switch state {
        case .disabled:
            statusMenuItem.title = "Status: Disabled"
            statusItem.button?.image = NSImage(systemSymbolName: "figure.stand.line.dotted.figure.stand", accessibilityDescription: "Disabled")

        case .calibrating:
            statusMenuItem.title = "Status: Calibrating..."
            statusItem.button?.image = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: "Calibrating")

        case .monitoring:
            if isCalibrated {
                statusMenuItem.title = "Status: Good Posture"
                statusItem.button?.image = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: "Good Posture")
            } else {
                statusMenuItem.title = "Status: Starting..."
                statusItem.button?.image = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: "Posturr")
            }

        case .paused(let reason):
            switch reason {
            case .noProfile:
                statusMenuItem.title = "Status: Calibration needed"
            case .onTheGo:
                statusMenuItem.title = "Status: Paused (on the go - recalibrate)"
            case .cameraDisconnected:
                statusMenuItem.title = "Status: Camera disconnected"
            case .screenLocked:
                statusMenuItem.title = "Status: Paused (screen locked)"
            }
            statusItem.button?.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
        }

        enabledMenuItem.state = (state != .disabled) ? .on : .off

        let cameras = getAvailableCameras()
        let hasCamera = !cameras.isEmpty && (selectedCameraID == nil || cameras.contains { $0.uniqueID == selectedCameraID })
        if hasCamera && state != .calibrating {
            recalibrateMenuItem.title = "Recalibrate"
            recalibrateMenuItem.action = #selector(recalibrate)
            recalibrateMenuItem.isEnabled = true
        } else {
            recalibrateMenuItem.title = hasCamera ? "Recalibrate" : "Recalibrate (no camera)"
            recalibrateMenuItem.action = nil
            recalibrateMenuItem.isEnabled = false
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()

        if showInDock {
            NSApp.setActivationPolicy(.regular)
        }

        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = applyMacOSIconMask(to: icon)
        }

        setupMenuBar()
        setupOverlayWindows()
        setupAirPodsTracking()
        if warningMode.usesWarningOverlay {
            warningOverlayManager.mode = warningMode
            warningOverlayManager.warningColor = warningColor
            warningOverlayManager.setupOverlayWindows()
        }
        registerDisplayChangeCallback()
        registerCameraChangeNotifications()
        registerScreenLockNotifications()

        registerGlobalHotKey()

        Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            self?.updateBlur()
        }

        initialSetupFlow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return false
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: "Posturr")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Status: Starting...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledMenuItem.target = self
        enabledMenuItem.state = .on
        updateEnabledMenuItemShortcut()
        menu.addItem(enabledMenuItem)

        recalibrateMenuItem = NSMenuItem(title: "Recalibrate", action: #selector(recalibrate), keyEquivalent: "r")
        recalibrateMenuItem.target = self
        menu.addItem(recalibrateMenuItem)

        // Tracking Mode submenu
        let trackingMenu = NSMenu()
        let trackingItem = NSMenuItem(title: "Tracking Mode", action: nil, keyEquivalent: "")
        trackingItem.submenu = trackingMenu
        menu.addItem(trackingItem)
        
        let cameraItem = NSMenuItem(title: "Camera", action: #selector(setTrackingToCamera), keyEquivalent: "")
        cameraItem.target = self
        trackingMenu.addItem(cameraItem)
        
        let airpodsItem = NSMenuItem(title: "AirPods", action: #selector(setTrackingToAirPods), keyEquivalent: "")
        airpodsItem.target = self
        trackingMenu.addItem(airpodsItem)

        menu.addItem(NSMenuItem.separator())
        
        let statsItem = NSMenuItem(title: "Statistics", action: #selector(showAnalytics), keyEquivalent: "s")
        statsItem.target = self
        statsItem.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Statistics")
        menu.addItem(statsItem)

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        
        // Initialize checkmarks
        updateTrackingMenu()
    }
    
    // Update Tracking Mode menu checkmarks
    func updateTrackingMenu() {
        guard let menu = statusItem.menu,
              let trackingItem = menu.items.first(where: { $0.title == "Tracking Mode" }),
              let submenu = trackingItem.submenu else { return }
              
        if let cameraItem = submenu.items.first(where: { $0.title == "Camera" }) {
            cameraItem.state = (trackingSource == .camera) ? .on : .off
        }
        
        if let airpodsItem = submenu.items.first(where: { $0.title == "AirPods" }) {
            airpodsItem.state = (trackingSource == .airpods) ? .on : .off
        }
    }

    // MARK: - Menu Actions

    @objc func toggleEnabled() {
        if state == .disabled {
            // Note: We intentionally don't check pauseOnTheGo here.
            // "Pause on the go" should only trigger when display config *changes*
            // to laptop-only (e.g., unplugging external monitor), not when the
            // user explicitly enables the app via menu or keyboard shortcut.
            if !isCalibrated {
                state = .paused(.noProfile)
            } else if !isCameraAvailable() {
                state = .paused(.cameraDisconnected)
            } else {
                state = .monitoring
            }
        } else {
            state = .disabled
        }
        saveSettings()
    }

    @objc func recalibrate() {
        startCalibration()
    }

    @objc func showAnalytics() {
        if analyticsWindowController == nil {
            analyticsWindowController = AnalyticsWindowController()
        }
        
        analyticsWindowController?.showWindow(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettings() {
        settingsWindowController.showSettings(appDelegate: self, fromStatusItem: statusItem)
    }
    
    @objc func setTrackingToCamera() {
        trackingSource = .camera
        saveSettings()
        
        // Ensure camera is setup and running
        setupCamera()
        
        // Restart calibration clearly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startCalibration()
        }
    }
    
    @objc func setTrackingToAirPods() {
        trackingSource = .airpods
        saveSettings()
        
        // Request permission/data -> Calibrate
        headphoneMotionManager.startTracking { [weak self] in
            DispatchQueue.main.async {
                self?.startCalibration()
            }
        }
    }

    @objc func quit() {
        captureSession?.stopRunning()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Initial Setup Flow

    func initialSetupFlow() {
        // Step 1: Request Camera Permission (for Camera mode)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        if status == .notDetermined {
            statusMenuItem.title = "Status: Requesting permissions..."
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.setupAndShowModeSelection()
                }
            }
        } else {
            setupAndShowModeSelection()
        }
    }
    
    func setupAndShowModeSelection() {
        guard !cameraSetupComplete else { return }
        cameraSetupComplete = true
        
        let configKey = getCurrentConfigKey()
        
        // If profile exists, load it and start monitoring
        if let profile = loadProfile(forKey: configKey) {
            let cameras = getAvailableCameras()
            
            // Check if profile is valid
            if cameras.contains(where: { $0.uniqueID == profile.cameraID }) || trackingSource == .airpods {
                selectedCameraID = profile.cameraID
                applyProfile(profile)
                state = .monitoring
                
                if trackingSource == .airpods {
                    headphoneMotionManager.startTracking()
                } else {
                    setupCamera()
                }
                return
            } else {
                state = .paused(.cameraDisconnected)
                return
            }
        }
        
        // No profile -> Show Mode Selection
        promptForTrackingSource { [weak self] source in
            guard let self = self else { return }
            self.trackingSource = source
            self.saveSettings()
            self.updateTrackingMenu()
            
            // Start Calibration based on selected mode
            if source == .camera {
                self.setupCamera()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startCalibration()
                }
            } else {
                // AirPods: Wait for permission/data before calibrating
                self.headphoneMotionManager.startTracking { [weak self] in
                    DispatchQueue.main.async {
                        self?.startCalibration()
                    }
                }
            }
        }
    }
    
    func promptForTrackingSource(completion: @escaping (TrackingSource) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Select Tracking Method"
        alert.informativeText = "Choose how you want to track your posture."
        alert.addButton(withTitle: "Camera")
        alert.addButton(withTitle: "AirPods")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completion(.camera)
        } else {
            completion(.airpods)
        }
    }

    func onCameraPermissionGranted() {
        guard waitingForPermission else { return }
        waitingForPermission = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startCalibration()
        }
    }

    func handleCameraDenied() {
        state = .disabled
        statusMenuItem.title = "Status: Camera access denied"

        let alert = NSAlert()
        alert.messageText = "Camera Access Required"
        alert.informativeText = "Posturr needs camera access to monitor your posture.\n\nPlease enable it in System Settings > Privacy & Security > Camera."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Camera Management

    func getAvailableCameras() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        return discoverySession.devices
    }

    private func isCameraAvailable() -> Bool {
        let cameras = getAvailableCameras()
        return !cameras.isEmpty && (selectedCameraID == nil || cameras.contains { $0.uniqueID == selectedCameraID })
    }

    func restartCamera() {
        switchCameraInput()
        state = .paused(.noProfile)
    }

    func applyDetectionMode() {
        guard let session = captureSession else { return }

        session.beginConfiguration()

        // Configure camera to capture at lower frame rate
        if let input = session.inputs.first as? AVCaptureDeviceInput {
            let device = input.device
            configureDeviceFrameRate(device)
        }

        session.commitConfiguration()
    }

    private func configureDeviceFrameRate(_ device: AVCaptureDevice) {
        let targetFrameRate = detectionMode.frameRate

        // Find the lowest supported frame rate across all ranges
        var minSupported = 30.0  // Default fallback
        for range in device.activeFormat.videoSupportedFrameRateRanges {
            minSupported = min(minSupported, range.minFrameRate)
        }

        // Clamp to supported range - can't go below what camera supports
        let actualFrameRate = max(targetFrameRate, minSupported)

        // Frame duration = 1/fps
        let frameDuration = CMTimeMake(value: 1, timescale: Int32(actualFrameRate))

        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()
        } catch {
        }
    }

    private func switchCameraInput() {
        let wasRunning = captureSession?.isRunning ?? false

        if wasRunning {
            captureSession?.stopRunning()
        }

        if let inputs = captureSession?.inputs {
            for input in inputs {
                captureSession?.removeInput(input)
            }
        }

        let cameras = getAvailableCameras()
        let camera = cameras.first { $0.uniqueID == selectedCameraID } ?? cameras.first

        guard let selectedCamera = camera else {
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: selectedCamera)
            selectedCameraID = selectedCamera.uniqueID
            captureSession?.addInput(input)
        } catch {
            return
        }

        if wasRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.startRunning()
            }
        }
    }

    private func ensureCameraInput() {
        guard let session = captureSession else {
            return
        }

        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            if currentInput.device.uniqueID == selectedCameraID {
                return
            }
        } else {
        }

        switchCameraInput()
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .cif352x288  // Low resolution for CPU efficiency

        let cameras = getAvailableCameras()
        let camera: AVCaptureDevice?

        if let selectedID = selectedCameraID {
            camera = cameras.first { $0.uniqueID == selectedID }
        } else {
            camera = cameras.first { $0.position == .front } ?? cameras.first
        }

        guard let selectedCamera = camera,
              let input = try? AVCaptureDeviceInput(device: selectedCamera) else {
            statusMenuItem.title = "Status: No Camera"
            return
        }

        if selectedCameraID == nil {
            selectedCameraID = selectedCamera.uniqueID
        }

        captureSession?.addInput(input)

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        videoOutput?.setSampleBufferDelegate(self, queue: captureQueue)

        if let videoOutput = videoOutput {
            captureSession?.addOutput(videoOutput)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
            // Must configure frame rate AFTER session starts on macOS
            // Otherwise the session preset overrides our settings
            DispatchQueue.main.async {
                self.applyDetectionMode()
            }
        }
    }

    // MARK: - Camera Hot-Plug

    func registerCameraChangeNotifications() {
        cameraConnectedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCameraConnected(notification)
        }

        cameraDisconnectedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCameraDisconnected(notification)
        }
    }

    func handleCameraConnected(_ notification: Notification) {
        syncUIToState()

        guard let device = notification.object as? AVCaptureDevice,
              device.hasMediaType(.video),
              case .paused(let reason) = state else { return }

        let configKey = getCurrentConfigKey()
        if let profile = loadProfile(forKey: configKey),
           profile.cameraID == device.uniqueID {
            selectedCameraID = profile.cameraID
            applyProfile(profile)
            switchCameraInput()
            state = .monitoring
        } else if reason == .cameraDisconnected {
            state = .paused(.noProfile)
        }
    }

    func handleCameraDisconnected(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice,
              device.hasMediaType(.video) else { return }


        guard device.uniqueID == selectedCameraID else {
            syncUIToState()
            return
        }

        let cameras = getAvailableCameras()

        if let fallbackCamera = cameras.first {
            selectedCameraID = fallbackCamera.uniqueID
            switchCameraInput()

            let configKey = getCurrentConfigKey()
            if let profile = loadProfile(forKey: configKey), profile.cameraID == fallbackCamera.uniqueID {
                applyProfile(profile)
                state = .monitoring
            } else {
                state = .paused(.noProfile)
            }
        } else {
            state = .paused(.cameraDisconnected)
        }
    }

    // MARK: - Screen Lock Detection

    func registerScreenLockNotifications() {
        let dnc = DistributedNotificationCenter.default()

        screenLockObserver = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenLocked()
        }

        screenUnlockObserver = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenUnlocked()
        }
    }

    func handleScreenLocked() {

        // Only save state and pause if we're in an active state
        guard state.isActive || (state != .disabled && state != .paused(.screenLocked)) else {
            return
        }

        stateBeforeLock = state
        state = .paused(.screenLocked)
    }

    func handleScreenUnlocked() {

        // Only restore if we paused due to screen lock
        guard case .paused(.screenLocked) = state else {
            return
        }

        if let previousState = stateBeforeLock {
            state = previousState
            stateBeforeLock = nil
        } else {
            state = .monitoring
        }
    }

    // MARK: - Global Keyboard Shortcut (Carbon API)

    func registerGlobalHotKey() {
        // Unregister existing hotkey if any
        unregisterGlobalHotKey()

        guard toggleShortcutEnabled else { return }

        // Convert NSEvent modifier flags to Carbon modifiers
        let carbonModifiers = carbonModifiersFromNSEvent(toggleShortcut.modifiers)

        // Create hotkey ID
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x504F5354)  // 'POST' for Posturr
        hotKeyID.id = 1

        // Install event handler if not already installed
        if carbonEventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )

            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, _) -> OSStatus in
                    // Get the AppDelegate and call toggleEnabled
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        DispatchQueue.main.async {
                            appDelegate.toggleEnabled()
                        }
                    }
                    return noErr
                },
                1,
                &eventType,
                nil,
                &(NSApp.delegate as! AppDelegate).carbonEventHandler
            )

            if status != noErr {
                return
            }
        }

        // Register the hotkey
        let status = RegisterEventHotKey(
            UInt32(toggleShortcut.keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )

        if status != noErr {
        }
    }

    func unregisterGlobalHotKey() {
        if let hotKeyRef = carbonHotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            carbonHotKeyRef = nil
        }
    }

    func carbonModifiersFromNSEvent(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        return carbonMods
    }

    func updateGlobalKeyMonitor() {
        registerGlobalHotKey()
        updateEnabledMenuItemShortcut()
    }

    func updateEnabledMenuItemShortcut() {
        guard let menuItem = enabledMenuItem else { return }

        if toggleShortcutEnabled {
            // Show shortcut hint in the menu item title
            menuItem.title = "Enabled (\(toggleShortcut.displayString))"
        } else {
            menuItem.title = "Enabled"
        }
    }

    // MARK: - Calibration

    func startCalibration() {
        guard state != .calibrating else {
            return
        }

        isCalibrated = false
        state = .calibrating


        
        let calibrations = CalibrationWindowController()
        calibrationController = calibrations
        
        calibrations.start(
            trackingSource: trackingSource,
            onComplete: { [weak self] values, motions in
                guard let self = self else { return }
                
                if self.trackingSource == .airpods {
                    // AirPods Calibration Complete (Average of 4 corners)
                    var avgPitch = 0.0
                    var avgRoll = 0.0
                    var avgYaw = 0.0
                    
                    if !motions.isEmpty {
                        avgPitch = motions.map { $0.0 }.reduce(0, +) / Double(motions.count)
                        avgRoll = motions.map { $0.1 }.reduce(0, +) / Double(motions.count)
                        avgYaw = motions.map { $0.2 }.reduce(0, +) / Double(motions.count)
                    }
                    
                    let profile = AirPodsProfile(
                        pitch: avgPitch,
                        roll: avgRoll,
                        yaw: avgYaw
                    )
                    self.airPodsProfile = profile
                    self.saveSettings()
                    
                    self.isCalibrated = true
                    self.calibrationController = nil
                    
                    self.state = .monitoring
                } else {
                    // Camera Calibration Complete (Original Logic)

                    let maxY = values.max() ?? 0.6
                    let minY = values.min() ?? 0.4
                    let avgY = values.reduce(0, +) / CGFloat(values.count)

                    self.goodPostureY = maxY
                    self.badPostureY = minY
                    self.neutralY = avgY
                    self.postureRange = abs(maxY - minY)

                    let profile = ProfileData(
                        goodPostureY: self.goodPostureY,
                        badPostureY: self.badPostureY,
                        neutralY: self.neutralY,
                        postureRange: self.postureRange,
                        cameraID: self.selectedCameraID ?? ""
                    )
                    let configKey = self.getCurrentConfigKey()
                    self.saveProfile(forKey: configKey, data: profile)

                    self.isCalibrated = true
                    self.calibrationController = nil

                    self.consecutiveBadFrames = 0
                    self.consecutiveGoodFrames = 0

                    self.state = .monitoring
                }
            },
            onCancel: { [weak self] in
                self?.calibrationController = nil
                self?.isCalibrated = true
                self?.state = .monitoring
            }
        )
    }

    func applyProfile(_ profile: ProfileData) {
        goodPostureY = profile.goodPostureY
        badPostureY = profile.badPostureY
        neutralY = profile.neutralY
        postureRange = profile.postureRange
        isCalibrated = true
    }

    // MARK: - Persistence

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(intensity, forKey: SettingsKeys.intensity)
        defaults.set(deadZone, forKey: SettingsKeys.deadZone)
        defaults.set(useCompatibilityMode, forKey: SettingsKeys.useCompatibilityMode)
        defaults.set(blurWhenAway, forKey: SettingsKeys.blurWhenAway)
        defaults.set(showInDock, forKey: SettingsKeys.showInDock)
        defaults.set(pauseOnTheGo, forKey: SettingsKeys.pauseOnTheGo)
        defaults.set(detectionMode.rawValue, forKey: SettingsKeys.detectionMode)
        defaults.set(warningMode.rawValue, forKey: SettingsKeys.warningMode)
        defaults.set(warningOnsetDelay, forKey: SettingsKeys.warningOnsetDelay)
        defaults.set(toggleShortcutEnabled, forKey: SettingsKeys.toggleShortcutEnabled)
        defaults.set(Int(toggleShortcut.keyCode), forKey: SettingsKeys.toggleShortcutKeyCode)
        defaults.set(Int(toggleShortcut.modifiers.rawValue), forKey: SettingsKeys.toggleShortcutModifiers)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: warningColor, requiringSecureCoding: false) {
            defaults.set(colorData, forKey: SettingsKeys.warningColor)
        }
        if let cameraID = selectedCameraID {
            defaults.set(cameraID, forKey: SettingsKeys.lastCameraID)
        }
        defaults.set(trackingSource.rawValue, forKey: SettingsKeys.trackingSource)
        if let airPodsProfile = airPodsProfile,
           let profileData = try? JSONEncoder().encode(airPodsProfile) {
            defaults.set(profileData, forKey: SettingsKeys.airPodsProfile)
        }
    }

    func loadSettings() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: SettingsKeys.intensity) != nil {
            intensity = defaults.double(forKey: SettingsKeys.intensity)
        }
        if defaults.object(forKey: SettingsKeys.deadZone) != nil {
            deadZone = defaults.double(forKey: SettingsKeys.deadZone)
        }
        useCompatibilityMode = defaults.bool(forKey: SettingsKeys.useCompatibilityMode)
        blurWhenAway = defaults.bool(forKey: SettingsKeys.blurWhenAway)
        showInDock = defaults.bool(forKey: SettingsKeys.showInDock)
        pauseOnTheGo = defaults.bool(forKey: SettingsKeys.pauseOnTheGo)
        if let modeString = defaults.string(forKey: SettingsKeys.detectionMode),
           let mode = DetectionMode(rawValue: modeString) {
            detectionMode = mode
        }
        selectedCameraID = defaults.string(forKey: SettingsKeys.lastCameraID)
        if let sourceString = defaults.string(forKey: SettingsKeys.trackingSource),
           let source = TrackingSource(rawValue: sourceString) {
            trackingSource = source
        }
        if let profileData = defaults.data(forKey: SettingsKeys.airPodsProfile),
           let profile = try? JSONDecoder().decode(AirPodsProfile.self, from: profileData) {
            airPodsProfile = profile
        }
        if let modeString = defaults.string(forKey: SettingsKeys.warningMode),
           let mode = WarningMode(rawValue: modeString) {
            warningMode = mode
        }
        if let colorData = defaults.data(forKey: SettingsKeys.warningColor),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            warningColor = color
        }
        if defaults.object(forKey: SettingsKeys.warningOnsetDelay) != nil {
            warningOnsetDelay = defaults.double(forKey: SettingsKeys.warningOnsetDelay)
        }
        // Shortcut settings - default to enabled if not set
        if defaults.object(forKey: SettingsKeys.toggleShortcutEnabled) != nil {
            toggleShortcutEnabled = defaults.bool(forKey: SettingsKeys.toggleShortcutEnabled)
        }
        if defaults.object(forKey: SettingsKeys.toggleShortcutKeyCode) != nil {
            let keyCode = UInt16(defaults.integer(forKey: SettingsKeys.toggleShortcutKeyCode))
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: SettingsKeys.toggleShortcutModifiers)))
            toggleShortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
        }
    }

    func saveProfile(forKey key: String, data: ProfileData) {
        let defaults = UserDefaults.standard
        var profiles = defaults.dictionary(forKey: SettingsKeys.profiles) as? [String: Data] ?? [:]

        if let encoded = try? JSONEncoder().encode(data) {
            profiles[key] = encoded
            defaults.set(profiles, forKey: SettingsKeys.profiles)
        }
    }

    func loadProfile(forKey key: String) -> ProfileData? {
        let defaults = UserDefaults.standard
        guard let profiles = defaults.dictionary(forKey: SettingsKeys.profiles) as? [String: Data],
              let data = profiles[key] else {
            return nil
        }

        return try? JSONDecoder().decode(ProfileData.self, from: data)
    }

    // MARK: - Display Configuration

    func getDisplayUUIDs() -> [String] {
        var uuids: [String] = []

        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }

            if let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber)?.takeRetainedValue() {
                let uuidString = CFUUIDCreateString(nil, uuid) as String
                uuids.append(uuidString)
            }
        }

        return uuids.sorted()
    }

    func getCurrentConfigKey() -> String {
        let displays = getDisplayUUIDs()
        return "displays:\(displays.joined(separator: "+"))"
    }

    func isLaptopOnlyConfiguration() -> Bool {
        let screens = NSScreen.screens
        if screens.count != 1 { return false }

        guard let screen = screens.first,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }

        return CGDisplayIsBuiltin(displayID) != 0
    }

    func registerDisplayChangeCallback() {
        let callback: CGDisplayReconfigurationCallBack = { displayID, flags, userInfo in
            guard let userInfo = userInfo else { return }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()

            if flags.contains(.beginConfigurationFlag) {
                return
            }

            appDelegate.scheduleDisplayConfigurationChange()
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(callback, userInfo)
    }

    func scheduleDisplayConfigurationChange() {
        DispatchQueue.main.async { [weak self] in
            self?.displayDebounceTimer?.invalidate()
            self?.displayDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.handleDisplayConfigurationChange()
            }
        }
    }

    func handleDisplayConfigurationChange() {
        rebuildOverlayWindows()

        guard state != .disabled else {
            return
        }

        if pauseOnTheGo && isLaptopOnlyConfiguration() {
            state = .paused(.onTheGo)
            return
        }

        let cameras = getAvailableCameras()
        let configKey = getCurrentConfigKey()
        let profile = loadProfile(forKey: configKey)


        if cameras.isEmpty {
            state = .paused(.cameraDisconnected)
            return
        }

        if let profile = profile,
           cameras.contains(where: { $0.uniqueID == profile.cameraID }) {
            if selectedCameraID != profile.cameraID {
                selectedCameraID = profile.cameraID
                switchCameraInput()
            }
            applyProfile(profile)
            state = .monitoring
        } else {
            state = .paused(.noProfile)
        }
    }

    // MARK: - AirPods Tracking

    func setupAirPodsTracking() {
        headphoneMotionManager.onUpdate = { [weak self] pitch, roll, yaw in
            guard let self = self else { return }
            
            if self.state == .calibrating {
                self.calibrationController?.updateCurrentMotion(pitch: pitch, roll: roll, yaw: yaw)
            } else if self.state == .monitoring, let profile = self.airPodsProfile {
                self.evaluateAirPodsPosture(pitch: pitch, profile: profile)
            }
        }
    }

    func evaluateAirPodsPosture(pitch: Double, profile: AirPodsProfile) {
        // Calculate signed difference (Current - Neutral)
        // Assumption: Looking Down decreases Pitch (Negative direction) based on reference logic
        let diff = pitch - profile.pitch
        
        // Threshold calculation: Base 0.15 rad (~8.5 deg) + scaled deadZone
        // deadZone (0.0-1.0) * 0.5 rad (~28 deg)
        let threshold = 0.15 + (deadZone * 0.5)
        
        // Only detect forward lean (negative diff exceeding threshold)
        // Leaning back (positive diff) is ignored (e.g. stretching)
        let isBadPosture = diff < -threshold
        
        // Severity
        var severity: Double = 0
        if isBadPosture {
             // How much past the threshold?
             // e.g. diff = -0.4, threshold = 0.15 => excess = |-0.4| - 0.15 = 0.25
             let excess = abs(diff) - threshold
             // Max out severity at +0.3 rad (~17 deg) past threshold
             severity = min(1.0, excess / 0.3)
        }
        
        processPostureState(isBad: isBadPosture, severity: severity)
    }

    // MARK: - Overlay Windows

    func setupOverlayWindows() {
        for screen in NSScreen.screens {
            let frame = screen.visibleFrame
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.hasShadow = false

            let blurView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
            blurView.blendingMode = .behindWindow
            blurView.material = .fullScreenUI
            blurView.state = .active
            blurView.alphaValue = 0

            window.contentView = blurView
            window.orderFrontRegardless()
            windows.append(window)
            blurViews.append(blurView)
        }
    }

    func rebuildOverlayWindows() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        blurViews.removeAll()
        setupOverlayWindows()

        if warningMode.usesWarningOverlay {
            warningOverlayManager.rebuildOverlayWindows()
        }
    }

    func clearBlur() {
        targetBlurRadius = 0
        currentBlurRadius = 0

        // Clear NSVisualEffectView alpha
        for blurView in blurViews {
            blurView.alphaValue = 0
        }

        #if !APP_STORE
        // Clear private API blur
        if let getConnectionID = cgsMainConnectionID,
           let setBlurRadius = cgsSetWindowBackgroundBlurRadius {
            let cid = getConnectionID()
            for window in windows {
                _ = setBlurRadius(cid, UInt32(window.windowNumber), 0)
            }
        }
        #endif
    }

    func switchWarningMode(to newMode: WarningMode) {
        // Reset current warning state
        clearBlur()

        // Clear vignette/border intensity before removing windows
        warningOverlayManager.currentIntensity = 0
        warningOverlayManager.targetIntensity = 0
        for view in warningOverlayManager.overlayViews {
            if let vignetteView = view as? VignetteOverlayView {
                vignetteView.intensity = 0
            } else if let borderView = view as? BorderOverlayView {
                borderView.intensity = 0
            }
        }

        // Remove old warning overlay windows
        for window in warningOverlayManager.windows {
            window.orderOut(nil)
        }
        warningOverlayManager.windows.removeAll()
        warningOverlayManager.overlayViews.removeAll()

        // Set new mode and rebuild if needed
        warningMode = newMode
        if warningMode.usesWarningOverlay {
            warningOverlayManager.mode = warningMode
            warningOverlayManager.warningColor = warningColor
            warningOverlayManager.setupOverlayWindows()
        }
    }

    func updateWarningColor(_ color: NSColor) {
        warningColor = color
        warningOverlayManager.updateColor(color)
    }

    func updateBlur() {
        // Two independent concerns:
        // 1. Privacy blur: full blur when away (always uses blur overlay)
        // 2. Posture warning: user's chosen style (blur/vignette/border/none)

        let privacyBlurIntensity: CGFloat = isCurrentlyAway ? 1.0 : 0.0

        // Compute target blur radius and warning overlay intensity based on mode
        switch warningMode {
        case .blur:
            // Both privacy and posture use blur - take the higher value
            let combinedIntensity = max(privacyBlurIntensity, postureWarningIntensity)
            targetBlurRadius = Int32(combinedIntensity * 64)
            warningOverlayManager.targetIntensity = 0
        case .none:
            // Only privacy blur, no posture warning visual
            targetBlurRadius = Int32(privacyBlurIntensity * 64)
            warningOverlayManager.targetIntensity = 0
        case .vignette, .border, .solid:
            // Privacy uses blur, posture uses vignette/border/solid overlay
            targetBlurRadius = Int32(privacyBlurIntensity * 64)
            warningOverlayManager.targetIntensity = postureWarningIntensity
        }
        warningOverlayManager.updateWarning()

        // Animate blur toward target
        if currentBlurRadius < targetBlurRadius {
            currentBlurRadius = min(currentBlurRadius + 1, targetBlurRadius)
        } else if currentBlurRadius > targetBlurRadius {
            currentBlurRadius = max(currentBlurRadius - 3, targetBlurRadius)
        }

        let normalizedBlur = CGFloat(currentBlurRadius) / 64.0
        let visualEffectAlpha = min(1.0, sqrt(normalizedBlur) * 1.2)

        #if APP_STORE
        for blurView in blurViews {
            blurView.alphaValue = visualEffectAlpha
        }
        #else
        if useCompatibilityMode {
            for blurView in blurViews {
                blurView.alphaValue = visualEffectAlpha
            }
        } else if let getConnectionID = cgsMainConnectionID,
                  let setBlurRadius = cgsSetWindowBackgroundBlurRadius {
            let cid = getConnectionID()
            for window in windows {
                _ = setBlurRadius(cid, UInt32(window.windowNumber), currentBlurRadius)
            }
        } else {
            for blurView in blurViews {
                blurView.alphaValue = visualEffectAlpha
            }
        }
        #endif
    }

    // MARK: - Posture Detection

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        let bodyRequest = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            if let results = request.results as? [VNHumanBodyPoseObservation], let body = results.first {
                self?.analyzeBodyPose(body)
            } else {
                self?.tryFaceDetection(pixelBuffer: pixelBuffer)
            }
        }

        do {
            try handler.perform([bodyRequest])
        } catch {
            tryFaceDetection(pixelBuffer: pixelBuffer)
        }
    }

    func analyzeBodyPose(_ body: VNHumanBodyPoseObservation) {
        guard let nose = try? body.recognizedPoint(.nose), nose.confidence > 0.3 else {
            return
        }

        consecutiveNoDetectionFrames = 0
        isCurrentlyAway = false

        let noseY = nose.location.y
        currentNoseY = noseY

        if state == .calibrating {
            calibrationController?.updateCurrentNoseY(noseY)
            return
        }

        guard state == .monitoring && isCalibrated else { return }

        evaluatePosture(currentY: noseY)
    }

    func tryFaceDetection(pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        let faceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            if let results = request.results as? [VNFaceObservation], let face = results.first {
                self?.analyzeFace(face)
            } else {
                self?.handleNoDetection()
            }
        }

        try? handler.perform([faceRequest])
    }

    func handleNoDetection() {
        consecutiveNoDetectionFrames += 1
        consecutiveBadFrames = 0
        consecutiveGoodFrames = 0

        guard state == .monitoring && isCalibrated && blurWhenAway else {
            consecutiveNoDetectionFrames = 0
            return
        }

        if consecutiveNoDetectionFrames >= awayFrameThreshold && !isCurrentlyAway {
            isCurrentlyAway = true

            DispatchQueue.main.async {
                self.statusMenuItem.title = "Status: Away"
                self.statusItem.button?.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "Away")
            }
        }
    }

    func analyzeFace(_ face: VNFaceObservation) {
        consecutiveNoDetectionFrames = 0
        isCurrentlyAway = false

        let faceY = face.boundingBox.midY
        currentNoseY = faceY

        if state == .calibrating {
            calibrationController?.updateCurrentNoseY(faceY)
            return
        }

        guard state == .monitoring && isCalibrated else { return }

        evaluatePosture(currentY: faceY)
    }

    func smoothNoseY(_ rawY: CGFloat) -> CGFloat {
        noseYHistory.append(rawY)

        if noseYHistory.count > smoothingWindow {
            noseYHistory.removeFirst()
        }

        let sum = noseYHistory.reduce(0, +)
        smoothedNoseY = sum / CGFloat(noseYHistory.count)
        return smoothedNoseY
    }

    func evaluatePosture(currentY: CGFloat) {
        let smoothedY = smoothNoseY(currentY)

        // How far past the bad posture threshold (positive = slouching)
        let slouchAmount = badPostureY - smoothedY

        // Dead zone is an absolute buffer (percentage of posture range)
        let deadZoneThreshold = deadZone * postureRange

        // Hysteresis: easier to exit slouching state than enter it
        let enterThreshold = deadZoneThreshold
        let exitThreshold = deadZoneThreshold * 0.7

        let threshold = isCurrentlySlouching ? exitThreshold : enterThreshold
        let isBadPosture = slouchAmount > threshold

        // Calculate severity: how far past the dead zone (0 to 1)
        let pastDeadZone = slouchAmount - deadZoneThreshold
        let remainingRange = max(0.01, postureRange - deadZoneThreshold)
        let severity = min(1.0, max(0.0, pastDeadZone / remainingRange))

        processPostureState(isBad: isBadPosture, severity: Double(severity))
    }

    func processPostureState(isBad: Bool, severity: Double) {
        // Track analytics
        AnalyticsManager.shared.trackTime(interval: frameInterval, isSlouching: isCurrentlySlouching)

        if isBad {
            consecutiveBadFrames += 1
            consecutiveGoodFrames = 0

            if consecutiveBadFrames >= frameThreshold {
                // Start tracking when bad posture began (if not already)
                if badPostureStartTime == nil {
                    badPostureStartTime = Date()
                }

                // Check if we've waited long enough for the blur onset delay
                let elapsedTime = Date().timeIntervalSince(badPostureStartTime!)
                guard elapsedTime >= warningOnsetDelay else {
                    // Still waiting for delay, don't activate blur yet
                    return
                }

                // Record slouch event only once when transitioning to slouching state
                if !isCurrentlySlouching {
                    AnalyticsManager.shared.recordSlouchEvent()
                }

                isCurrentlySlouching = true

                // Intensity controls the curve: higher = warning ramps up faster
                // pow(severity, 1/intensity): intensity 2.0 = aggressive, 0.5 = gentle
                let adjustedSeverity = pow(severity, 1.0 / intensity)

                postureWarningIntensity = adjustedSeverity

                DispatchQueue.main.async {
                    self.statusMenuItem.title = "Status: Slouching"
                    self.statusItem.button?.image = NSImage(systemSymbolName: "figure.fall", accessibilityDescription: "Bad Posture")
                }
            }
        } else {
            consecutiveGoodFrames += 1
            consecutiveBadFrames = 0

            // Reset the bad posture start time when posture improves
            badPostureStartTime = nil

            postureWarningIntensity = 0

            if consecutiveGoodFrames >= 5 { // Quick recovery
                isCurrentlySlouching = false
                DispatchQueue.main.async {
                    self.syncUIToState()
                }
            }
        }

        DispatchQueue.main.async {
            self.updateBlur()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension AppDelegate: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if waitingForPermission {
            DispatchQueue.main.async {
                self.onCameraPermissionGranted()
            }
        }

        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= frameInterval else { return }
        lastFrameTime = now

        processFrame(pixelBuffer)
    }
}
