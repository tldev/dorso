import AppKit

extension AppDelegate {
    // MARK: - Menu Bar

    func setupMenuBar() {
        menuBarManager.setup()
        menuBarManager.updateShortcut(enabled: toggleShortcutEnabled, shortcut: toggleShortcut)
        setupTrackingMenuActions()
        setupWindowMenuActions()
    }

    private func setupTrackingMenuActions() {
        menuBarManager.onToggleEnabled = { [weak self] in
            Task { @MainActor in
                await self?.toggleEnabled()
            }
        }
        menuBarManager.onPause = { [weak self] duration in
            Task { @MainActor in
                await self?.pause(for: duration)
            }
        }
        menuBarManager.onResume = { [weak self] in
            Task { @MainActor in
                await self?.resumeFromTimedPause()
            }
        }
        menuBarManager.desksProvider = { [weak self] in
            self?.desksForMenu() ?? ([], nil)
        }
        menuBarManager.onSelectDesk = { [weak self] id in
            Task { @MainActor in
                await self?.selectDesk(id: id)
            }
        }
        menuBarManager.onManageDesks = { [weak self] in
            Task { @MainActor in
                self?.openSettings()
            }
        }
        menuBarManager.onRecalibrate = { [weak self] in
            Task { @MainActor in
                self?.startCalibration()
            }
        }
    }

    private func setupWindowMenuActions() {
        menuBarManager.onShowAnalytics = { [weak self] in
            Task { @MainActor in
                self?.showAnalytics()
            }
        }
        menuBarManager.onOpenSettings = { [weak self] in
            Task { @MainActor in
                self?.openSettings()
            }
        }
        menuBarManager.onOpenSupport = { [weak self] in
            Task { @MainActor in
                self?.showSupport()
            }
        }
        menuBarManager.onQuit = { [weak self] in
            Task { @MainActor in
                self?.quit()
            }
        }
        #if !APP_STORE
            menuBarManager.onCheckForUpdates = { [weak self] in
                Task { @MainActor in
                    self?.updaterManager?.checkForUpdates()
                }
            }
        #endif
    }

    // MARK: - Menu Actions

    private func showAnalytics() {
        if analyticsWindowController == nil {
            analyticsWindowController = AnalyticsWindowController()
        }
        analyticsWindowController?.appDelegate = self
        analyticsWindowController?.showWindow(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettings() {
        settingsWindowController.showSettings(appDelegate: self, fromStatusItem: menuBarManager.statusItem)
    }

    func showSupport() {
        supportWindowController.showSupport(appDelegate: self, fromStatusItem: menuBarManager.statusItem)
    }

    private func quit() {
        cameraDetector.stop()
        airPodsDetector.stop()
        NSApplication.shared.terminate(nil)
    }

    func openSupportPage() {
        guard let url = URL(string: "https://buymeacoffee.com/tjohnell") else { return }

        if let openSupportURLHandler {
            openSupportURLHandler(url)
            return
        }

        NSWorkspace.shared.open(url)
    }
}
