import AppKit
import CoreGraphics
import Foundation

// MARK: - Profile Data

struct ProfileData: Codable {
    let goodPostureY: CGFloat
    let badPostureY: CGFloat
    let neutralY: CGFloat
    let postureRange: CGFloat
    let cameraID: String
}

// MARK: - Settings Profile

struct SettingsProfile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var warningMode: WarningMode
    var warningColorData: Data
    var deadZone: Double
    var intensity: Double
    var warningOnsetDelay: Double
    var detectionMode: DetectionMode

    var warningColor: NSColor {
        if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: warningColorData) {
            return color
        }
        return WarningDefaults.color
    }

    static func encodedColorData(from color: NSColor) -> Data {
        (try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)) ?? Data()
    }
}

// MARK: - Settings Profile Manager

@MainActor
final class SettingsProfileManager {
    private(set) var settingsProfiles: [SettingsProfile] = []
    private(set) var currentSettingsProfileID: String?
    private let defaultIntensity: Double = 1.0
    private let defaultDeadZone: Double = 0.03
    private let defaultWarningOnsetDelay: Double = 0.0
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var activeProfile: SettingsProfile? {
        guard let profileID = currentSettingsProfileID else { return nil }
        return settingsProfiles.first(where: { $0.id == profileID })
    }

    func loadProfiles() {
        guard settingsProfiles.isEmpty else { return }
        let defaults = userDefaults
        if let data = defaults.data(forKey: SettingsKeys.settingsProfiles),
           let profiles = try? JSONDecoder().decode([SettingsProfile].self, from: data),
           !profiles.isEmpty {
            settingsProfiles = profiles
            let savedID = defaults.string(forKey: SettingsKeys.currentSettingsProfileID)
            let selectedProfile = profiles.first(where: { $0.id == savedID }) ?? profiles.first
            currentSettingsProfileID = selectedProfile?.id
            return
        }

        let legacyIntensity = doubleOrDefault(forKey: SettingsKeys.intensity, defaultValue: defaultIntensity)
        let legacyDeadZone = doubleOrDefault(forKey: SettingsKeys.deadZone, defaultValue: defaultDeadZone)
        var legacyWarningMode = WarningMode.blur
        var legacyWarningColor = WarningDefaults.color
        var legacyWarningOnsetDelay = defaultWarningOnsetDelay
        var legacyDetectionMode = DetectionMode.balanced

        if let modeString = defaults.string(forKey: SettingsKeys.warningMode),
           let mode = WarningMode(rawValue: modeString) {
            legacyWarningMode = mode
        }
        if let colorData = defaults.data(forKey: SettingsKeys.warningColor),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            legacyWarningColor = color
        }
        legacyWarningOnsetDelay = doubleOrDefault(forKey: SettingsKeys.warningOnsetDelay, defaultValue: defaultWarningOnsetDelay)
        if let modeString = defaults.string(forKey: SettingsKeys.detectionMode),
           let mode = DetectionMode(rawValue: modeString) {
            legacyDetectionMode = mode
        }

        let defaultProfile = SettingsProfile(
            id: UUID().uuidString,
            name: "Default",
            warningMode: legacyWarningMode,
            warningColorData: SettingsProfile.encodedColorData(from: legacyWarningColor),
            deadZone: legacyDeadZone,
            intensity: legacyIntensity,
            warningOnsetDelay: legacyWarningOnsetDelay,
            detectionMode: legacyDetectionMode
        )
        settingsProfiles = [defaultProfile]
        currentSettingsProfileID = defaultProfile.id
        saveProfiles()
        if defaults.object(forKey: SettingsKeys.intensity) != nil
            || defaults.object(forKey: SettingsKeys.deadZone) != nil
            || defaults.object(forKey: SettingsKeys.warningMode) != nil
            || defaults.object(forKey: SettingsKeys.warningColor) != nil
            || defaults.object(forKey: SettingsKeys.warningOnsetDelay) != nil
            || defaults.object(forKey: SettingsKeys.detectionMode) != nil {
            clearLegacyProfileKeys()
        }
    }

    func ensureProfilesLoaded() {
        if settingsProfiles.isEmpty {
            loadProfiles()
        }
    }

    func profilesState() -> (profiles: [SettingsProfile], selectedID: String?) {
        (settingsProfiles, currentSettingsProfileID)
    }

    func updateActiveProfile(
        warningMode: WarningMode? = nil,
        warningColor: NSColor? = nil,
        deadZone: Double? = nil,
        intensity: Double? = nil,
        warningOnsetDelay: Double? = nil,
        detectionMode: DetectionMode? = nil
    ) {
        guard let profileID = currentSettingsProfileID,
              let index = settingsProfiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }
        var profile = settingsProfiles[index]
        if let warningMode = warningMode {
            profile.warningMode = warningMode
        }
        if let warningColor = warningColor {
            profile.warningColorData = SettingsProfile.encodedColorData(from: warningColor)
        }
        if let deadZone = deadZone {
            profile.deadZone = deadZone
        }
        if let intensity = intensity {
            profile.intensity = intensity
        }
        if let warningOnsetDelay = warningOnsetDelay {
            profile.warningOnsetDelay = warningOnsetDelay
        }
        if let detectionMode = detectionMode {
            profile.detectionMode = detectionMode
        }
        settingsProfiles[index] = profile
        saveProfiles()
    }

    func selectProfile(id: String) -> SettingsProfile? {
        guard let profile = settingsProfiles.first(where: { $0.id == id }) else { return nil }
        currentSettingsProfileID = id
        saveProfiles()
        return profile
    }

    func createProfile(
        named name: String,
        warningMode: WarningMode,
        warningColor: NSColor,
        deadZone: Double,
        intensity: Double,
        warningOnsetDelay: Double,
        detectionMode: DetectionMode
    ) -> SettingsProfile {
        let uniqueName = uniqueProfileName(for: name)
        let profile = SettingsProfile(
            id: UUID().uuidString,
            name: uniqueName,
            warningMode: warningMode,
            warningColorData: SettingsProfile.encodedColorData(from: warningColor),
            deadZone: deadZone,
            intensity: intensity,
            warningOnsetDelay: warningOnsetDelay,
            detectionMode: detectionMode
        )
        settingsProfiles.append(profile)
        currentSettingsProfileID = profile.id
        saveProfiles()
        return profile
    }

    func canDeleteProfile(id: String) -> Bool {
        guard settingsProfiles.count > 1 else { return false }
        guard let profile = settingsProfiles.first(where: { $0.id == id }) else { return false }
        return profile.name != "Default"
    }

    func deleteProfile(id: String) -> Bool {
        guard canDeleteProfile(id: id) else { return false }
        guard let index = settingsProfiles.firstIndex(where: { $0.id == id }) else { return false }

        settingsProfiles.remove(at: index)

        // If we deleted the current profile, switch to another
        if currentSettingsProfileID == id {
            currentSettingsProfileID = settingsProfiles.first?.id
        }

        saveProfiles()
        return true
    }

    private func uniqueProfileName(for name: String) -> String {
        let existingNames = Set(settingsProfiles.map { $0.name })
        if !existingNames.contains(name) {
            return name
        }
        var index = 2
        while existingNames.contains("\(name) \(index)") {
            index += 1
        }
        return "\(name) \(index)"
    }

    private func saveProfiles() {
        let defaults = userDefaults
        if let data = try? JSONEncoder().encode(settingsProfiles) {
            defaults.set(data, forKey: SettingsKeys.settingsProfiles)
        }
        if let profileID = currentSettingsProfileID {
            defaults.set(profileID, forKey: SettingsKeys.currentSettingsProfileID)
        }
    }

    private func doubleOrDefault(forKey key: String, defaultValue: Double) -> Double {
        guard userDefaults.object(forKey: key) != nil else { return defaultValue }
        return userDefaults.double(forKey: key)
    }

    private func clearLegacyProfileKeys() {
        userDefaults.removeObject(forKey: SettingsKeys.intensity)
        userDefaults.removeObject(forKey: SettingsKeys.deadZone)
        userDefaults.removeObject(forKey: SettingsKeys.warningMode)
        userDefaults.removeObject(forKey: SettingsKeys.warningColor)
        userDefaults.removeObject(forKey: SettingsKeys.warningOnsetDelay)
        userDefaults.removeObject(forKey: SettingsKeys.detectionMode)
    }
}
