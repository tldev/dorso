import XCTest
@testable import DorsoCore

final class PostureUIStateTests: XCTestCase {

    // MARK: - Disabled State

    func testDisabledState() {
        let uiState = PostureUIState.derive(
            from: .disabled,
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.disabled"))
        XCTAssertEqual(uiState.icon, .paused)
        XCTAssertFalse(uiState.isEnabled)
        XCTAssertTrue(uiState.canRecalibrate)
    }

    // MARK: - Timed Pause

    func testTimedPauseShowsResumeTimeAndResumeAction() {
        let end = Date(timeIntervalSince1970: 1_000)
        let uiState = PostureUIState.derive(
            from: .paused(.timed(until: end)),
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        let time = DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short)
        XCTAssertEqual(uiState.statusText, L("status.pausedUntil", time))
        XCTAssertEqual(uiState.icon, .paused)
        XCTAssertTrue(uiState.isEnabled)
        XCTAssertTrue(uiState.canPause)
        XCTAssertTrue(uiState.isTimedPause)
    }

    func testOtherPausesDoNotShowResumeAction() {
        let uiState = PostureUIState.derive(
            from: .paused(.onBattery),
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertTrue(uiState.canPause)
        XCTAssertFalse(uiState.isTimedPause)
    }

    func testDisabledAndCalibratingCannotPause() {
        for appState in [AppState.disabled, .calibrating] {
            let uiState = PostureUIState.derive(
                from: appState,
                isCalibrated: true,
                isCurrentlyAway: false,
                isCurrentlySlouching: false,
                trackingSource: .camera
            )
            XCTAssertFalse(uiState.canPause, "\(appState)")
        }
    }

    // MARK: - Calibrating State

    func testCalibratingState() {
        let uiState = PostureUIState.derive(
            from: .calibrating,
            isCalibrated: false,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.calibrating"))
        XCTAssertEqual(uiState.icon, .calibrating)
        XCTAssertTrue(uiState.isEnabled)
        XCTAssertFalse(uiState.canRecalibrate)
    }

    // MARK: - Monitoring State

    func testMonitoringGoodPosture() {
        let uiState = PostureUIState.derive(
            from: .monitoring,
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.goodPosture"))
        XCTAssertEqual(uiState.icon, .good)
        XCTAssertTrue(uiState.isEnabled)
    }

    func testMonitoringBadPosture() {
        let uiState = PostureUIState.derive(
            from: .monitoring,
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: true,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.slouching"))
        XCTAssertEqual(uiState.icon, .bad)
    }

    func testMonitoringAway() {
        let uiState = PostureUIState.derive(
            from: .monitoring,
            isCalibrated: true,
            isCurrentlyAway: true,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.away"))
        XCTAssertEqual(uiState.icon, .away)
    }

    func testAwayTakesPrecedenceOverSlouching() {
        let uiState = PostureUIState.derive(
            from: .monitoring,
            isCalibrated: true,
            isCurrentlyAway: true,
            isCurrentlySlouching: true,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.away"))
        XCTAssertEqual(uiState.icon, .away)
    }

    func testMonitoringNotCalibrated() {
        let uiState = PostureUIState.derive(
            from: .monitoring,
            isCalibrated: false,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.starting"))
        XCTAssertEqual(uiState.icon, .good)
    }

    // MARK: - Paused States

    func testPausedNoProfile() {
        let uiState = PostureUIState.derive(
            from: .paused(.noProfile),
            isCalibrated: false,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.calibrationNeeded"))
        XCTAssertEqual(uiState.icon, .paused)
    }

    func testPausedOnTheGo() {
        let uiState = PostureUIState.derive(
            from: .paused(.onTheGo),
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.pausedOnTheGo"))
        XCTAssertEqual(uiState.icon, .paused)
    }

    func testPausedCameraDisconnected() {
        let uiState = PostureUIState.derive(
            from: .paused(.cameraDisconnected),
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.cameraDisconnected"))
        XCTAssertEqual(uiState.icon, .paused)
    }

    func testPausedAirPodsDisconnected() {
        let uiState = PostureUIState.derive(
            from: .paused(.cameraDisconnected),
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .airpods
        )

        XCTAssertEqual(uiState.statusText, L("status.airPodsDisconnected"))
        XCTAssertEqual(uiState.icon, .paused)
    }

    func testPausedScreenLocked() {
        let uiState = PostureUIState.derive(
            from: .paused(.screenLocked),
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.pausedScreenLocked"))
        XCTAssertEqual(uiState.icon, .paused)
    }

    func testPausedAirPodsRemoved() {
        let uiState = PostureUIState.derive(
            from: .paused(.airPodsRemoved),
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .airpods
        )

        XCTAssertEqual(uiState.statusText, L("status.pausedPutInAirPods"))
        XCTAssertEqual(uiState.icon, .paused)
    }

    func testPausedOnBattery() {
        let uiState = PostureUIState.derive(
            from: .paused(.onBattery),
            isCalibrated: true,
            isCurrentlyAway: false,
            isCurrentlySlouching: false,
            trackingSource: .camera
        )

        XCTAssertEqual(uiState.statusText, L("status.pausedOnBattery"))
        XCTAssertEqual(uiState.icon, .paused)
    }
}
