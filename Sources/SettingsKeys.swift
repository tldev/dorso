import Foundation

// MARK: - Settings Keys

enum SettingsKeys {
    static let intensity = "intensity"
    static let deadZone = "deadZone"
    static let useCompatibilityMode = "useCompatibilityMode"
    static let blurWhenAway = "blurWhenAway"
    static let showInDock = "showInDock"
    static let pauseOnTheGo = "pauseOnTheGo"
    static let lastCameraID = "lastCameraID"
    static let profiles = "profiles"
    static let settingsProfiles = "settingsProfiles"
    static let currentSettingsProfileID = "currentSettingsProfileID"
    static let warningMode = "warningMode"
    static let warningColor = "warningColor"
    static let warningOnsetDelay = "blurOnsetDelay"  // Keep key for backward compatibility
    static let toggleShortcutEnabled = "toggleShortcutEnabled"
    static let toggleShortcutKeyCode = "toggleShortcutKeyCode"
    static let toggleShortcutModifiers = "toggleShortcutModifiers"
    static let detectionMode = "detectionMode"
    static let trackingSource = "trackingSource"
    static let airPodsCalibration = "airPodsCalibration"

    // Legacy keys (migrated on load)
    static let legacyAirPodsProfile = "airPodsProfile"
}
