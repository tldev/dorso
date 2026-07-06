import AppKit
import SwiftUI

@MainActor
final class SupportWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?
    weak var appDelegate: AppDelegate?

    func showSupport(appDelegate: AppDelegate, fromStatusItem statusItem: NSStatusItem?) {
        self.appDelegate = appDelegate

        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let supportView = SupportView(appDelegate: appDelegate)
        let hostingController = NSHostingController(rootView: supportView)
        let fittingSize = hostingController.sizeThatFits(in: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("support.title")
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor.windowBackgroundColor

        let restored = window.setFrameUsingName("SupportWindow")
        if !restored || !isWindowOnScreen(window) {
            window.center()
        }

        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.setFrameAutosaveName("SupportWindow")
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            appDelegate?.restoreAccessoryActivationPolicyIfNeeded(excluding: window)
        }
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

struct SupportView: View {
    let appDelegate: AppDelegate

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.brandCyan.opacity(0.16))
                    .frame(width: 78, height: 78)

                Image(systemName: "heart.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.brandCyan)
            }

            VStack(spacing: 8) {
                Text(L("support.title"))
                    .font(.system(size: 22, weight: .semibold))

                Text(L("support.message"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: {
                appDelegate.openSupportPage()
                appDelegate.supportWindowController.close()
            }) {
                Label(L("support.button"), systemImage: "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.onBrandCyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.brandCyan)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}
