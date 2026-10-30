import AppKit
import CoreText

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
    var deskPickerRowRects: [NSRect] = []
    var hoveredRowIndex: Int?
    static let accent = NSColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1)  // brandCyan
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

        if showRing {
            drawRing()
        }
        drawInstructions()
    }

    private func drawRing() {
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

    private func drawInstructions() {
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

    func drawLocalizedHintWithKeycap(text: String, centerY: CGFloat, textColor: NSColor, fontSize: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let keycapFont = NSFont.systemFont(ofSize: fontSize - 1, weight: .semibold)
        let rightToLeft = KeycapHintLayout.direction(of: text) == .rightToLeft
        let textAttrs = hintTextAttributes(font: font, color: textColor, rightToLeft: rightToLeft)
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
                totalWidth += hintTextLayout(segment.text, attributes: textAttrs, rightToLeft: rightToLeft).width
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
                let textLayout = hintTextLayout(segment.text, attributes: textAttrs, rightToLeft: rightToLeft)
                (segment.text as NSString).draw(
                    at: NSPoint(x: currentX + textLayout.drawOffset, y: centerY), withAttributes: textAttrs)
                currentX += textLayout.width
            }
        }
    }

    private func hintTextAttributes(
        font: NSFont, color: NSColor, rightToLeft: Bool
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        guard rightToLeft else { return attributes }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.baseWritingDirection = .rightToLeft
        attributes[.paragraphStyle] = paragraphStyle
        return attributes
    }

    /// Width to advance, and how far right of `currentX` to draw.
    /// An RTL line's logical trailing whitespace is placed left of the Core Text origin, so the draw
    /// shifts by that width and the gap stays inside the segment, beside the keycap on its left.
    private func hintTextLayout(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        rightToLeft: Bool
    ) -> (width: CGFloat, drawOffset: CGFloat) {
        guard rightToLeft else {
            return ((text as NSString).size(withAttributes: attributes).width, 0)
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let drawOffset = CGFloat(CTLineGetTrailingWhitespaceWidth(line))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return (width, drawOffset)
    }

    private func keycapSegments(for text: String) -> [(text: String, isKeycap: Bool)] {
        if let cached = keycapSegmentCache[text] {
            return cached
        }
        let segments = KeycapHintLayout.visualSegments(in: text)
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
