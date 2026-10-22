import AppKit

// MARK: - Calibration View

enum CalibrationKeyAction: Equatable {
    case cancel
    case capture
    case toggleNewDesk
    case selectDesk(index: Int)
    case calibrateNewDesk
    case recalibrateCurrentDesk
    case moveFocus(by: Int)
    case activateFocused

    /// kVK_ANSI_1...9, so number keys work on layouts like AZERTY
    private static let numberRowKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// Keys typed into other apps only reach Space and Escape.
    static func forKey(
        keyCode: UInt16,
        characters: String?,
        modifiers: NSEvent.ModifierFlags,
        isRepeat: Bool,
        isFromDorso: Bool,
        isChoosingDesk: Bool,
        deskCount: Int
    ) -> CalibrationKeyAction? {
        if keyCode == 53 { return .cancel }  // Escape
        guard modifiers.intersection([.command, .option, .control]).isEmpty else { return nil }

        // Arrows may repeat
        if isChoosingDesk, isFromDorso {
            if keyCode == 126 { return .moveFocus(by: -1) }  // Up arrow
            if keyCode == 125 { return .moveFocus(by: 1) }  // Down arrow
        }
        guard !isRepeat else { return nil }

        // Physical N and R for non-Latin layouts
        var key = characters?.lowercased() ?? ""
        if !key.allSatisfy(\.isASCII) {
            if keyCode == 45 { key = "n" }
            if keyCode == 15 { key = "r" }
        }
        if isChoosingDesk {
            guard isFromDorso else { return nil }
            if keyCode == 36 || keyCode == 76 { return .activateFocused }  // Return, keypad Enter
            let number = Int(key) ?? numberRowKeyCodes.firstIndex(of: keyCode).map { $0 + 1 }
            if let number, number >= 1, number <= min(deskCount, 9) {
                return .selectDesk(index: number - 1)
            }
            if key == "n" { return .calibrateNewDesk }
            if key == "r" { return .recalibrateCurrentDesk }
            return nil
        }

        if keyCode == 49 { return .capture }  // Space
        if key == "n", deskCount > 0, isFromDorso { return .toggleNewDesk }
        return nil
    }
}

/// `key` is empty for desks past the ninth.
struct DeskPickerRow: Equatable {
    let key: String
    let title: String
    let action: CalibrationKeyAction
    var isCurrent = false
    var isSecondary = false
}

class CalibrationView: NSView {
    var targetPosition: NSPoint = .zero
    var pulsePhase: CGFloat = 0
    var instructionText: String = L("calibration.lookAtRing")
    var stepText: String = L("calibration.stepOf", 1, 4)
    var showRing: Bool = true
    var waitingForConnection: Bool = false
    var waitingSource: TrackingSource = .airpods
    var deskPickerRows: [DeskPickerRow]?
    var deskPickerTitle = L("calibration.desk.title")
    var deskPickerSubtitle = L("calibration.desk.subtitle")
    var onDeskPickerRowSelected: ((CalibrationKeyAction) -> Void)?
    var onDeskPickerRowHovered: ((Int) -> Void)?
    var focusedRowIndex: Int?
    private var deskPickerRowRects: [NSRect] = []
    private var hoveredRowIndex: Int?
    private static let accent = NSColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1)  // brandCyan
    var footerHint: String?
    private var keycapSegmentCache: [String: [(text: String, isKeycap: Bool)]] = [:]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Dark overlay
        NSColor.black.withAlphaComponent(0.85).setFill()
        dirtyRect.fill()

        if let deskPickerRows {
            drawDeskPicker(rows: deskPickerRows)
            return
        }

        // Show waiting state until the detector delivers data
        if waitingForConnection {
            drawWaitingForConnection()
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
            .paragraphStyle: paragraphStyle,
        ]

        let stepAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .paragraphStyle: paragraphStyle,
        ]

        // Draw step indicator at top center
        let stepRect = NSRect(x: 0, y: bounds.height - 100, width: bounds.width, height: 40)
        (stepText as NSString).draw(in: stepRect, withAttributes: stepAttrs)

        // Draw instruction in center
        let textRect = NSRect(x: 0, y: bounds.midY - 20, width: bounds.width, height: 50)
        (instructionText as NSString).draw(in: textRect, withAttributes: titleAttrs)

        // Draw hint with keycap for Space
        let hintY = bounds.midY - 70
        drawLocalizedHintWithKeycap(
            text: L("calibration.hint.tapSpace"),
            centerY: hintY,
            textColor: NSColor.cyan,
            fontSize: 18
        )

        // Draw escape hint with keycap for Esc
        let escapeY = bounds.midY - 110
        drawLocalizedHintWithKeycap(
            text: L("calibration.hint.escToSkip"),
            centerY: escapeY,
            textColor: NSColor.white.withAlphaComponent(0.5),
            fontSize: 14
        )

        if let footerHint {
            drawLocalizedHintWithKeycap(
                text: footerHint,
                centerY: bounds.midY - 170,
                textColor: NSColor.white.withAlphaComponent(0.5),
                fontSize: 14
            )
        }
    }

    // MARK: - Desk Picker

    private func drawDeskPicker(rows: [DeskPickerRow]) {
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()

        let cardWidth: CGFloat = 440
        let padding: CGFloat = 28
        let primaryRowHeight: CGFloat = 52
        let secondaryRowHeight: CGFloat = 42
        let rowSpacing: CGFloat = 6
        let dividerSpacing: CGFloat = 14

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let textWidth = cardWidth - padding * 2
        let textOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let title = deskPickerTitle as NSString
        let subtitle = deskPickerSubtitle as NSString
        let titleHeight = ceil(
            title.boundingRect(
                with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: textOptions,
                attributes: titleAttrs
            ).height)
        let subtitleHeight = ceil(
            subtitle.boundingRect(
                with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: textOptions,
                attributes: subtitleAttrs
            ).height)

        let hasDivider = rows.contains(where: \.isSecondary) && rows.contains(where: { !$0.isSecondary })
        var rowsHeight: CGFloat = 0
        for row in rows {
            rowsHeight += (row.isSecondary ? secondaryRowHeight : primaryRowHeight) + rowSpacing
        }
        rowsHeight -= rowSpacing
        if hasDivider { rowsHeight += dividerSpacing * 2 + 1 }

        let cardHeight = padding + titleHeight + 4 + subtitleHeight + 20 + rowsHeight + padding
        let card = NSRect(
            x: bounds.midX - cardWidth / 2,
            y: bounds.midY - cardHeight / 2,
            width: cardWidth,
            height: cardHeight
        )
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18)
        NSColor(white: 0.11, alpha: 0.97).setFill()
        cardPath.fill()
        NSColor.white.withAlphaComponent(0.1).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        // y grows upward
        var y = card.maxY - padding - titleHeight
        title.draw(
            with: NSRect(x: card.minX + padding, y: y, width: textWidth, height: titleHeight),
            options: textOptions,
            attributes: titleAttrs
        )
        y -= 4 + subtitleHeight
        subtitle.draw(
            with: NSRect(x: card.minX + padding, y: y, width: textWidth, height: subtitleHeight),
            options: textOptions,
            attributes: subtitleAttrs
        )
        y -= 20

        deskPickerRowRects = []
        var previousWasSecondary = false
        for (index, row) in rows.enumerated() {
            if row.isSecondary, !previousWasSecondary, hasDivider {
                y -= dividerSpacing
                NSColor.white.withAlphaComponent(0.08).setFill()
                NSRect(x: card.minX + padding, y: y - 1, width: cardWidth - padding * 2, height: 1).fill()
                y -= 1 + dividerSpacing
            }
            previousWasSecondary = row.isSecondary

            let height = row.isSecondary ? secondaryRowHeight : primaryRowHeight
            let rowRect = NSRect(x: card.minX + 16, y: y - height, width: cardWidth - 32, height: height)
            drawDeskPickerRow(row, in: rowRect, isFocused: focusedRowIndex == index)
            deskPickerRowRects.append(rowRect)
            y -= height + rowSpacing
        }

        drawLocalizedHintWithKeycap(
            text: L("calibration.desk.keysHint"),
            centerY: card.minY - 40,
            textColor: NSColor.white.withAlphaComponent(0.45),
            fontSize: 13
        )
    }

    private func drawDeskPickerRow(_ row: DeskPickerRow, in rect: NSRect, isFocused: Bool) {
        let accent = Self.accent
        let rowPath = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        if row.isCurrent {
            accent.withAlphaComponent(isFocused ? 0.2 : 0.13).setFill()
            rowPath.fill()
        } else if isFocused {
            NSColor.white.withAlphaComponent(0.07).setFill()
            rowPath.fill()
        }
        if isFocused {
            let ringPath = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
            accent.withAlphaComponent(0.95).setStroke()
            ringPath.lineWidth = 2
            ringPath.stroke()
        } else if row.isCurrent {
            accent.withAlphaComponent(0.4).setStroke()
            rowPath.lineWidth = 1
            rowPath.stroke()
        }

        let keycapColumnWidth: CGFloat = 28
        if !row.key.isEmpty {
            let keycapSize: CGFloat = row.isSecondary ? 24 : keycapColumnWidth
            let keycapRect = NSRect(
                x: rect.minX + 14 + (keycapColumnWidth - keycapSize) / 2,
                y: rect.midY - keycapSize / 2,
                width: keycapSize,
                height: keycapSize
            )
            let keycapPath = NSBezierPath(roundedRect: keycapRect, xRadius: 6, yRadius: 6)
            (row.isCurrent ? accent.withAlphaComponent(0.25) : NSColor.white.withAlphaComponent(0.1)).setFill()
            keycapPath.fill()
            (row.isCurrent ? accent.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.22)).setStroke()
            keycapPath.lineWidth = 1
            keycapPath.stroke()

            let keyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: row.isSecondary ? 12 : 14, weight: .semibold),
                .foregroundColor: row.isCurrent ? accent : NSColor.white.withAlphaComponent(0.85),
            ]
            let key = row.key as NSString
            let keySize = key.size(withAttributes: keyAttrs)
            key.draw(
                at: NSPoint(x: keycapRect.midX - keySize.width / 2, y: keycapRect.midY - keySize.height / 2),
                withAttributes: keyAttrs
            )
        }

        var titleMaxX = rect.maxX - 14
        if row.isCurrent {
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: accent,
            ]
            let badge = L("calibration.desk.current") as NSString
            let badgeSize = badge.size(withAttributes: badgeAttrs)
            let pill = NSRect(
                x: rect.maxX - 14 - badgeSize.width - 16,
                y: rect.midY - (badgeSize.height + 6) / 2,
                width: badgeSize.width + 16,
                height: badgeSize.height + 6
            )
            accent.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            badge.draw(at: NSPoint(x: pill.minX + 8, y: pill.minY + 3), withAttributes: badgeAttrs)
            titleMaxX = pill.minX - 10
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: row.isSecondary ? 14 : 17, weight: row.isSecondary ? .regular : .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(row.isSecondary ? 0.7 : 1),
            .paragraphStyle: paragraphStyle,
        ]
        let title = row.title as NSString
        let titleHeight = title.size(withAttributes: titleAttrs).height
        let titleX = rect.minX + 14 + keycapColumnWidth + 14
        title.draw(
            in: NSRect(x: titleX, y: rect.midY - titleHeight / 2, width: titleMaxX - titleX, height: titleHeight),
            withAttributes: titleAttrs
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        guard deskPickerRows != nil else { return }
        let index = deskPickerRowIndex(at: convert(event.locationInWindow, from: nil))
        if index != hoveredRowIndex {
            hoveredRowIndex = index
            (index == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
            if let index {
                onDeskPickerRowHovered?(index)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let rows = deskPickerRows,
            let index = deskPickerRowIndex(at: convert(event.locationInWindow, from: nil)),
            index < rows.count
        else { return }
        hoveredRowIndex = nil
        NSCursor.arrow.set()
        onDeskPickerRowSelected?(rows[index].action)
    }

    func resetDeskPickerHover() {
        hoveredRowIndex = nil
    }

    private func deskPickerRowIndex(at point: NSPoint) -> Int? {
        deskPickerRowRects.firstIndex(where: { $0.contains(point) })
    }

    private func drawLocalizedHintWithKeycap(text: String, centerY: CGFloat, textColor: NSColor, fontSize: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let keycapFont = NSFont.systemFont(ofSize: fontSize - 1, weight: .semibold)

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let keycapTextAttrs: [NSAttributedString.Key: Any] = [
            .font: keycapFont,
            .foregroundColor: NSColor.white,
        ]

        let keycapPaddingH: CGFloat = 8
        let keycapPaddingV: CGFloat = 4

        let segments = keycapSegments(for: text)

        // Calculate total width
        var totalWidth: CGFloat = 0
        for segment in segments {
            if segment.isKeycap {
                let keycapTextSize = (segment.text as NSString).size(withAttributes: keycapTextAttrs)
                totalWidth += keycapTextSize.width + keycapPaddingH * 2
            } else {
                totalWidth += (segment.text as NSString).size(withAttributes: textAttrs).width
            }
        }

        var currentX = (bounds.width - totalWidth) / 2

        for segment in segments {
            if segment.isKeycap {
                let keycapTextSize = (segment.text as NSString).size(withAttributes: keycapTextAttrs)
                let keycapWidth = keycapTextSize.width + keycapPaddingH * 2
                let keycapHeight = keycapTextSize.height + keycapPaddingV * 2

                let keycapRect = NSRect(
                    x: currentX,
                    y: centerY - keycapPaddingV,
                    width: keycapWidth,
                    height: keycapHeight
                )
                let keycapPath = NSBezierPath(roundedRect: keycapRect, xRadius: 5, yRadius: 5)

                NSColor.white.withAlphaComponent(0.15).setFill()
                keycapPath.fill()
                NSColor.white.withAlphaComponent(0.3).setStroke()
                keycapPath.lineWidth = 1
                keycapPath.stroke()

                let keycapTextY = keycapRect.minY + (keycapRect.height - keycapTextSize.height) / 2
                (segment.text as NSString).draw(
                    at: NSPoint(x: currentX + keycapPaddingH, y: keycapTextY), withAttributes: keycapTextAttrs)
                currentX += keycapWidth
            } else {
                (segment.text as NSString).draw(at: NSPoint(x: currentX, y: centerY), withAttributes: textAttrs)
                currentX += (segment.text as NSString).size(withAttributes: textAttrs).width
            }
        }
    }

    private func keycapSegments(for text: String) -> [(text: String, isKeycap: Bool)] {
        if let cached = keycapSegmentCache[text] {
            return cached
        }

        var segments: [(text: String, isKeycap: Bool)] = []
        var remaining = text
        while let openBrace = remaining.range(of: "{") {
            let prefix = String(remaining[..<openBrace.lowerBound])
            if !prefix.isEmpty {
                segments.append((prefix, false))
            }
            remaining = String(remaining[openBrace.upperBound...])
            if let closeBrace = remaining.range(of: "}") {
                let keycap = String(remaining[..<closeBrace.lowerBound])
                segments.append((keycap, true))
                remaining = String(remaining[closeBrace.upperBound...])
            } else {
                segments.append(("{\(remaining)", false))
                remaining = ""
                break
            }
        }
        if !remaining.isEmpty {
            segments.append((remaining, false))
        }

        keycapSegmentCache[text] = segments
        return segments
    }

    private func drawWaitingForConnection() {
        let icon = waitingSource == .airpods ? "🎧" : "📷"
        let title = waitingSource == .airpods ? L("calibration.airpods.putIn") : L("calibration.camera.waiting")
        let subtitle = L("calibration.airpods.autoBegin")

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        // Draw pulsing source icon
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .light),
            .foregroundColor: NSColor.cyan.withAlphaComponent(0.7 + 0.3 * sin(pulsePhase)),
            .paragraphStyle: paragraphStyle,
        ]
        let iconRect = NSRect(x: 0, y: bounds.midY + 20, width: bounds.width, height: 90)
        (icon as NSString).draw(in: iconRect, withAttributes: iconAttrs)

        // Main instruction
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        let titleRect = NSRect(x: 0, y: bounds.midY - 30, width: bounds.width, height: 45)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

        // Subtitle
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .paragraphStyle: paragraphStyle,
        ]
        let subtitleRect = NSRect(x: 0, y: bounds.midY - 70, width: bounds.width, height: 30)
        (subtitle as NSString).draw(in: subtitleRect, withAttributes: subtitleAttrs)

        // Escape hint (keycap style)
        drawLocalizedHintWithKeycap(
            text: L("calibration.airpods.escToCancel"),
            centerY: bounds.midY - 120,
            textColor: NSColor.white.withAlphaComponent(0.5),
            fontSize: 14
        )
    }
}

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
    private(set) var isChoosingDesk = false
    private(set) var saveAsNewDesk = false
    private var deskPickerRows: [DeskPickerRow] = []
    private var focusedRowIndex = 0

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

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent, isFromDorso: Bool) -> Bool {
        guard
            let action = CalibrationKeyAction.forKey(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers,
                modifiers: event.modifierFlags,
                isRepeat: event.isARepeat,
                isFromDorso: isFromDorso,
                isChoosingDesk: isChoosingDesk,
                deskCount: desks.count
            )
        else { return false }
        perform(action)
        return true
    }

    private func perform(_ action: CalibrationKeyAction) {
        switch action {
        case .cancel:
            cancel()
        case .capture:
            captureCurrentPosition()
        case .toggleNewDesk:
            saveAsNewDesk.toggle()
            updateFooterHint()
        case .selectDesk(let index):
            guard isChoosingDesk, desks.indices.contains(index) else { return }
            let desk = desks[index]
            cleanup()
            onSelectDesk?(desk.id)
        case .calibrateNewDesk:
            guard isChoosingDesk else { return }
            beginCalibration(asNewDesk: true)
        case .recalibrateCurrentDesk:
            guard isChoosingDesk else { return }
            beginCalibration(asNewDesk: false)
        case .moveFocus(let delta):
            guard isChoosingDesk else { return }
            calibrationViews.forEach { $0.resetDeskPickerHover() }
            setFocusedRow(Self.movedFocus(from: focusedRowIndex, by: delta, rowCount: deskPickerRows.count))
        case .activateFocused:
            guard isChoosingDesk, deskPickerRows.indices.contains(focusedRowIndex) else { return }
            perform(deskPickerRows[focusedRowIndex].action)
        }
    }

    // MARK: - Desk Choice

    private func showDeskPicker() {
        isChoosingDesk = true
        var rows: [DeskPickerRow] = []
        for (index, desk) in desks.enumerated() {
            let key = index < 9 ? "\(index + 1)" : ""
            rows.append(
                DeskPickerRow(key: key, title: desk.name, action: .selectDesk(index: index), isCurrent: desk.isActive))
        }
        rows.append(
            DeskPickerRow(key: "N", title: L("calibration.desk.new"), action: .calibrateNewDesk, isSecondary: true))
        rows.append(
            DeskPickerRow(
                key: "R", title: L("calibration.desk.recalibrate"), action: .recalibrateCurrentDesk, isSecondary: true))
        deskPickerRows = rows
        focusedRowIndex = rows.firstIndex(where: \.isCurrent) ?? 0
        for view in calibrationViews {
            view.deskPickerRows = rows
            view.focusedRowIndex = focusedRowIndex
            view.onDeskPickerRowSelected = { [weak self] action in
                self?.perform(action)
            }
            view.onDeskPickerRowHovered = { [weak self] index in
                self?.setFocusedRow(index)
            }
            view.showRing = false
            view.needsDisplay = true
        }
    }

    private func setFocusedRow(_ index: Int) {
        guard index != focusedRowIndex else { return }
        focusedRowIndex = index
        for view in calibrationViews {
            view.focusedRowIndex = index
            view.needsDisplay = true
        }
    }

    private func beginCalibration(asNewDesk: Bool) {
        isChoosingDesk = false
        saveAsNewDesk = asNewDesk
        for view in calibrationViews {
            view.deskPickerRows = nil
        }
        checkDetectorAndProceed()
    }

    private func updateFooterHint() {
        // With the picker, the choice was made up front
        let hint: String?
        if desks.count == 1 {
            hint = saveAsNewDesk ? L("calibration.desk.hint.newSelected") : L("calibration.desk.hint.new")
        } else if saveAsNewDesk {
            hint = L("calibration.desk.hint.newSelected")
        } else {
            hint = nil
        }
        for view in calibrationViews {
            view.footerHint = hint
            view.needsDisplay = true
        }
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

    private func checkDetectorAndProceed() {
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
