import AppKit
import ServiceManagement
import SwiftUI

extension SettingsView {
    var behaviorCard: some View {
        // Behavior card: appearance in the header (matching the other
        // cards' header-control pattern), app-level toggles below
        SettingsCard(icon: "switch.2", title: L("settings.section.behavior")) {
            CompactSegmentedPicker(
                // Side effects live in the binding so they run inside the
                // click action itself; the custom-drawn controls keep
                // their brand colors through the appearance change
                selection: Binding(
                    get: { appAppearance },
                    set: { newValue in
                        appDelegate.appAppearance = newValue
                        appDelegate.saveSettings()
                        appDelegate.applyAppearance()
                        appAppearance = newValue
                    }
                ),
                options: AppAppearance.allCases.map { ($0, $0.displayName) }
            )
            .frame(width: 170)
            .help(L("settings.appearance"))
        } content: {
            VStack(spacing: 6) {

                HStack(spacing: 0) {
                    CompactToggle(
                        title: L("settings.launchAtLogin"),
                        helpText: L("settings.launchAtLogin.help"),
                        isOn: $launchAtLogin
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                    CompactToggle(
                        title: L("settings.showInDock"),
                        helpText: L("settings.showInDock.help"),
                        isOn: $showInDock
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: showInDock) { newValue in
                        appDelegate.showInDock = newValue
                        appDelegate.saveSettings()
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        DispatchQueue.main.async {
                            appDelegate.settingsWindowController.window?.makeKeyAndOrderFront(nil)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }

                #if !APP_STORE
                    HStack(spacing: 0) {
                        CompactToggle(
                            title: L("settings.autoUpdates"),
                            helpText: L("settings.autoUpdates.help"),
                            isOn: $autoCheckForUpdates
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: autoCheckForUpdates) { newValue in
                            appDelegate.updaterManager?.automaticallyChecksForUpdates = newValue
                        }

                        CompactToggle(
                            title: L("settings.compatibilityMode"),
                            helpText: L("settings.compatibilityMode.help"),
                            isOn: $useCompatibilityMode
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: useCompatibilityMode) { newValue in
                            appDelegate.useCompatibilityMode = newValue
                            appDelegate.saveSettings()
                            // Clear both blur mechanisms, not just the visual
                            // effect views: the CGS background blur radius of the
                            // outgoing private-API path survives alpha resets and
                            // would otherwise stay on screen indefinitely
                            appDelegate.clearBlur()
                        }
                    }
                #endif

                HStack(spacing: 0) {
                    CompactToggle(
                        title: L("settings.pauseOnTheGo"),
                        helpText: L("settings.pauseOnTheGo.help"),
                        isOn: $pauseOnTheGo
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: pauseOnTheGo) { newValue in
                        Task { @MainActor in
                            await appDelegate.setPauseOnTheGoEnabled(newValue)
                        }
                    }

                    CompactToggle(
                        title: L("settings.pauseOnBattery"),
                        helpText: L("settings.pauseOnBattery.help"),
                        isOn: $pauseOnBattery
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: pauseOnBattery) { newValue in
                        Task { @MainActor in
                            await appDelegate.setPauseOnBatteryEnabled(newValue)
                        }
                    }
                }

                HStack(spacing: 0) {
                    CompactToggle(
                        title: L("settings.blurWhenAway"),
                        helpText: trackingSource == .airpods
                            ? L("settings.blurWhenAway.help.airpods")
                            : L("settings.blurWhenAway.help.camera"),
                        isOn: $blurWhenAway,
                        isDisabled: trackingSource == .airpods
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: blurWhenAway) { newValue in
                        appDelegate.blurWhenAway = newValue
                        appDelegate.saveSettings()
                    }

                    CompactToggle(
                        title: L("settings.fullScreenOverlay"),
                        helpText: L("settings.fullScreenOverlay.help"),
                        isOn: $useFullScreenOverlay
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: useFullScreenOverlay) { newValue in
                        appDelegate.useFullScreenOverlay = newValue
                        appDelegate.saveSettings()
                        appDelegate.rebuildOverlayWindows()
                    }
                }

                // Shortcut row (full width so the recorder chip doesn't
                // disrupt the toggle grid rhythm)
                HStack(spacing: 0) {
                    CompactShortcutRecorder(
                        shortcut: $toggleShortcut,
                        isEnabled: $toggleShortcutEnabled,
                        onShortcutChange: {
                            appDelegate.toggleShortcutEnabled = toggleShortcutEnabled
                            appDelegate.toggleShortcut = toggleShortcut
                            appDelegate.saveSettings()
                            appDelegate.updateGlobalKeyMonitor()
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
