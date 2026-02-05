import XCTest
@testable import PosturrCore

final class SettingsMigrationsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsMigrationsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAirPodsCalibrationMigratesFromLegacyKeyWhenNewKeyMissing() throws {
        let legacyCalibration = AirPodsCalibrationData(pitch: 1.0, roll: 2.0, yaw: 3.0)
        let legacyData = try JSONEncoder().encode(legacyCalibration)
        defaults.set(legacyData, forKey: SettingsKeys.legacyAirPodsProfile)

        XCTAssertNil(defaults.data(forKey: SettingsKeys.airPodsCalibration))
        SettingsMigrations.migrateLegacyKeysIfNeeded(userDefaults: defaults)

        let migratedData = try XCTUnwrap(defaults.data(forKey: SettingsKeys.airPodsCalibration))
        XCTAssertEqual(migratedData, legacyData)

        let decoded = try JSONDecoder().decode(AirPodsCalibrationData.self, from: migratedData)
        XCTAssertEqual(decoded.pitch, legacyCalibration.pitch)
        XCTAssertEqual(decoded.roll, legacyCalibration.roll)
        XCTAssertEqual(decoded.yaw, legacyCalibration.yaw)
    }

    func testAirPodsCalibrationDoesNotOverwriteWhenNewKeyAlreadyPresent() throws {
        let newCalibration = AirPodsCalibrationData(pitch: 10.0, roll: 20.0, yaw: 30.0)
        let newData = try JSONEncoder().encode(newCalibration)
        defaults.set(newData, forKey: SettingsKeys.airPodsCalibration)

        let legacyCalibration = AirPodsCalibrationData(pitch: 1.0, roll: 2.0, yaw: 3.0)
        let legacyData = try JSONEncoder().encode(legacyCalibration)
        defaults.set(legacyData, forKey: SettingsKeys.legacyAirPodsProfile)

        SettingsMigrations.migrateLegacyKeysIfNeeded(userDefaults: defaults)

        let persistedData = try XCTUnwrap(defaults.data(forKey: SettingsKeys.airPodsCalibration))
        XCTAssertEqual(persistedData, newData)
    }
}

