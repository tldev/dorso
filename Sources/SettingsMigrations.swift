import Foundation
import os

enum SettingsMigrations {
    private static let logger = Logger(subsystem: "com.posturr", category: "SettingsMigrations")

    static func migrateLegacyKeysIfNeeded(userDefaults: UserDefaults = .standard) {
        migrateAirPodsCalibrationKeyIfNeeded(userDefaults: userDefaults)
    }

    static func migrateAirPodsCalibrationKeyIfNeeded(userDefaults: UserDefaults = .standard) {
        let newKey = SettingsKeys.airPodsCalibration
        let legacyKey = SettingsKeys.legacyAirPodsProfile

        guard userDefaults.data(forKey: newKey) == nil else { return }
        guard let legacyData = userDefaults.data(forKey: legacyKey) else { return }

        userDefaults.set(legacyData, forKey: newKey)
        logger.info("Migrated AirPods calibration from legacy key '\(legacyKey, privacy: .public)' to '\(newKey, privacy: .public)'.")
    }
}

