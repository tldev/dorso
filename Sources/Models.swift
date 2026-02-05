import Foundation
import CoreGraphics
import AppKit

// MARK: - Icon Utilities

/// Applies macOS-style rounded corner mask to an app icon
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

// MARK: - Menu Bar Icons

enum MenuBarIcon: String, CaseIterable {
    case good = "posture-good"
    case bad = "posture-bad"
    case away = "posture-away"
    case paused = "posture-paused"
    case calibrating = "posture-calibrating"

    /// Fallback SF Symbol for each icon state
    private var fallbackSymbol: String {
        switch self {
        case .good: return "figure.stand"
        case .bad: return "figure.fall"
        case .away: return "figure.walk"
        case .paused: return "pause.circle"
        case .calibrating: return "figure.stand"
        }
    }

    /// Accessibility description for the icon
    private var accessibilityDescription: String {
        switch self {
        case .good: return "Good Posture"
        case .bad: return "Bad Posture"
        case .away: return "Away"
        case .paused: return "Paused"
        case .calibrating: return "Calibrating"
        }
    }

    /// Returns the menu bar icon, preferring custom PDF if available
    var image: NSImage? {
        // Try to load custom PDF icon from Resources/Icons/
        if let url = Bundle.main.url(forResource: rawValue, withExtension: "pdf", subdirectory: "Icons"),
           let customImage = NSImage(contentsOf: url) {
            // Resize to menu bar height (18pt) while preserving aspect ratio
            let targetHeight: CGFloat = 18
            let aspectRatio = customImage.size.width / customImage.size.height
            let targetWidth = targetHeight * aspectRatio
            let targetSize = NSSize(width: targetWidth, height: targetHeight)

            let resizedImage = NSImage(size: targetSize)
            resizedImage.lockFocus()
            customImage.draw(in: NSRect(origin: .zero, size: targetSize),
                           from: NSRect(origin: .zero, size: customImage.size),
                           operation: .copy,
                           fraction: 1.0)
            resizedImage.unlockFocus()
            resizedImage.isTemplate = true
            return resizedImage
        }

        // Fall back to SF Symbol
        let image = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        return image
    }
}

// MARK: - Constants

enum WarningDefaults {
    static let color = NSColor(red: 0.85, green: 0.05, blue: 0.05, alpha: 1.0)
}

// MARK: - Warning Mode

enum WarningMode: String, CaseIterable, Codable {
    case blur = "blur"
    case vignette = "vignette"
    case border = "border"
    case solid = "solid"
    case none = "none"

    /// Whether this mode uses the WarningOverlayManager for posture warnings.
    /// Vignette, border, and solid use the overlay system; blur and none do not.
    var usesWarningOverlay: Bool {
        switch self {
        case .vignette, .border, .solid: return true
        case .blur, .none: return false
        }
    }
}

// MARK: - Detection Mode

enum DetectionMode: String, CaseIterable, Codable {
    case responsive = "responsive"  // 10 fps - best accuracy (default)
    case balanced = "balanced"      // 4 fps - good balance
    case performance = "performance" // 2 fps - best battery life

    var frameRate: Double {
        switch self {
        case .responsive: return 10.0
        case .balanced: return 4.0
        case .performance: return 2.0
        }
    }

    var displayName: String {
        switch self {
        case .responsive: return "Responsive"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        }
    }
}
