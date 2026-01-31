import AppKit

// MARK: - Calibration View

class CalibrationView: NSView {
    var targetPosition: NSPoint = .zero
    var pulsePhase: CGFloat = 0
    var instructionText: String = "Look at the ring and press Space"
    var stepText: String = "Step 1 of 4"
    var showRing: Bool = true

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Dark overlay
        NSColor.black.withAlphaComponent(0.85).setFill()
        dirtyRect.fill()

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
        ("Move your head naturally • Press Space when ready" as NSString).draw(in: hintRect, withAttributes: hintAttrs)

        // Draw escape hint smaller
        let escapeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
            .paragraphStyle: paragraphStyle
        ]
        let escapeRect = NSRect(x: 0, y: bounds.midY - 110, width: bounds.width, height: 25)
        ("Escape to skip calibration" as NSString).draw(in: escapeRect, withAttributes: escapeAttrs)
    }
}

// MARK: - Calibration Window Controller

class CalibrationWindowController: NSObject {
    var windows: [NSWindow] = []
    var calibrationViews: [CalibrationView] = []
    var animationTimer: Timer?
    var currentStep = 0
    var onComplete: (([CGFloat], [(Double, Double, Double)]) -> Void)?
    var onCancel: (() -> Void)?
    var capturedValues: [CGFloat] = []
    var capturedMotions: [(Double, Double, Double)] = []
    
    var currentNoseY: CGFloat = 0.5
    var currentPitch: Double = 0.0
    var currentRoll: Double = 0.0
    var currentYaw: Double = 0.0
    
    var localEventMonitor: Any?
    var globalEventMonitor: Any?
    var trackingSource: TrackingSource = .camera

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
        // Always use 4-corner calibration for consistency
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

    func start(trackingSource: TrackingSource, onComplete: @escaping ([CGFloat], [(Double, Double, Double)]) -> Void, onCancel: @escaping () -> Void) {
        self.trackingSource = trackingSource
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.currentStep = 0
        self.capturedValues = []
        self.capturedMotions = []

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

        updateStep()
        startAnimation()
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
                // Show ring for both Camera and AirPods modes
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
        if trackingSource == .camera {
            capturedValues.append(currentNoseY)
        } else {
            capturedValues.append(0.0) // Dummy
        }
        
        // Always capture motion (useful for AirPods)
        capturedMotions.append((currentPitch, currentRoll, currentYaw))
        
        currentStep += 1
        updateStep()
    }

    func updateCurrentNoseY(_ value: CGFloat) {
        currentNoseY = value
    }
    
    func updateCurrentMotion(pitch: Double, roll: Double, yaw: Double) {
        currentPitch = pitch
        currentRoll = roll
        currentYaw = yaw
    }

    func complete() {
        cleanup()
        onComplete?(capturedValues, capturedMotions)
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

        for window in windows {
            window.orderOut(nil)
        }
        windows = []
        calibrationViews = []
    }
}
