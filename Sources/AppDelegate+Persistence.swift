import AppKit
import Foundation

extension AppDelegate {
    // MARK: - Global Keyboard Shortcut

    func updateGlobalKeyMonitor() {
        hotkeyManager.isEnabled = toggleShortcutEnabled
        hotkeyManager.shortcut = toggleShortcut
        menuBarManager.updateShortcut(enabled: toggleShortcutEnabled, shortcut: toggleShortcut)
    }

    // MARK: - Persistence

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(useCompatibilityMode, forKey: SettingsKeys.useCompatibilityMode)
        defaults.set(blurWhenAway, forKey: SettingsKeys.blurWhenAway)
        defaults.set(showInDock, forKey: SettingsKeys.showInDock)
        defaults.set(pauseOnTheGo, forKey: SettingsKeys.pauseOnTheGo)
        defaults.set(toggleShortcutEnabled, forKey: SettingsKeys.toggleShortcutEnabled)
        defaults.set(Int(toggleShortcut.keyCode), forKey: SettingsKeys.toggleShortcutKeyCode)
        defaults.set(Int(toggleShortcut.modifiers.rawValue), forKey: SettingsKeys.toggleShortcutModifiers)
        if let cameraID = selectedCameraID {
            defaults.set(cameraID, forKey: SettingsKeys.lastCameraID)
        }
        defaults.set(trackingSource.rawValue, forKey: SettingsKeys.trackingSource)
        if let airPodsCalibration = airPodsCalibration,
           let data = try? JSONEncoder().encode(airPodsCalibration) {
            defaults.set(data, forKey: SettingsKeys.airPodsCalibration)
        }
    }

    func loadSettings() {
        let defaults = UserDefaults.standard
        SettingsMigrations.migrateLegacyKeysIfNeeded(userDefaults: defaults)
        settingsProfileManager.loadProfiles()
        applyActiveSettingsProfile()

        useCompatibilityMode = defaults.bool(forKey: SettingsKeys.useCompatibilityMode)
        blurWhenAway = defaults.bool(forKey: SettingsKeys.blurWhenAway)
        showInDock = defaults.bool(forKey: SettingsKeys.showInDock)
        pauseOnTheGo = defaults.bool(forKey: SettingsKeys.pauseOnTheGo)
        cameraDetector.selectedCameraID = defaults.string(forKey: SettingsKeys.lastCameraID)
        if let sourceString = defaults.string(forKey: SettingsKeys.trackingSource),
           let source = TrackingSource(rawValue: sourceString) {
            trackingSource = source
        }
        if let data = defaults.data(forKey: SettingsKeys.airPodsCalibration),
           let calibration = try? JSONDecoder().decode(AirPodsCalibrationData.self, from: data) {
            airPodsCalibration = calibration
        }
        if defaults.object(forKey: SettingsKeys.toggleShortcutEnabled) != nil {
            toggleShortcutEnabled = defaults.bool(forKey: SettingsKeys.toggleShortcutEnabled)
        }
        if defaults.object(forKey: SettingsKeys.toggleShortcutKeyCode) != nil {
            let keyCode = UInt16(defaults.integer(forKey: SettingsKeys.toggleShortcutKeyCode))
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: SettingsKeys.toggleShortcutModifiers)))
            toggleShortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
        }
    }

    func saveProfile(forKey key: String, data: ProfileData) {
        let defaults = UserDefaults.standard
        var profiles = defaults.dictionary(forKey: SettingsKeys.profiles) as? [String: Data] ?? [:]

        if let encoded = try? JSONEncoder().encode(data) {
            profiles[key] = encoded
            defaults.set(profiles, forKey: SettingsKeys.profiles)
        }
    }

    func loadProfile(forKey key: String) -> ProfileData? {
        let defaults = UserDefaults.standard
        guard let profiles = defaults.dictionary(forKey: SettingsKeys.profiles) as? [String: Data],
              let data = profiles[key] else {
            return nil
        }

        return try? JSONDecoder().decode(ProfileData.self, from: data)
    }
}
