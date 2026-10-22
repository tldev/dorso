import AppKit

// MARK: - Calibration Window Controller

@MainActor
class CalibrationWindowController: NSObject {
    var windows: [NSWindow] = []
    var calibrationViews: [CalibrationView] = []
    var animationTimer: Timer?
    var currentStep = 0
    var onComplete: (([CalibrationSample], _ saveAsNewDesk: Bool) -> Void)?
    var onSelectDesk: ((String) -> Void)?
    var onCancel: (() -> Void)?

    struct DeskChoice: Equatable {
        let id: String
        let name: String
        let isActive: Bool
    }

    private(set) var desks: [DeskChoice] = []
    var isChoosingDesk = false
    var saveAsNewDesk = false
    var deskPickerRows: [DeskPickerRow] = []
    var focusedRowIndex = 0

    static func movedFocus(from index: Int, by delta: Int, rowCount: Int) -> Int {
        guard rowCount > 0 else { return 0 }
        return min(max(index + delta, 0), rowCount - 1)
    }
    var capturedValues: [CalibrationSample] = []

    var localEventMonitor: Any?
    var globalEventMonitor: Any?

    // The detector being used for calibration
    weak var detector: PostureDetector?

    // Waiting for detector connection (AirPods in ears, or camera's first frame)
    var isWaitingForConnection: Bool = false

    // Store the original connection callback to restore later
    var originalConnectionCallback: ((Bool) -> Void)?

    // Activation policy the app had before calibration started. Calibration
    // forces .accessory because the overlay-above-fullscreen recipe only
    // behaves reliably when Dorso isn't a .regular app.
    private var activationPolicyToRestore: NSApplication.ActivationPolicy?

    struct CalibrationStep {
        let instruction: String
        let screenIndex: Int
        let corner: Corner
    }

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight

        func position(in bounds: NSRect, margin: CGFloat = 120) -> NSPoint {
            switch self {
            case .topLeft:
                return NSPoint(x: margin, y: bounds.height - margin)
            case .topRight:
                return NSPoint(x: bounds.width - margin, y: bounds.height - margin)
            case .bottomLeft:
                return NSPoint(x: margin, y: margin)
            case .bottomRight:
                return NSPoint(x: bounds.width - margin, y: margin)
            }
        }

        var name: String {
            switch self {
            case .topLeft: return L("calibration.corner.topLeft")
            case .topRight: return L("calibration.corner.topRight")
            case .bottomLeft: return L("calibration.corner.bottomLeft")
            case .bottomRight: return L("calibration.corner.bottomRight")
            }
        }
    }

    var steps: [CalibrationStep] = []

    func buildSteps() {
        steps = []
        let corners: [Corner] = [.topLeft, .topRight, .bottomRight, .bottomLeft]

        for screenIndex in 0..<NSScreen.screens.count {
            for corner in corners {
                steps.append(
                    CalibrationStep(
                        instruction: L("calibration.lookAtCorner", corner.name),
                        screenIndex: screenIndex,
                        corner: corner
                    ))
            }
        }
    }

    func start(
        detector: PostureDetector,
        desks: [DeskChoice] = [],
        onComplete: @escaping ([CalibrationSample], _ saveAsNewDesk: Bool) -> Void,
        onSelectDesk: @escaping (String) -> Void = { _ in },
        onCancel: @escaping () -> Void
    ) {
        // Guard against reentrant start() before cleanup() has run: re-capturing
        // `originalConnectionCallback` would snapshot a previously-wrapped
        // callback as the "original," and cleanup would then restore the
        // wrapper permanently.
        guard windows.isEmpty else { return }

        self.detector = detector
        self.onComplete = onComplete
        self.onSelectDesk = onSelectDesk
        self.onCancel = onCancel
        self.currentStep = 0
        self.capturedValues = []
        self.desks = desks
        self.saveAsNewDesk = false

        // Force .accessory so calibration windows overlay cleanly above a
        // fullscreen app on the current Space. Onboarding and Settings both
        // flip Dorso to .regular, and if we launched calibration while still
        // .regular the overlay could land behind the fullscreen window.
        let currentPolicy = NSApp.activationPolicy()
        if currentPolicy != .accessory {
            activationPolicyToRestore = currentPolicy
            NSApp.setActivationPolicy(.accessory)
        }

        buildSteps()

        // Create calibration window for each screen
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .aboveFullscreen
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let view = CalibrationView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.showRing = false  // Hide by default
            window.contentView = view

            windows.append(window)
            calibrationViews.append(view)
        }

        // Setup keyboard monitoring (both local and global)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event, isFromDorso: true) ? nil : event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKey(event, isFromDorso: false)
        }

        // Activate first so subsequent ordering happens while Dorso is frontmost.
        NSApp.activate(ignoringOtherApps: true)

        // Re-asserting .level refreshes the window-server layer; pairing it with
        // orderFrontRegardless anchors the window on the active Space (including
        // a fullscreen Space). Make the first window key last, so the key state
        // doesn't precede the ordering we just set.
        for window in windows {
            window.level = .aboveFullscreen
            window.orderFrontRegardless()
        }
        windows.first?.makeKeyAndOrderFront(nil)

        // Check if detector needs to wait for connection (e.g., AirPods in ears)
        // Save the original callback to restore later
        originalConnectionCallback = detector.onConnectionStateChange

        if desks.count >= 2 {
            showDeskPicker()
        } else {
            checkDetectorAndProceed()
        }

        startAnimation()
    }

    func showWaitingForConnection() {
        for view in calibrationViews {
            view.waitingForConnection = true
            view.waitingSource = detector?.trackingSource ?? .airpods
            view.showRing = false
            view.needsDisplay = true
        }
    }

    func detectorConnected() {
        isWaitingForConnection = false

        NSApp.activate(ignoringOtherApps: true)
        for window in windows {
            window.level = .aboveFullscreen
            window.orderFrontRegardless()
        }

        for view in calibrationViews {
            view.waitingForConnection = false
            view.needsDisplay = true
        }
        updateStep()
    }

    func checkDetectorAndProceed() {
        guard let detector else { return }
        if !detector.isConnected {
            isWaitingForConnection = true
            for window in windows {
                // Yield to system dialogs (e.g., Bluetooth pairing / "put AirPods
                // in ear") that open at higher levels. Restored to .aboveFullscreen
                // once the detector reports connected.
                window.level = .floating
            }
            showWaitingForConnection()

            detector.onConnectionStateChange = { [weak self] isConnected in
                if isConnected {
                    self?.detectorConnected()
                }
                self?.originalConnectionCallback?(isConnected)
            }
        } else {
            updateStep()
        }
        updateFooterHint()
    }

    func updateStep() {
        guard currentStep < steps.count else {
            complete()
            return
        }

        let step = steps[currentStep]

        // Update all views
        for (index, view) in calibrationViews.enumerated() {
            if index == step.screenIndex {
                view.showRing = true
                view.targetPosition = step.corner.position(in: view.bounds)
                view.instructionText = step.instruction
                view.stepText = L("calibration.stepOf", currentStep + 1, steps.count)
            } else {
                view.showRing = false
                view.instructionText = L("calibration.lookOtherScreen")
                view.stepText = L("calibration.stepOf", currentStep + 1, steps.count)
            }
            view.needsDisplay = true
        }
    }

    func startAnimation() {
        // Respect accessibility reduce motion preference
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                for view in self.calibrationViews {
                    if !reduceMotion {
                        view.pulsePhase += 0.08
                    }
                    view.needsDisplay = true
                }
            }
        }
    }

    func captureCurrentPosition() {
        // Don't capture while waiting for detector connection
        guard !isWaitingForConnection, !isChoosingDesk else { return }

        // Get current calibration value from the detector
        if let detector {
            capturedValues.append(detector.getCurrentCalibrationValue())
        }

        currentStep += 1
        updateStep()
    }

    func complete() {
        cleanup()
        onComplete?(capturedValues, saveAsNewDesk)
    }

    func cancel() {
        cleanup()
        onCancel?()
    }

    func cleanup() {
        animationTimer?.invalidate()
        animationTimer = nil

        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }

        // Restore original connection callback
        detector?.onConnectionStateChange = originalConnectionCallback
        originalConnectionCallback = nil

        for window in windows {
            window.orderOut(nil)
        }
        windows = []
        calibrationViews = []
        NSCursor.arrow.set()

        if let policy = activationPolicyToRestore {
            NSApp.setActivationPolicy(policy)
            activationPolicyToRestore = nil
            // The window that had flipped the app to .regular may have closed
            // during calibration; drop back to .accessory if nothing visible
            // still needs .regular.
            (NSApp.delegate as? AppDelegate)?.restoreAccessoryActivationPolicyIfNeeded()
        }
    }
}
