import AppKit

// MARK: - Menu Bar Manager

class MenuBarManager {
    var statusItem: NSStatusItem!
    var statusMenuItem: NSMenuItem!
    var enabledMenuItem: NSMenuItem!
    var recalibrateMenuItem: NSMenuItem!

    weak var appDelegate: AppDelegate?

    func setup(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = MenuBarIcon.good.image
        }

        let menu = NSMenu()

        // Status
        statusMenuItem = NSMenuItem(title: "Status: Starting...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Enabled toggle
        enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(appDelegate.toggleEnabled), keyEquivalent: "e")
        enabledMenuItem.target = appDelegate
        enabledMenuItem.state = .on
        menu.addItem(enabledMenuItem)

        // Recalibrate
        recalibrateMenuItem = NSMenuItem(title: "Recalibrate", action: #selector(appDelegate.recalibrate), keyEquivalent: "r")
        recalibrateMenuItem.target = appDelegate
        menu.addItem(recalibrateMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(appDelegate.openSettings), keyEquivalent: ",")
        settingsItem.target = appDelegate
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(appDelegate.quit), keyEquivalent: "q")
        quitItem.target = appDelegate
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func updateStatus(title: String, icon: MenuBarIcon) {
        statusMenuItem.title = title
        statusItem.button?.image = icon.image
    }

    func updateEnabledState(_ enabled: Bool) {
        enabledMenuItem.state = enabled ? .on : .off
    }

    func updateRecalibrateItem(hasCamera: Bool, isCalibrating: Bool) {
        if hasCamera && !isCalibrating {
            recalibrateMenuItem.title = "Recalibrate"
            recalibrateMenuItem.action = #selector(appDelegate?.recalibrate)
            recalibrateMenuItem.isEnabled = true
        } else {
            recalibrateMenuItem.title = hasCamera ? "Recalibrate" : "Recalibrate (no camera)"
            recalibrateMenuItem.action = nil
            recalibrateMenuItem.isEnabled = false
        }
    }
}
