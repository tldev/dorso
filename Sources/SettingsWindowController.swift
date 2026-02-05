import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?
    weak var appDelegate: AppDelegate?

    func showSettings(appDelegate: AppDelegate, fromStatusItem statusItem: NSStatusItem?) {
        self.appDelegate = appDelegate

        // Find the screen where the status item is located
        let targetScreen = statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first

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
        window.title = "Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor.windowBackgroundColor

        // Restore saved window position, or center on status item's screen if no saved position
        window.setFrameAutosaveName("SettingsWindow")
        if !window.setFrameUsingName("SettingsWindow") {
            // No saved position - center on target screen
            if let screen = targetScreen {
                centerWindow(window, on: screen)
            } else {
                window.center()
            }
        }

        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Only hide from Dock if user hasn't enabled "Show in Dock"
        if let appDelegate = appDelegate, !appDelegate.showInDock {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func centerWindow(_ window: NSWindow, on screen: NSScreen) {
        let screenFrame = screen.frame
        let windowSize = window.frame.size
        let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func close() {
        window?.close()
    }
}

