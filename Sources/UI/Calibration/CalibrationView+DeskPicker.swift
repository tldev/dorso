import AppKit

private enum DeskPickerLayout {
    static let cardWidth: CGFloat = 440
    static let padding: CGFloat = 28
    static let primaryRowHeight: CGFloat = 52
    static let secondaryRowHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 6
    static let dividerSpacing: CGFloat = 14
    static let titleGap: CGFloat = 4
    static let headerGap: CGFloat = 20
    static let keycapColumnWidth: CGFloat = 28
    static let textOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
    static var textWidth: CGFloat { cardWidth - padding * 2 }

    static let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]
    static let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.6),
    ]

    static func rowHeight(_ row: DeskPickerRow) -> CGFloat {
        row.isSecondary ? secondaryRowHeight : primaryRowHeight
    }

    static func hasDivider(_ rows: [DeskPickerRow]) -> Bool {
        rows.contains(where: \.isSecondary) && rows.contains(where: { !$0.isSecondary })
    }

    static func rowsHeight(_ rows: [DeskPickerRow]) -> CGFloat {
        let rowsAndSpacing = rows.reduce(0) { $0 + rowHeight($1) + rowSpacing } - rowSpacing
        return rowsAndSpacing + (hasDivider(rows) ? dividerSpacing * 2 + 1 : 0)
    }

    static func height(of text: NSString, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let size = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        return ceil(text.boundingRect(with: size, options: textOptions, attributes: attributes).height)
    }
}

extension CalibrationView {
    // MARK: - Desk Picker

    func drawDeskPicker(rows: [DeskPickerRow]) {
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()

        let title = deskPickerTitle as NSString
        let subtitle = deskPickerSubtitle as NSString
        let titleHeight = DeskPickerLayout.height(of: title, attributes: DeskPickerLayout.titleAttributes)
        let subtitleHeight = DeskPickerLayout.height(of: subtitle, attributes: DeskPickerLayout.subtitleAttributes)
        let headerHeight = titleHeight + DeskPickerLayout.titleGap + subtitleHeight + DeskPickerLayout.headerGap
        let cardHeight = DeskPickerLayout.padding * 2 + headerHeight + DeskPickerLayout.rowsHeight(rows)
        let card = NSRect(
            x: bounds.midX - DeskPickerLayout.cardWidth / 2,
            y: bounds.midY - cardHeight / 2,
            width: DeskPickerLayout.cardWidth,
            height: cardHeight
        )
        drawCard(card)

        // y grows upward
        var y = card.maxY - DeskPickerLayout.padding - titleHeight
        drawText(title, at: y, in: card, height: titleHeight, attributes: DeskPickerLayout.titleAttributes)
        y -= DeskPickerLayout.titleGap + subtitleHeight
        drawText(subtitle, at: y, in: card, height: subtitleHeight, attributes: DeskPickerLayout.subtitleAttributes)
        y -= DeskPickerLayout.headerGap
        drawDeskPickerRows(rows, in: card, from: y)

        drawLocalizedHintWithKeycap(
            text: L("calibration.desk.keysHint"),
            centerY: card.minY - 40,
            textColor: NSColor.white.withAlphaComponent(0.45),
            fontSize: 13
        )
    }

    private func drawCard(_ card: NSRect) {
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18)
        NSColor(white: 0.11, alpha: 0.97).setFill()
        cardPath.fill()
        NSColor.white.withAlphaComponent(0.1).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()
    }

    private func drawText(
        _ text: NSString,
        at y: CGFloat,
        in card: NSRect,
        height: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        text.draw(
            with: NSRect(
                x: card.minX + DeskPickerLayout.padding, y: y, width: DeskPickerLayout.textWidth, height: height),
            options: DeskPickerLayout.textOptions,
            attributes: attributes
        )
    }

    private func drawDeskPickerRows(_ rows: [DeskPickerRow], in card: NSRect, from top: CGFloat) {
        var y = top
        let hasDivider = DeskPickerLayout.hasDivider(rows)
        deskPickerRowRects = []
        var previousWasSecondary = false
        for (index, row) in rows.enumerated() {
            if row.isSecondary, !previousWasSecondary, hasDivider {
                y -= DeskPickerLayout.dividerSpacing
                NSColor.white.withAlphaComponent(0.08).setFill()
                NSRect(x: card.minX + DeskPickerLayout.padding, y: y - 1, width: DeskPickerLayout.textWidth, height: 1)
                    .fill()
                y -= 1 + DeskPickerLayout.dividerSpacing
            }
            previousWasSecondary = row.isSecondary

            let height = DeskPickerLayout.rowHeight(row)
            let rowRect = NSRect(x: card.minX + 16, y: y - height, width: card.width - 32, height: height)
            drawDeskPickerRow(row, in: rowRect, isFocused: focusedRowIndex == index)
            deskPickerRowRects.append(rowRect)
            y -= height + DeskPickerLayout.rowSpacing
        }
    }

    private func drawDeskPickerRow(_ row: DeskPickerRow, in rect: NSRect, isFocused: Bool) {
        drawRowBackground(row, in: rect, isFocused: isFocused)
        if !row.key.isEmpty {
            drawKeycap(row, in: rect)
        }
        let titleMaxX = row.isCurrent ? drawCurrentBadge(in: rect) - 10 : rect.maxX - 14

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: row.isSecondary ? 14 : 17, weight: row.isSecondary ? .regular : .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(row.isSecondary ? 0.7 : 1),
            .paragraphStyle: paragraphStyle,
        ]
        let title = row.title as NSString
        let titleHeight = title.size(withAttributes: titleAttrs).height
        let titleX = rect.minX + 14 + DeskPickerLayout.keycapColumnWidth + 14
        title.draw(
            in: NSRect(x: titleX, y: rect.midY - titleHeight / 2, width: titleMaxX - titleX, height: titleHeight),
            withAttributes: titleAttrs
        )
    }

    private func drawRowBackground(_ row: DeskPickerRow, in rect: NSRect, isFocused: Bool) {
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
    }

    private func drawKeycap(_ row: DeskPickerRow, in rect: NSRect) {
        let accent = Self.accent
        let columnWidth = DeskPickerLayout.keycapColumnWidth
        let keycapSize: CGFloat = row.isSecondary ? 24 : columnWidth
        let keycapRect = NSRect(
            x: rect.minX + 14 + (columnWidth - keycapSize) / 2,
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

    /// Returns the badge's left edge, so the title can be truncated before it
    private func drawCurrentBadge(in rect: NSRect) -> CGFloat {
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: Self.accent,
        ]
        let badge = L("calibration.desk.current") as NSString
        let badgeSize = badge.size(withAttributes: badgeAttrs)
        let pill = NSRect(
            x: rect.maxX - 14 - badgeSize.width - 16,
            y: rect.midY - (badgeSize.height + 6) / 2,
            width: badgeSize.width + 16,
            height: badgeSize.height + 6
        )
        Self.accent.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        badge.draw(at: NSPoint(x: pill.minX + 8, y: pill.minY + 3), withAttributes: badgeAttrs)
        return pill.minX
    }

    func resetDeskPickerHover() {
        hoveredRowIndex = nil
    }

    func deskPickerRowIndex(at point: NSPoint) -> Int? {
        deskPickerRowRects.firstIndex(where: { $0.contains(point) })
    }
}
