import AppKit

// MARK: - Calibration View

class CalibrationView: NSView {
    var targetPosition: NSPoint = .zero
    var pulsePhase: CGFloat = 0
    var instructionText: String = "Look at the ring and press Space"
    var stepText: String = "Step 1 of 4"
    var hintText: String = "Move your head naturally \u{2022} Press Space when ready"
    var showRing: Bool = true
    var waitingForAirPods: Bool = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Dark overlay
        NSColor.black.withAlphaComponent(0.85).setFill()
        dirtyRect.fill()

        // Show AirPods waiting state
        if waitingForAirPods {
            drawWaitingForAirPods()
            return
        }

        // Pulsing ring (only if this screen should show it)
        if showRing {
            let baseRadius: CGFloat = 50
            let pulseAmount: CGFloat = 15
            let radius = baseRadius + sin(pulsePhase) * pulseAmount

            let ringRect = NSRect(
                x: targetPosition.x - radius,
                y: targetPosition.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            // Outer glow
            let glowColor = NSColor.cyan.withAlphaComponent(0.3 + 0.2 * sin(pulsePhase))
            glowColor.setFill()
            let glowRect = ringRect.insetBy(dx: -25, dy: -25)
            NSBezierPath(ovalIn: glowRect).fill()

            // Main ring
            let ringPath = NSBezierPath(ovalIn: ringRect)
            NSColor.cyan.withAlphaComponent(0.9).setStroke()
            ringPath.lineWidth = 5
            ringPath.stroke()

            // Inner dot
            let dotRect = NSRect(
                x: targetPosition.x - 10,
                y: targetPosition.y - 10,
                width: 20,
                height: 20
            )
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        // Instructions
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let stepAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .paragraphStyle: paragraphStyle
        ]

        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.cyan,
            .paragraphStyle: paragraphStyle
        ]

        // Draw step indicator at top center
        let stepRect = NSRect(x: 0, y: bounds.height - 100, width: bounds.width, height: 40)
        (stepText as NSString).draw(in: stepRect, withAttributes: stepAttrs)

        // Draw instruction in center
        let textRect = NSRect(x: 0, y: bounds.midY - 20, width: bounds.width, height: 50)
        (instructionText as NSString).draw(in: textRect, withAttributes: titleAttrs)

        // Draw hint below
        let hintRect = NSRect(x: 0, y: bounds.midY - 70, width: bounds.width, height: 30)
        (hintText as NSString).draw(in: hintRect, withAttributes: hintAttrs)

        // Draw escape hint smaller
        let escapeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
            .paragraphStyle: paragraphStyle
        ]
        let escapeRect = NSRect(x: 0, y: bounds.midY - 110, width: bounds.width, height: 25)
        ("Escape to skip calibration" as NSString).draw(in: escapeRect, withAttributes: escapeAttrs)
    }

    private func drawWaitingForAirPods() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        // Draw pulsing AirPods icon (using SF Symbol or text)
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .light),
            .foregroundColor: NSColor.cyan.withAlphaComponent(0.7 + 0.3 * sin(pulsePhase)),
            .paragraphStyle: paragraphStyle
        ]
        let iconRect = NSRect(x: 0, y: bounds.midY + 20, width: bounds.width, height: 90)
        ("🎧" as NSString).draw(in: iconRect, withAttributes: iconAttrs)

        // Main instruction
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let titleRect = NSRect(x: 0, y: bounds.midY - 30, width: bounds.width, height: 45)
        ("Put in your AirPods" as NSString).draw(in: titleRect, withAttributes: titleAttrs)

        // Subtitle
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .paragraphStyle: paragraphStyle
        ]
        let subtitleRect = NSRect(x: 0, y: bounds.midY - 70, width: bounds.width, height: 30)
        ("Calibration will begin automatically" as NSString).draw(in: subtitleRect, withAttributes: subtitleAttrs)

        // Escape hint
        let escapeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
            .paragraphStyle: paragraphStyle
        ]
        let escapeRect = NSRect(x: 0, y: bounds.midY - 120, width: bounds.width, height: 25)
        ("Press Escape to cancel" as NSString).draw(in: escapeRect, withAttributes: escapeAttrs)
    }
}

// MARK: - Calibration Window Controller

class CalibrationWindowController: NSObject {
    var windows: [NSWindow] = []
    var calibrationViews: [CalibrationView] = []
    var animationTimer: Timer?
    var currentStep = 0
    var onComplete: (([Any]) -> Void)?
    var onCancel: (() -> Void)?
    var capturedValues: [Any] = []

    var localEventMonitor: Any?
    var globalEventMonitor: Any?

    // The detector being used for calibration
    weak var detector: PostureDetector?

    // Waiting for detector connection (e.g., AirPods in ears)
    var isWaitingForConnection: Bool = false

    // Store the original connection callback to restore later
    var originalConnectionCallback: ((Bool) -> Void)?

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
            case .topLeft: return "TOP-LEFT"
            case .topRight: return "TOP-RIGHT"
            case .bottomLeft: return "BOTTOM-LEFT"
            case .bottomRight: return "BOTTOM-RIGHT"
            }
        }
    }

    var steps: [CalibrationStep] = []

    func buildSteps() {
        steps = []
        let corners: [Corner] = [.topLeft, .topRight, .bottomRight, .bottomLeft]

        for screenIndex in 0..<NSScreen.screens.count {
            let screenName = NSScreen.screens.count > 1 ? "Screen \(screenIndex + 1) " : ""
            for corner in corners {
                steps.append(CalibrationStep(
                    instruction: "Look at the \(screenName)\(corner.name) corner",
                    screenIndex: screenIndex,
                    corner: corner
                ))
            }
        }
    }

    func start(detector: PostureDetector, onComplete: @escaping ([Any]) -> Void, onCancel: @escaping () -> Void) {
        self.detector = detector
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.currentStep = 0
        self.capturedValues = []

        buildSteps()

        // Create calibration window for each screen
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver + 1
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let view = CalibrationView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.showRing = false  // Hide by default
            window.contentView = view

            window.orderFrontRegardless()
            windows.append(window)
            calibrationViews.append(view)
        }

        // Setup keyboard monitoring (both local and global)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 49 { // Space
                self?.captureCurrentPosition()
                return nil
            } else if event.keyCode == 53 { // Escape
                self?.cancel()
                return nil
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 49 { // Space
                self?.captureCurrentPosition()
            } else if event.keyCode == 53 { // Escape
                self?.cancel()
            }
        }

        if let firstWindow = windows.first {
            firstWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)

        // Check if detector needs to wait for connection (e.g., AirPods in ears)
        // Save the original callback to restore later
        originalConnectionCallback = detector.onConnectionStateChange

        if !detector.isConnected {
            // Show waiting state with lower window level so permission dialogs appear on top
            isWaitingForConnection = true
            for window in windows {
                window.level = .floating  // Lower level allows system dialogs on top
            }
            showWaitingForConnection()

            // Subscribe to connection state changes (wrapping the original callback)
            detector.onConnectionStateChange = { [weak self] isConnected in
                // Call our handler for calibration
                if isConnected {
                    self?.detectorConnected()
                }
                // Also call the original callback so AppDelegate stays in sync
                self?.originalConnectionCallback?(isConnected)
            }
        } else {
            // Already connected and authorized - proceed with calibration
            updateStep()
        }

        startAnimation()
    }

    func showWaitingForConnection() {
        for view in calibrationViews {
            view.waitingForAirPods = true  // View still uses this name for the UI state
            view.showRing = false
            view.needsDisplay = true
        }
    }

    func detectorConnected() {
        isWaitingForConnection = false

        // Raise window level back to full screen calibration level
        for window in windows {
            window.level = .screenSaver + 1
        }
        NSApp.activate(ignoringOtherApps: true)

        for view in calibrationViews {
            view.waitingForAirPods = false  // View still uses this name for the UI state
            view.needsDisplay = true
        }
        updateStep()
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
                view.stepText = "Step \(currentStep + 1) of \(steps.count)"
            } else {
                view.showRing = false
                view.instructionText = "Look at the other screen"
                view.stepText = "Step \(currentStep + 1) of \(steps.count)"
            }
            view.needsDisplay = true
        }
    }

    func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            for view in self?.calibrationViews ?? [] {
                view.pulsePhase += 0.08
                view.needsDisplay = true
            }
        }
    }

    func captureCurrentPosition() {
        // Don't capture while waiting for detector connection
        guard !isWaitingForConnection else { return }

        // Get current calibration value from the detector
        if let value = detector?.getCurrentCalibrationValue() {
            capturedValues.append(value)
        }

        currentStep += 1
        updateStep()
    }

    func complete() {
        cleanup()
        onComplete?(capturedValues)
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
    }
}
