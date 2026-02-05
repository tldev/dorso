import AppKit
import CoreGraphics

extension AppDelegate {
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

        if activeWarningMode.usesWarningOverlay {
            warningOverlayManager.rebuildOverlayWindows()
        }
    }

    func clearBlur() {
        targetBlurRadius = 0
        currentBlurRadius = 0

        for blurView in blurViews {
            blurView.alphaValue = 0
        }

        #if !APP_STORE
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
        clearBlur()

        warningOverlayManager.mode = newMode

        warningOverlayManager.currentIntensity = 0
        warningOverlayManager.targetIntensity = 0
        for view in warningOverlayManager.overlayViews {
            if let vignetteView = view as? VignetteOverlayView {
                vignetteView.intensity = 0
            } else if let borderView = view as? BorderOverlayView {
                borderView.intensity = 0
            }
        }

        for window in warningOverlayManager.windows {
            window.orderOut(nil)
        }
        warningOverlayManager.windows.removeAll()
        warningOverlayManager.overlayViews.removeAll()

        if newMode.usesWarningOverlay {
            warningOverlayManager.warningColor = activeWarningColor
            warningOverlayManager.setupOverlayWindows()
        }
    }

    func updateWarningColor(_ color: NSColor) {
        warningOverlayManager.updateColor(color)
    }

    func updateBlur() {
        let privacyBlurIntensity: CGFloat = isCurrentlyAway ? 1.0 : 0.0

        switch activeWarningMode {
        case .blur:
            let combinedIntensity = max(privacyBlurIntensity, postureWarningIntensity)
            targetBlurRadius = Int32(combinedIntensity * 64)
            warningOverlayManager.targetIntensity = 0
        case .none:
            targetBlurRadius = Int32(privacyBlurIntensity * 64)
            warningOverlayManager.targetIntensity = 0
        case .vignette, .border, .solid:
            targetBlurRadius = Int32(privacyBlurIntensity * 64)
            warningOverlayManager.targetIntensity = postureWarningIntensity
        }

        // Skip work if nothing is changing
        let blurNeedsUpdate = currentBlurRadius != targetBlurRadius
        let overlayNeedsUpdate = warningOverlayManager.currentIntensity != warningOverlayManager.targetIntensity
        guard blurNeedsUpdate || overlayNeedsUpdate else { return }

        warningOverlayManager.updateWarning()

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
}
