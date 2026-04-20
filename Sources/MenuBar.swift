import AppKit

// MARK: - Menu Bar Manager

@MainActor
final class MenuBarManager {
    private(set) var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var enabledMenuItem: NSMenuItem!
    private var recalibrateMenuItem: NSMenuItem!

    // Callbacks
    var onToggleEnabled: (() -> Void)?
    var onRecalibrate: (() -> Void)?
    var onShowAnalytics: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenSupport: (() -> Void)?
    var onQuit: (() -> Void)?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let icon = MenuBarIcon.good.image
            button.image = icon
            if icon == nil {
                button.title = "Dorso"
            }
        }

        let menu = NSMenu()

        // Status
        statusMenuItem = NSMenuItem(title: L("menu.status.starting"), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Enabled toggle
        enabledMenuItem = NSMenuItem(title: L("menu.enable"), action: #selector(handleToggleEnabled), keyEquivalent: "")
        enabledMenuItem.target = self
        enabledMenuItem.state = .on
        menu.addItem(enabledMenuItem)

        // Recalibrate
        recalibrateMenuItem = NSMenuItem(title: L("menu.recalibrate"), action: #selector(handleRecalibrate), keyEquivalent: "r")
        recalibrateMenuItem.target = self
        menu.addItem(recalibrateMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Support
        let supportItem = NSMenuItem(title: L("menu.support"), action: #selector(handleOpenSupport), keyEquivalent: "")
        supportItem.target = self
        supportItem.image = NSImage(systemSymbolName: "heart", accessibilityDescription: L("menu.support"))
        menu.addItem(supportItem)

        // Analytics
        let statsItem = NSMenuItem(title: L("menu.analytics"), action: #selector(handleShowAnalytics), keyEquivalent: "a")
        statsItem.target = self
        statsItem.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: L("menu.analytics"))
        menu.addItem(statsItem)

        // Settings
        let settingsItem = NSMenuItem(title: L("menu.settings"), action: #selector(handleOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L("menu.settings"))
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: L("menu.quit"), action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Updates

    private var isSetUp: Bool { statusItem != nil }

    func updateStatus(text: String, icon: MenuBarIcon) {
        guard isSetUp else { return }
        statusMenuItem.title = text
        guard let button = statusItem.button else { return }
        let iconImage = icon.image
        button.image = iconImage
        button.title = iconImage == nil ? "Dorso" : ""
    }

    func updateEnabledState(_ enabled: Bool) {
        guard isSetUp else { return }
        enabledMenuItem.state = enabled ? .on : .off
    }

    func updateRecalibrateEnabled(_ enabled: Bool) {
        guard isSetUp else { return }
        recalibrateMenuItem.isEnabled = enabled
    }

    func updateShortcut(enabled: Bool, shortcut: KeyboardShortcut) {
        if enabled {
            enabledMenuItem.keyEquivalent = shortcut.keyCharacter
            enabledMenuItem.keyEquivalentModifierMask = shortcut.modifiers
        } else {
            enabledMenuItem.keyEquivalent = ""
            enabledMenuItem.keyEquivalentModifierMask = []
        }
    }

    // MARK: - Actions

    @objc private func handleToggleEnabled() {
        onToggleEnabled?()
    }

    @objc private func handleRecalibrate() {
        onRecalibrate?()
    }

    @objc private func handleShowAnalytics() {
        onShowAnalytics?()
    }

    @objc private func handleOpenSettings() {
        onOpenSettings?()
    }

    @objc private func handleOpenSupport() {
        onOpenSupport?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}
