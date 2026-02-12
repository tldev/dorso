import AppKit
import XCTest
@testable import PosturrCore

@MainActor
final class SettingsProfileManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsProfileManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMigratesLegacySettingsToDefaultProfileAndClearsLegacyKeys() throws {
        let legacyIntensity = 0.65
        let legacyDeadZone = 0.15
        let legacyWarningOnsetDelay = 4.0
        let legacyWarningMode = WarningMode.border
        let legacyWarningColor = NSColor.systemOrange
        let legacyDetectionMode = DetectionMode.performance

        defaults.set(legacyIntensity, forKey: SettingsKeys.intensity)
        defaults.set(legacyDeadZone, forKey: SettingsKeys.deadZone)
        defaults.set(legacyWarningOnsetDelay, forKey: SettingsKeys.warningOnsetDelay)
        defaults.set(legacyWarningMode.rawValue, forKey: SettingsKeys.warningMode)
        defaults.set(legacyDetectionMode.rawValue, forKey: SettingsKeys.detectionMode)
        let legacyColorData = try NSKeyedArchiver.archivedData(withRootObject: legacyWarningColor, requiringSecureCoding: false)
        defaults.set(legacyColorData, forKey: SettingsKeys.warningColor)

        let manager = SettingsProfileManager(userDefaults: defaults)
        manager.loadProfiles()

        XCTAssertEqual(manager.settingsProfiles.count, 1)
        guard let profile = manager.activeProfile else {
            XCTFail("Expected active profile after migration")
            return
        }
        XCTAssertEqual(profile.name, "Default")
        XCTAssertEqual(profile.intensity, legacyIntensity)
        XCTAssertEqual(profile.deadZone, legacyDeadZone)
        XCTAssertEqual(profile.warningOnsetDelay, legacyWarningOnsetDelay)
        XCTAssertEqual(profile.warningMode, legacyWarningMode)
        XCTAssertEqual(profile.detectionMode, legacyDetectionMode)
        XCTAssertEqual(profile.warningColor, legacyWarningColor)

        XCTAssertNil(defaults.object(forKey: SettingsKeys.intensity))
        XCTAssertNil(defaults.object(forKey: SettingsKeys.deadZone))
        XCTAssertNil(defaults.object(forKey: SettingsKeys.warningMode))
        XCTAssertNil(defaults.object(forKey: SettingsKeys.warningColor))
        XCTAssertNil(defaults.object(forKey: SettingsKeys.warningOnsetDelay))
        XCTAssertNil(defaults.object(forKey: SettingsKeys.detectionMode))

        let data = try XCTUnwrap(defaults.data(forKey: SettingsKeys.settingsProfiles))
        let decoded = try JSONDecoder().decode([SettingsProfile].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0], profile)
    }

    func testLoadsSavedProfilesAndRespectsSavedSelection() throws {
        let first = SettingsProfile(
            id: UUID().uuidString,
            name: "Default",
            warningMode: .blur,
            warningColorData: SettingsProfile.encodedColorData(from: .systemRed),
            deadZone: 0.03,
            intensity: 0.35,
            warningOnsetDelay: 0.0,
            detectionMode: .balanced
        )
        let second = SettingsProfile(
            id: UUID().uuidString,
            name: "Work",
            warningMode: .glow,
            warningColorData: SettingsProfile.encodedColorData(from: .systemBlue),
            deadZone: 0.15,
            intensity: 1.2,
            warningOnsetDelay: 2.0,
            detectionMode: .responsive
        )
        defaults.set(try JSONEncoder().encode([first, second]), forKey: SettingsKeys.settingsProfiles)
        defaults.set(second.id, forKey: SettingsKeys.currentSettingsProfileID)

        let manager = SettingsProfileManager(userDefaults: defaults)
        manager.loadProfiles()

        XCTAssertEqual(manager.settingsProfiles.count, 2)
        XCTAssertEqual(manager.activeProfile?.id, second.id)
        XCTAssertEqual(manager.activeProfile?.name, "Work")
        XCTAssertEqual(manager.activeProfile?.warningMode, .glow)
    }

    func testCreateProfileEnsuresUniqueNames() {
        let manager = SettingsProfileManager(userDefaults: defaults)
        manager.loadProfiles()

        let a = manager.createProfile(
            named: "Work",
            warningMode: .blur,
            warningColor: .systemRed,
            deadZone: 0.03,
            intensity: 0.35,
            warningOnsetDelay: 0.0,
            detectionMode: .balanced
        )
        let b = manager.createProfile(
            named: "Work",
            warningMode: .blur,
            warningColor: .systemRed,
            deadZone: 0.03,
            intensity: 0.35,
            warningOnsetDelay: 0.0,
            detectionMode: .balanced
        )

        XCTAssertEqual(a.name, "Work")
        XCTAssertEqual(b.name, "Work 2")
    }

    func testDeletingActiveProfileSelectsFallbackAndPreventsDeletingDefault() {
        let manager = SettingsProfileManager(userDefaults: defaults)
        manager.loadProfiles()

        let created = manager.createProfile(
            named: "Work",
            warningMode: .blur,
            warningColor: .systemRed,
            deadZone: 0.03,
            intensity: 0.35,
            warningOnsetDelay: 0.0,
            detectionMode: .balanced
        )

        XCTAssertEqual(manager.activeProfile?.id, created.id)
        XCTAssertTrue(manager.deleteProfile(id: created.id))
        XCTAssertEqual(manager.settingsProfiles.count, 1)
        XCTAssertEqual(manager.activeProfile?.name, "Default")

        let defaultID = manager.settingsProfiles[0].id
        XCTAssertFalse(manager.canDeleteProfile(id: defaultID))
        XCTAssertFalse(manager.deleteProfile(id: defaultID))
    }
}

