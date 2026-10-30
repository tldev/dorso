enum KeycapHintDirection: Equatable {
    case leftToRight
    case rightToLeft
}

/// Visual order for calibration hints that mix prose with `{Key}` caps.
enum KeycapHintLayout {
    /// First strong letter outside `{...}` keycaps. No strong letter means left to right.
    static func direction(of text: String) -> KeycapHintDirection {
        baseDirection(of: segments(in: text))
    }

    /// Left-to-right drawing order. Right-to-left hints are the logical segments reversed.
    static func visualSegments(in text: String) -> [(text: String, isKeycap: Bool)] {
        let parsed = segments(in: text)
        guard baseDirection(of: parsed) == .rightToLeft else { return parsed }
        return Array(parsed.reversed())
    }

    private static let rightToLeftLetters: [ClosedRange<UInt32>] = [
        0x0590...0x05FF,  // Hebrew
        0xFB1D...0xFB4F,  // Hebrew presentation forms
        0x0600...0x06FF,  // Arabic
        0x0750...0x077F,  // Arabic Supplement
        0x08A0...0x08FF,  // Arabic Extended-A
        0xFB50...0xFDFF,  // Arabic Presentation Forms-A
        0xFE70...0xFEFF,  // Arabic Presentation Forms-B
    ]

    private static func baseDirection(
        of segments: [(text: String, isKeycap: Bool)]
    ) -> KeycapHintDirection {
        for segment in segments where !segment.isKeycap {
            for scalar in segment.text.unicodeScalars where scalar.properties.isAlphabetic {
                return isRightToLeftLetter(scalar) ? .rightToLeft : .leftToRight
            }
        }
        return .leftToRight
    }

    private static func isRightToLeftLetter(_ scalar: Unicode.Scalar) -> Bool {
        rightToLeftLetters.contains { $0.contains(scalar.value) }
    }

    private static func segments(in text: String) -> [(text: String, isKeycap: Bool)] {
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
        return segments
    }
}
