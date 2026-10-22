import AppKit

// MARK: - Menu Bar Manager

@MainActor
final class MenuBarManager: NSObject, NSMenuDelegate {
    private(set) var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var enabledMenuItem: NSMenuItem!
    private var recalibrateMenuItem: NSMenuItem!
    private var resumeMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var deskMenuItem: NSMenuItem!

    /// Timed pause lengths offered in the Pause submenu. Each one ends on its
    /// own; indefinite pausing is what the Enable toggle is for.
    static let pauseDurations: [TimeInterval] = [5 * 60, 10 * 60, 30 * 60, 60 * 60]

    // Callbacks
    var onToggleEnabled: (() -> Void)?
    var onRecalibrate: (() -> Void)?
    var onPause: ((TimeInterval) -> Void)?
    var onResume: (() -> Void)?
    /// Read each time the menu opens
    var desksProvider: (() -> (desks: [(id: String, name: String)], activeID: String?))?
    var onSelectDesk: ((String) -> Void)?
    var onManageDesks: (() -> Void)?
    var onShowAnalytics: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenSupport: (() -> Void)?
    var onQuit: (() -> Void)?
    #if !APP_STORE
        var onCheckForUpdates: (() -> Void)?
    #endif

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = MenuBarIcon.good.image
        }

        statusItem.menu = makeMenu()
    }

    /// Builds the status menu and retains its mutable items. Separate from
    /// `setup()` because NSMenu needs no window server connection, so
    /// headless tests can build the menu and exercise the update methods.
    @discardableResult
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        // Item enablement is driven by tracking state via the update methods
        menu.autoenablesItems = false
        menu.delegate = self

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

        // Resume Now (only shown during a timed pause)
        resumeMenuItem = NSMenuItem(title: L("menu.resumeNow"), action: #selector(handleResume), keyEquivalent: "")
        resumeMenuItem.target = self
        resumeMenuItem.isHidden = true
        menu.addItem(resumeMenuItem)

        // Timed pause
        pauseMenuItem = NSMenuItem(title: L("menu.pause"), action: nil, keyEquivalent: "")
        pauseMenuItem.submenu = makePauseSubmenu()
        menu.addItem(pauseMenuItem)

        // Desk switcher (only shown once the display setup has two desks)
        deskMenuItem = NSMenuItem(title: L("menu.desk"), action: nil, keyEquivalent: "")
        deskMenuItem.submenu = NSMenu()
        deskMenuItem.isHidden = true
        menu.addItem(deskMenuItem)

        // Recalibrate
        recalibrateMenuItem = NSMenuItem(
            title: L("menu.recalibrate"), action: #selector(handleRecalibrate), keyEquivalent: "r")
        recalibrateMenuItem.target = self
        menu.addItem(recalibrateMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Support
        let supportItem = NSMenuItem(title: L("menu.support"), action: #selector(handleOpenSupport), keyEquivalent: "")
        supportItem.target = self
        supportItem.image = NSImage(systemSymbolName: "heart", accessibilityDescription: L("menu.support"))
        menu.addItem(supportItem)

        // Analytics
        let statsItem = NSMenuItem(
            title: L("menu.analytics"), action: #selector(handleShowAnalytics), keyEquivalent: "a")
        statsItem.target = self
        statsItem.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: L("menu.analytics"))
        menu.addItem(statsItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: L("menu.settings"), action: #selector(handleOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L("menu.settings"))
        menu.addItem(settingsItem)

        #if !APP_STORE
            // Check for Updates (direct-distribution builds only; the App Store
            // delivers updates for Mac App Store installs)
            let updatesItem = NSMenuItem(
                title: L("menu.checkForUpdates"), action: #selector(handleCheckForUpdates), keyEquivalent: "")
            updatesItem.target = self
            updatesItem.image = NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: L("menu.checkForUpdates"))
            menu.addItem(updatesItem)
        #endif

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: L("menu.quit"), action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makePauseSubmenu() -> NSMenu {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]

        let submenu = NSMenu()
        for duration in Self.pauseDurations {
            let item = NSMenuItem(
                title: formatter.string(from: duration) ?? "",
                action: #selector(handlePause(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = duration
            submenu.addItem(item)
        }
        return submenu
    }

    // MARK: - Updates

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshDesks()
    }

    func refreshDesks() {
        guard isSetUp else { return }
        let (desks, activeID) = desksProvider?() ?? ([], nil)
        deskMenuItem.isHidden = desks.count < 2

        let submenu = NSMenu()
        for desk in desks {
            let item = NSMenuItem(title: desk.name, action: #selector(handleSelectDesk(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = desk.id
            item.state = desk.id == activeID ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(NSMenuItem.separator())
        let manageItem = NSMenuItem(
            title: L("menu.manageDesks"), action: #selector(handleManageDesks), keyEquivalent: "")
        manageItem.target = self
        submenu.addItem(manageItem)
        deskMenuItem.submenu = submenu
    }

    private var isSetUp: Bool { statusMenuItem != nil }

    func updateStatus(text: String, icon: MenuBarIcon) {
        guard isSetUp else { return }
        statusMenuItem.title = text
        statusItem?.button?.image = icon.image
    }

    func updateEnabledState(_ enabled: Bool) {
        guard isSetUp else { return }
        enabledMenuItem.state = enabled ? .on : .off
    }

    func updateRecalibrateEnabled(_ enabled: Bool) {
        guard isSetUp else { return }
        recalibrateMenuItem.isEnabled = enabled
    }

    func updateDeskEnabled(_ enabled: Bool) {
        guard isSetUp else { return }
        deskMenuItem.isEnabled = enabled
    }

    func updatePauseState(canPause: Bool, isTimedPause: Bool) {
        guard isSetUp else { return }
        pauseMenuItem.isEnabled = canPause
        resumeMenuItem.isHidden = !isTimedPause
    }

    func updateShortcut(enabled: Bool, shortcut: KeyboardShortcut) {
        guard isSetUp else { return }
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

    @objc private func handlePause(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? TimeInterval else { return }
        onPause?(duration)
    }

    @objc private func handleResume() {
        onResume?()
    }

    @objc private func handleSelectDesk(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onSelectDesk?(id)
    }

    @objc private func handleManageDesks() {
        onManageDesks?()
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

    #if !APP_STORE
        @objc private func handleCheckForUpdates() {
            onCheckForUpdates?()
        }
    #endif
}
