import XCTest
@testable import DorsoCore

@MainActor
final class DeskStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: DeskStore!
    private let key = "displays:BUILTIN"

    override func setUp() {
        super.setUp()
        suiteName = "DeskStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = DeskStore(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func profile(goodY: CGFloat, range: CGFloat = 0.1, cameraID: String = "cam") -> ProfileData {
        ProfileData(goodPostureY: goodY, badPostureY: goodY - range, neutralY: goodY - range / 2, postureRange: range, cameraID: cameraID)
    }

    private func legacyProfile(forKey key: String) -> ProfileData? {
        guard let legacy = defaults.dictionary(forKey: SettingsKeys.profiles) as? [String: Data],
              let data = legacy[key] else { return nil }
        return try? JSONDecoder().decode(ProfileData.self, from: data)
    }

    // MARK: - Legacy Adoption

    func testAdoptsLegacyCalibrationAsFirstDesk() throws {
        let legacy = profile(goodY: 0.6)
        defaults.set([key: try JSONEncoder().encode(legacy)], forKey: SettingsKeys.profiles)

        let desks = store.desks(forKey: key)

        XCTAssertEqual(desks.count, 1)
        XCTAssertEqual(desks.first?.name, L("desk.defaultName", 1))
        XCTAssertEqual(store.activeProfile(forKey: key), legacy)
        // Adoption is persisted, so the desk keeps a stable identity
        XCTAssertEqual(DeskStore(userDefaults: defaults).activeDesk(forKey: key)?.id, desks.first?.id)
    }

    func testNoDesksWithoutAnyCalibration() {
        XCTAssertTrue(store.desks(forKey: key).isEmpty)
        XCTAssertNil(store.activeProfile(forKey: key))
    }

    // MARK: - Saving Calibrations

    func testReplaceCreatesFirstDeskThenOverwritesActive() {
        store.replaceActiveCalibration(forKey: key, with: profile(goodY: 0.6))
        let firstID = store.activeDesk(forKey: key)?.id

        store.replaceActiveCalibration(forKey: key, with: profile(goodY: 0.7))

        XCTAssertEqual(store.desks(forKey: key).count, 1)
        XCTAssertEqual(store.activeDesk(forKey: key)?.id, firstID)
        XCTAssertEqual(store.activeProfile(forKey: key), profile(goodY: 0.7))
        XCTAssertEqual(legacyProfile(forKey: key), profile(goodY: 0.7))
    }

    func testAddDeskBecomesActiveAndMirrorsLegacyProfile() {
        store.replaceActiveCalibration(forKey: key, with: profile(goodY: 0.6))

        let desk = store.addDesk(named: "Uni", profile: profile(goodY: 0.8), forKey: key)

        XCTAssertEqual(store.desks(forKey: key).map(\.name), [L("desk.defaultName", 1), "Uni"])
        XCTAssertEqual(store.activeDesk(forKey: key)?.id, desk.id)
        XCTAssertEqual(legacyProfile(forKey: key), profile(goodY: 0.8))
    }

    func testAddDeskWithBlankNameUsesNextDefaultName() {
        store.replaceActiveCalibration(forKey: key, with: profile(goodY: 0.6))

        let desk = store.addDesk(named: "  ", profile: profile(goodY: 0.8), forKey: key)

        XCTAssertEqual(desk.name, L("desk.defaultName", 2))
    }

    func testAddDeskWithDuplicateNameIsMadeUnique() {
        store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)

        let desk = store.addDesk(named: "Home", profile: profile(goodY: 0.8), forKey: key)

        XCTAssertEqual(desk.name, "Home 2")
    }

    func testDesksAreScopedToDisplayConfiguration() {
        store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)
        store.addDesk(named: "Office", profile: profile(goodY: 0.7), forKey: "displays:EXTERNAL")

        XCTAssertEqual(store.desks(forKey: key).map(\.name), ["Home"])
        XCTAssertEqual(store.desks(forKey: "displays:EXTERNAL").map(\.name), ["Office"])
    }

    // MARK: - Switching

    func testSelectDeskChangesActiveCalibration() {
        let home = store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)
        store.addDesk(named: "Uni", profile: profile(goodY: 0.8), forKey: key)

        XCTAssertEqual(store.selectDesk(id: home.id, forKey: key)?.id, home.id)

        XCTAssertEqual(store.activeProfile(forKey: key), profile(goodY: 0.6))
        XCTAssertEqual(legacyProfile(forKey: key), profile(goodY: 0.6))
    }

    func testSelectUnknownDeskIsRejected() {
        store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)
        XCTAssertNil(store.selectDesk(id: "missing", forKey: key))
    }

    // MARK: - Renaming

    func testRenameDesk() {
        let desk = store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)

        XCTAssertTrue(store.renameDesk(id: desk.id, to: "  Kitchen  ", forKey: key))

        XCTAssertEqual(store.desks(forKey: key).first?.name, "Kitchen")
    }

    func testRenameRejectsEmptyAndDuplicateNames() {
        let home = store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)
        store.addDesk(named: "Uni", profile: profile(goodY: 0.8), forKey: key)

        XCTAssertFalse(store.renameDesk(id: home.id, to: "   ", forKey: key))
        XCTAssertFalse(store.renameDesk(id: home.id, to: "Uni", forKey: key))
        XCTAssertEqual(store.desks(forKey: key).first?.name, "Home")
    }

    func testRenameToOwnNameSucceeds() {
        let home = store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)
        XCTAssertTrue(store.renameDesk(id: home.id, to: "Home", forKey: key))
    }

    // MARK: - Deleting

    func testCannotDeleteLastDesk() {
        let desk = store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)

        XCTAssertFalse(store.canDeleteDesk(forKey: key))
        XCTAssertFalse(store.deleteDesk(id: desk.id, forKey: key))
        XCTAssertEqual(store.desks(forKey: key).count, 1)
    }

    func testDeletingActiveDeskActivatesFirstRemaining() {
        let home = store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)
        let uni = store.addDesk(named: "Uni", profile: profile(goodY: 0.8), forKey: key)

        XCTAssertTrue(store.deleteDesk(id: uni.id, forKey: key))

        XCTAssertEqual(store.activeDesk(forKey: key)?.id, home.id)
        XCTAssertEqual(legacyProfile(forKey: key), profile(goodY: 0.6))
    }

    func testDeletingInactiveDeskKeepsActive() {
        let home = store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)
        let uni = store.addDesk(named: "Uni", profile: profile(goodY: 0.8), forKey: key)

        XCTAssertTrue(store.deleteDesk(id: home.id, forKey: key))

        XCTAssertEqual(store.activeDesk(forKey: key)?.id, uni.id)
    }

    // MARK: - Resilience

    private func storedSets() -> [String: Data] {
        defaults.dictionary(forKey: SettingsKeys.desks) as? [String: Data] ?? [:]
    }

    private func injectUnreadableEntry(forKey key: String) -> Data {
        let garbage = Data("from a newer build".utf8)
        var stored = storedSets()
        stored[key] = garbage
        defaults.set(stored, forKey: SettingsKeys.desks)
        return garbage
    }

    func testUnreadableEntryDoesNotAffectOtherDisplaySetups() {
        store.addDesk(named: "Office", profile: profile(goodY: 0.7), forKey: "displays:EXTERNAL")
        let garbage = injectUnreadableEntry(forKey: key)
        let reloaded = DeskStore(userDefaults: defaults)

        XCTAssertEqual(reloaded.desks(forKey: "displays:EXTERNAL").map(\.name), ["Office"])
        let office = reloaded.activeDesk(forKey: "displays:EXTERNAL")!
        XCTAssertTrue(reloaded.renameDesk(id: office.id, to: "HQ", forKey: "displays:EXTERNAL"))

        XCTAssertEqual(storedSets()[key], garbage)
    }

    func testUnreadableEntryFallsBackToLegacyCalibrationWithoutOverwriting() throws {
        let legacy = profile(goodY: 0.6)
        defaults.set([key: try JSONEncoder().encode(legacy)], forKey: SettingsKeys.profiles)
        let garbage = injectUnreadableEntry(forKey: key)

        XCTAssertEqual(store.activeProfile(forKey: key), legacy)
        XCTAssertEqual(storedSets()[key], garbage)
    }

    func testChangingAnUnreadableSetupReplacesIt() {
        _ = injectUnreadableEntry(forKey: key)

        store.replaceActiveCalibration(forKey: key, with: profile(goodY: 0.65))

        XCTAssertEqual(DeskStore(userDefaults: defaults).activeProfile(forKey: key), profile(goodY: 0.65))
    }

    func testCalibrationFromOlderBuildUpdatesActiveDesk() throws {
        let home = store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)
        let uni = store.addDesk(named: "Uni", profile: profile(goodY: 0.8), forKey: key)

        // An older build recalibrates after a downgrade; it only knows `profiles`
        let newer = profile(goodY: 0.75)
        defaults.set([key: try JSONEncoder().encode(newer)], forKey: SettingsKeys.profiles)
        let reloaded = DeskStore(userDefaults: defaults)

        XCTAssertEqual(reloaded.desks(forKey: key).count, 2)
        XCTAssertEqual(reloaded.activeDesk(forKey: key)?.id, uni.id)
        XCTAssertEqual(reloaded.activeProfile(forKey: key), newer)
        XCTAssertEqual(reloaded.desks(forKey: key).first(where: { $0.id == home.id })?.profile, profile(goodY: 0.6))
    }

    func testFieldsFromNewerBuildSurviveChangesToOtherSetups() {
        let newer = Data("""
        {"activeDeskID":"o","desks":[{"id":"o","name":"Office","icon":"building",\
        "profile":{"goodPostureY":0.7,"badPostureY":0.6,"neutralY":0.65,"postureRange":0.1,"cameraID":"cam"}}],"version":2}
        """.utf8)
        defaults.set(["displays:EXTERNAL": newer], forKey: SettingsKeys.desks)

        XCTAssertEqual(store.desks(forKey: "displays:EXTERNAL").map(\.name), ["Office"])
        store.addDesk(named: "Home", profile: profile(goodY: 0.6), forKey: key)

        XCTAssertEqual(storedSets()["displays:EXTERNAL"], newer)
    }

    func testStandInForUnreadableEntryKeepsItsIdentity() throws {
        defaults.set([key: try JSONEncoder().encode(profile(goodY: 0.6))], forKey: SettingsKeys.profiles)
        _ = injectUnreadableEntry(forKey: key)

        let first = store.activeDesk(forKey: key)?.id
        XCTAssertNotNil(first)
        XCTAssertEqual(DeskStore(userDefaults: defaults).activeDesk(forKey: key)?.id, first)
    }
}
