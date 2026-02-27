import Foundation
import os

enum SettingsMigrations {
    private static let logger = Logger(subsystem: "com.thelazydeveloper.dorso", category: "SettingsMigrations")

    static func migrateLegacyKeysIfNeeded(userDefaults: UserDefaults = .standard) {
        migrateAirPodsCalibrationKeyIfNeeded(userDefaults: userDefaults)
        migrateTrackingPolicyKeysIfNeeded(userDefaults: userDefaults)
    }

    static func migrateAirPodsCalibrationKeyIfNeeded(userDefaults: UserDefaults = .standard) {
        let newKey = SettingsKeys.airPodsCalibration
        let legacyKey = SettingsKeys.legacyAirPodsProfile

        guard userDefaults.data(forKey: newKey) == nil else { return }
        guard let legacyData = userDefaults.data(forKey: legacyKey) else { return }

        userDefaults.set(legacyData, forKey: newKey)
        logger.info("Migrated AirPods calibration from legacy key '\(legacyKey, privacy: .public)' to '\(newKey, privacy: .public)'.")
    }

    static func migrateTrackingPolicyKeysIfNeeded(userDefaults: UserDefaults = .standard) {
        guard userDefaults.string(forKey: SettingsKeys.trackingPolicyMode) == nil else { return }

        let legacySource = userDefaults.string(forKey: SettingsKeys.trackingSource)
            .flatMap(TrackingSource.init(rawValue:))
            ?? .camera

        userDefaults.set(TrackingPolicyMode.manual.rawValue, forKey: SettingsKeys.trackingPolicyMode)
        userDefaults.set(legacySource.rawValue, forKey: SettingsKeys.manualTrackingSource)
        userDefaults.set(legacySource.rawValue, forKey: SettingsKeys.preferredTrackingSource)
        userDefaults.set(true, forKey: SettingsKeys.autoReturnEnabled)

        logger.info("Initialized tracking policy settings from legacy tracking source '\(legacySource.rawValue, privacy: .public)'.")
    }
}
