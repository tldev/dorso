import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?
    weak var appDelegate: AppDelegate?

    func showSettings(appDelegate: AppDelegate, fromStatusItem statusItem: NSStatusItem?) {
        self.appDelegate = appDelegate

        if let existingWindow = window {
            // Show existing window where user left it (position is auto-saved)
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(appDelegate: appDelegate)
        let hostingController = NSHostingController(rootView: settingsView)

        // Calculate actual content size from SwiftUI view
        let fittingSize = hostingController.sizeThatFits(in: CGSize(width: 480, height: CGFloat.greatestFiniteMagnitude))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings.title")
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor.windowBackgroundColor

        // Restore saved position or center on screen
        let restored = window.setFrameUsingName("SettingsWindow")
        if !restored || !self.isWindowOnScreen(window) {
            window.center()
        }

        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Register autosave after positioning to prevent interference
        window.setFrameAutosaveName("SettingsWindow")
    }

    func windowWillClose(_ notification: Notification) {
        // Only hide from Dock if user hasn't enabled "Show in Dock"
        if let appDelegate = appDelegate, !appDelegate.showInDock {
            NSApp.setActivationPolicy(.accessory)
        }
        appDelegate?.onCalibrationComplete = nil
        appDelegate?.onActiveSourceChanged = nil
    }

    private func isWindowOnScreen(_ window: NSWindow) -> Bool {
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(window.frame) {
                return true
            }
        }
        return false
    }

    func close() {
        window?.close()
    }
}

