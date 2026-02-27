import XCTest
@testable import DorsoCore

final class PostureEngineTransitionTests: XCTestCase {

    // MARK: - canTransition: Allowed Transitions

    func testCanTransitionFromDisabledToMonitoring() {
        XCTAssertTrue(PostureEngine.canTransition(from: .disabled, to: .monitoring()))
    }

    func testCanTransitionFromDisabledToPausedNoProfile() {
        XCTAssertTrue(PostureEngine.canTransition(from: .disabled, to: .paused(.noProfile)))
    }

    func testCanTransitionFromDisabledToCalibrating() {
        XCTAssertTrue(PostureEngine.canTransition(from: .disabled, to: .calibrating()))
    }

    func testCanTransitionFromMonitoringToDisabled() {
        XCTAssertTrue(PostureEngine.canTransition(from: .monitoring(), to: .disabled))
    }

    func testCanTransitionFromMonitoringToPausedScreenLocked() {
        XCTAssertTrue(PostureEngine.canTransition(from: .monitoring(), to: .paused(.screenLocked)))
    }

    func testCanTransitionFromMonitoringToCalibrating() {
        XCTAssertTrue(PostureEngine.canTransition(from: .monitoring(), to: .calibrating()))
    }

    func testCanTransitionFromPausedNoProfileToDisabled() {
        XCTAssertTrue(PostureEngine.canTransition(from: .paused(.noProfile), to: .disabled))
    }

    func testCanTransitionFromPausedNoProfileToMonitoring() {
        XCTAssertTrue(PostureEngine.canTransition(from: .paused(.noProfile), to: .monitoring()))
    }

    func testCanTransitionFromPausedNoProfileToCalibrating() {
        XCTAssertTrue(PostureEngine.canTransition(from: .paused(.noProfile), to: .calibrating()))
    }

    func testCanTransitionFromCalibratingToMonitoring() {
        XCTAssertTrue(PostureEngine.canTransition(from: .calibrating(), to: .monitoring()))
    }

    func testCanTransitionFromCalibratingToPausedNoProfile() {
        XCTAssertTrue(PostureEngine.canTransition(from: .calibrating(), to: .paused(.noProfile)))
    }

    func testCanTransitionFromCalibratingToDisabled() {
        XCTAssertTrue(PostureEngine.canTransition(from: .calibrating(), to: .disabled))
    }

    // MARK: - canTransition: Same State (disallowed for non-paused)

    func testCannotTransitionDisabledToDisabled() {
        XCTAssertFalse(PostureEngine.canTransition(from: .disabled, to: .disabled))
    }

    func testCannotTransitionMonitoringToMonitoring() {
        XCTAssertFalse(PostureEngine.canTransition(from: .monitoring(), to: .monitoring()))
    }

    func testCannotTransitionCalibratingToCalibrating() {
        XCTAssertFalse(PostureEngine.canTransition(from: .calibrating(), to: .calibrating()))
    }

    // MARK: - canTransition: Paused-to-Paused

    func testCanTransitionBetweenDifferentPauseReasons() {
        // (.paused, .paused) is in the explicit allowed list, so different reasons return true
        XCTAssertTrue(PostureEngine.canTransition(from: .paused(.noProfile), to: .paused(.screenLocked)))
    }

    func testCannotTransitionSamePauseReason() {
        // .paused(.noProfile) -> .paused(.noProfile) is the same state;
        // not in the explicit case list, falls to default which returns false
        XCTAssertFalse(PostureEngine.canTransition(from: .paused(.noProfile), to: .paused(.noProfile)))
    }

    // MARK: - canTransition: All PauseReason variants from monitoring

    func testCanTransitionFromMonitoringToAllPauseReasons() {
        let reasons: [PauseReason] = [.noProfile, .onTheGo, .cameraDisconnected, .screenLocked, .airPodsRemoved]
        for reason in reasons {
            XCTAssertTrue(
                PostureEngine.canTransition(from: .monitoring(), to: .paused(reason)),
                "Should allow .monitoring() -> .paused(.\(reason))"
            )
        }
    }

    func testCanTransitionFromDisabledToAllPauseReasons() {
        let reasons: [PauseReason] = [.noProfile, .onTheGo, .cameraDisconnected, .screenLocked, .airPodsRemoved]
        for reason in reasons {
            XCTAssertTrue(
                PostureEngine.canTransition(from: .disabled, to: .paused(reason)),
                "Should allow .disabled -> .paused(.\(reason))"
            )
        }
    }

    // MARK: - shouldDetectorRun: Comprehensive PauseReason Tests with Camera

    func testShouldDetectorRunPausedNoProfileCamera() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .paused(.noProfile), trackingSource: .camera))
    }

    func testShouldDetectorRunPausedOnTheGoCamera() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .paused(.onTheGo), trackingSource: .camera))
    }

    func testShouldDetectorRunPausedCameraDisconnectedCamera() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .paused(.cameraDisconnected), trackingSource: .camera))
    }

    func testShouldDetectorRunPausedScreenLockedCamera() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .paused(.screenLocked), trackingSource: .camera))
    }

    func testShouldDetectorRunPausedAirPodsRemovedCamera() {
        // Camera detector should NOT run when paused for AirPods removal
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .paused(.airPodsRemoved), trackingSource: .camera))
    }

    // MARK: - shouldDetectorRun: Comprehensive PauseReason Tests with AirPods

    func testShouldDetectorRunPausedNoProfileAirPods() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .paused(.noProfile), trackingSource: .airpods))
    }

    func testShouldDetectorRunPausedOnTheGoAirPods() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .paused(.onTheGo), trackingSource: .airpods))
    }

    func testShouldDetectorRunPausedCameraDisconnectedAirPods() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .paused(.cameraDisconnected), trackingSource: .airpods))
    }

    func testShouldDetectorRunPausedScreenLockedAirPods() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .paused(.screenLocked), trackingSource: .airpods))
    }

    func testShouldDetectorRunPausedAirPodsRemovedAirPods() {
        // Only this combination keeps the detector running
        XCTAssertTrue(PostureEngine.shouldDetectorRun(for: .paused(.airPodsRemoved), trackingSource: .airpods))
    }

    // MARK: - shouldDetectorRun: Active States

    func testShouldDetectorRunMonitoringCamera() {
        XCTAssertTrue(PostureEngine.shouldDetectorRun(for: .monitoring(), trackingSource: .camera))
    }

    func testShouldDetectorRunMonitoringAirPods() {
        XCTAssertTrue(PostureEngine.shouldDetectorRun(for: .monitoring(), trackingSource: .airpods))
    }

    func testShouldDetectorRunCalibratingCamera() {
        XCTAssertTrue(PostureEngine.shouldDetectorRun(for: .calibrating(), trackingSource: .camera))
    }

    func testShouldDetectorRunCalibratingAirPods() {
        XCTAssertTrue(PostureEngine.shouldDetectorRun(for: .calibrating(), trackingSource: .airpods))
    }

    func testShouldDetectorRunDisabledCamera() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .disabled, trackingSource: .camera))
    }

    func testShouldDetectorRunDisabledAirPods() {
        XCTAssertFalse(PostureEngine.shouldDetectorRun(for: .disabled, trackingSource: .airpods))
    }

    // MARK: - stateWhenEnabling Edge Cases

    func testStateWhenEnablingNotCalibratedAndNotAvailablePrefersNoProfile() {
        // When both not calibrated AND not available, calibration is checked first
        let state = PostureEngine.stateWhenEnabling(isCalibrated: false, detectorAvailable: false)
        XCTAssertEqual(state, .paused(.noProfile))
    }

    func testStateWhenEnablingCalibratedAndAvailableReturnsMonitoring() {
        let state = PostureEngine.stateWhenEnabling(isCalibrated: true, detectorAvailable: true)
        XCTAssertEqual(state, .monitoring())
    }

    func testStateWhenEnablingCalibratedButUnavailableReturnsCameraDisconnected() {
        let state = PostureEngine.stateWhenEnabling(isCalibrated: true, detectorAvailable: false)
        XCTAssertEqual(state, .paused(.cameraDisconnected))
    }

    func testStateWhenEnablingNotCalibratedButAvailableReturnsNoProfile() {
        let state = PostureEngine.stateWhenEnabling(isCalibrated: false, detectorAvailable: true)
        XCTAssertEqual(state, .paused(.noProfile))
    }
}
