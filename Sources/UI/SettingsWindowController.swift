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

        // Restore saved position, or center on the screen the user is on.
        // A saved frame only counts if it is fully visible; a partially
        // off-screen frame would open cut off.
        let restored = window.setFrameUsingName("SettingsWindow")
        if !restored || !window.isFullyOnScreen {
            window.centerOnActiveScreen()
        }

        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Register autosave after positioning to prevent interference
        window.setFrameAutosaveName("SettingsWindow")
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            appDelegate?.restoreAccessoryActivationPolicyIfNeeded(excluding: window)
        }
        appDelegate?.onCalibrationComplete = nil
        appDelegate?.onActiveSourceChanged = nil
    }

    func windowDidResize(_ notification: Notification) {
        // The window isn't user-resizable, so any resize is SwiftUI content
        // layout (including the post-show layout that can grow the window
        // past a screen edge). Keep the new frame fully on screen.
        (notification.object as? NSWindow)?.constrainToVisibleScreenArea()
    }

    func close() {
        window?.close()
    }
}
