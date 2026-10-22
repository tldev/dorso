import XCTest

@testable import DorsoCore

@MainActor
final class AppDelegateDeskTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppDelegateDeskTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func profile(goodY: CGFloat, cameraID: String) -> ProfileData {
        ProfileData(
            goodPostureY: goodY, badPostureY: goodY - 0.1, neutralY: goodY - 0.05, postureRange: 0.1, cameraID: cameraID
        )
    }

    /// Desks in a throwaway defaults suite; detectors never start
    private func makeAppDelegate(cameraIDs: [String]) -> AppDelegate {
        let appDelegate = AppDelegate(userDefaults: defaults)
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.beginMonitoringSessionHandler = {}
        appDelegate.marketingModeOverride = false
        appDelegate.availableCameraIDsOverride = { cameraIDs }
        return appDelegate
    }

    private var key: String { DisplayMonitor.getCurrentConfigKey() }

    func testSwitchingDeskWhileDisabledLinesUpItsCameraAndCalibration() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin", "external"])
        appDelegate.deskStore.addDesk(named: "Home", profile: profile(goodY: 0.6, cameraID: "builtin"), forKey: key)
        let office = appDelegate.deskStore.addDesk(
            named: "Office", profile: profile(goodY: 0.8, cameraID: "external"), forKey: key)
        let home = appDelegate.deskStore.desks(forKey: key).first!
        _ = appDelegate.deskStore.selectDesk(id: home.id, forKey: key)
        appDelegate.selectedCameraID = "builtin"
        appDelegate.applyCameraCalibration(from: home.profile)
        XCTAssertEqual(appDelegate.state, .disabled)

        await appDelegate.selectDesk(id: office.id)

        XCTAssertEqual(appDelegate.selectedCameraID, "external")
        XCTAssertEqual(appDelegate.cameraCalibration?.cameraID, "external")
        XCTAssertEqual(appDelegate.cameraCalibration?.goodPostureY, 0.8)
    }

    func testSwitchingWhileDisabledToDeskWithMissingCameraClearsCalibration() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin"])
        let home = appDelegate.deskStore.addDesk(
            named: "Home", profile: profile(goodY: 0.6, cameraID: "builtin"), forKey: key)
        let office = appDelegate.deskStore.addDesk(
            named: "Office", profile: profile(goodY: 0.8, cameraID: "external"), forKey: key)
        _ = appDelegate.deskStore.selectDesk(id: home.id, forKey: key)
        appDelegate.selectedCameraID = "builtin"
        appDelegate.applyCameraCalibration(from: home.profile)

        await appDelegate.selectDesk(id: office.id)

        XCTAssertEqual(appDelegate.selectedCameraID, "builtin")
        XCTAssertNil(appDelegate.cameraCalibration)
    }

    func testSwitchingDeskNotifiesListeners() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin"])
        let home = appDelegate.deskStore.addDesk(
            named: "Home", profile: profile(goodY: 0.6, cameraID: "builtin"), forKey: key)
        appDelegate.deskStore.addDesk(named: "Uni", profile: profile(goodY: 0.8, cameraID: "builtin"), forKey: key)
        var notifications = 0
        appDelegate.onDesksChanged = { notifications += 1 }

        await appDelegate.selectDesk(id: home.id)

        XCTAssertEqual(notifications, 1)
    }

    func testDisplayChangeAppliesProfileCalibrationWhenCameraAlreadySelected() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin"])
        appDelegate.deskStore.addDesk(named: "Home", profile: profile(goodY: 0.7, cameraID: "builtin"), forKey: key)
        appDelegate.selectedCameraID = "builtin"
        appDelegate.applyCameraCalibration(from: profile(goodY: 0.5, cameraID: "builtin"))
        appDelegate.state = .monitoring

        await appDelegate.handleDisplayConfigurationChange(rebuildOverlays: false)

        XCTAssertEqual(appDelegate.cameraCalibration?.goodPostureY, 0.7)
        XCTAssertEqual(appDelegate.state, .monitoring)
    }

    /// Home on the built-in camera (active) and Office on an external one
    private func makeTwoCameraDesks(_ appDelegate: AppDelegate) -> (home: Desk, office: Desk) {
        let home = appDelegate.deskStore.addDesk(
            named: "Home", profile: profile(goodY: 0.6, cameraID: "builtin"), forKey: key)
        let office = appDelegate.deskStore.addDesk(
            named: "Office", profile: profile(goodY: 0.8, cameraID: "external"), forKey: key)
        _ = appDelegate.deskStore.selectDesk(id: home.id, forKey: key)
        appDelegate.selectedCameraID = "builtin"
        appDelegate.applyCameraCalibration(from: home.profile)
        return (home, office)
    }

    func testSwitchingDeskDuringBatteryPauseLinesUpCameraForResume() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin", "external"])
        let (_, office) = makeTwoCameraDesks(appDelegate)
        appDelegate.state = .paused(.onBattery)

        await appDelegate.selectDesk(id: office.id)

        XCTAssertEqual(appDelegate.state, .paused(.onBattery))
        XCTAssertEqual(appDelegate.selectedCameraID, "external")
        XCTAssertEqual(appDelegate.cameraCalibration?.goodPostureY, 0.8)
    }

    func testSwitchingDeskWhileCalibratingIsIgnored() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin", "external"])
        let (home, office) = makeTwoCameraDesks(appDelegate)
        appDelegate.state = .calibrating
        var notifications = 0
        appDelegate.onDesksChanged = { notifications += 1 }

        await appDelegate.selectDesk(id: office.id)

        XCTAssertEqual(appDelegate.deskStore.activeDesk(forKey: key)?.id, home.id)
        XCTAssertEqual(appDelegate.selectedCameraID, "builtin")
        XCTAssertEqual(notifications, 1)
    }

    func testPickingDeskOnCalibrationScreenLinesUpCameraAndResumes() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin", "external"])
        let (_, office) = makeTwoCameraDesks(appDelegate)
        appDelegate.state = .calibrating

        await appDelegate.finishCalibrationBySelectingDesk(id: office.id)

        XCTAssertEqual(appDelegate.deskStore.activeDesk(forKey: key)?.id, office.id)
        XCTAssertEqual(appDelegate.selectedCameraID, "external")
        XCTAssertEqual(appDelegate.cameraCalibration?.goodPostureY, 0.8)
        XCTAssertEqual(appDelegate.state, .monitoring)
    }

    func testDeletingActiveDeskSwitchesToRemainingDesk() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin", "external"])
        let (home, office) = makeTwoCameraDesks(appDelegate)

        await appDelegate.deleteDesk(id: home.id)

        XCTAssertEqual(appDelegate.deskStore.desks(forKey: key).map(\.id), [office.id])
        XCTAssertEqual(appDelegate.selectedCameraID, "external")
        XCTAssertEqual(appDelegate.cameraCalibration?.goodPostureY, 0.8)
    }

    private func cameraSamples(topY: CGFloat) -> [CalibrationSample] {
        [topY, topY, topY - 0.1, topY - 0.1].map { .camera(CameraCalibrationSample(noseY: $0, faceWidth: nil)) }
    }

    func testCalibratingAsNewDeskAddsAndActivatesIt() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin"])
        let home = appDelegate.deskStore.addDesk(
            named: "Home", profile: profile(goodY: 0.6, cameraID: "builtin"), forKey: key)
        appDelegate.selectedCameraID = "builtin"

        await appDelegate.finishCalibration(values: cameraSamples(topY: 0.8), saveAsNewDesk: true)

        let desks = appDelegate.deskStore.desks(forKey: key)
        XCTAssertEqual(desks.count, 2)
        XCTAssertEqual(desks.first(where: { $0.id == home.id })?.profile.goodPostureY, 0.6)
        XCTAssertNotEqual(appDelegate.deskStore.activeDesk(forKey: key)?.id, home.id)
        XCTAssertEqual(appDelegate.deskStore.activeProfile(forKey: key)?.goodPostureY ?? 0, 0.8, accuracy: 0.0001)
    }

    func testRecalibratingWithoutNewDeskReplacesActiveDesk() async {
        let appDelegate = makeAppDelegate(cameraIDs: ["builtin"])
        let home = appDelegate.deskStore.addDesk(
            named: "Home", profile: profile(goodY: 0.6, cameraID: "builtin"), forKey: key)
        appDelegate.selectedCameraID = "builtin"

        await appDelegate.finishCalibration(values: cameraSamples(topY: 0.8), saveAsNewDesk: false)

        XCTAssertEqual(appDelegate.deskStore.desks(forKey: key).map(\.id), [home.id])
        XCTAssertEqual(appDelegate.deskStore.activeProfile(forKey: key)?.goodPostureY ?? 0, 0.8, accuracy: 0.0001)
    }

    func testSavingSettingsWritesToInjectedDefaults() {
        let appDelegate = makeAppDelegate(cameraIDs: [])
        appDelegate.pauseOnTheGo = true

        appDelegate.saveSettings()

        XCTAssertTrue(defaults.bool(forKey: SettingsKeys.pauseOnTheGo))
    }
}
