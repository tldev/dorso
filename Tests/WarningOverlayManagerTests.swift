import XCTest
@testable import PosturrCore

final class WarningOverlayManagerTests: XCTestCase {

    // MARK: - Initial State Tests

    func testInitialState() {
        let manager = WarningOverlayManager()
        XCTAssertEqual(manager.currentIntensity, 0.0)
        XCTAssertEqual(manager.targetIntensity, 0.0)
        XCTAssertEqual(manager.mode, .glow)
        XCTAssertTrue(manager.windows.isEmpty)
        XCTAssertTrue(manager.overlayViews.isEmpty)
    }

    // MARK: - Mode Tests

    func testModeCanBeSetToAllValues() {
        let manager = WarningOverlayManager()
        for mode in WarningMode.allCases {
            manager.mode = mode
            XCTAssertEqual(manager.mode, mode)
        }
    }

    // MARK: - updateWarning() Ramp-Up Tests

    func testUpdateWarningRampsUpByStep() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 1.0
        manager.currentIntensity = 0.0

        manager.updateWarning()

        XCTAssertEqual(manager.currentIntensity, 0.05, accuracy: 0.0001)
    }

    func testUpdateWarningRampsUpMultipleSteps() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 1.0
        manager.currentIntensity = 0.0

        manager.updateWarning()
        XCTAssertEqual(manager.currentIntensity, 0.05, accuracy: 0.0001)

        manager.updateWarning()
        XCTAssertEqual(manager.currentIntensity, 0.10, accuracy: 0.0001)

        manager.updateWarning()
        XCTAssertEqual(manager.currentIntensity, 0.15, accuracy: 0.0001)
    }

    func testUpdateWarningDoesNotOvershootTarget() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 0.03
        manager.currentIntensity = 0.0

        manager.updateWarning()

        // Step is 0.05 but target is only 0.03, so min() should clamp it
        XCTAssertEqual(manager.currentIntensity, 0.03, accuracy: 0.0001)
    }

    func testFullRampUpCycleReachesTarget() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 1.0
        manager.currentIntensity = 0.0

        // 1.0 / 0.05 = 20 steps needed
        for _ in 0..<20 {
            manager.updateWarning()
        }

        XCTAssertEqual(manager.currentIntensity, 1.0, accuracy: 0.0001)
    }

    // MARK: - updateWarning() Ramp-Down Tests

    func testUpdateWarningRampsDownRapidly() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 0.0
        manager.currentIntensity = 1.0

        manager.updateWarning()

        // Ramps down by 0.5
        XCTAssertEqual(manager.currentIntensity, 0.5, accuracy: 0.0001)
    }

    func testUpdateWarningDoesNotUndershootTarget() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 0.0
        manager.currentIntensity = 0.3

        manager.updateWarning()

        // 0.3 - 0.5 would be -0.2, but max() should clamp to target (0.0)
        XCTAssertEqual(manager.currentIntensity, 0.0, accuracy: 0.0001)
    }

    func testRampDownToNonZeroTarget() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 0.4
        manager.currentIntensity = 1.0

        manager.updateWarning()

        // 1.0 - 0.5 = 0.5, which is still above target
        XCTAssertEqual(manager.currentIntensity, 0.5, accuracy: 0.0001)

        manager.updateWarning()

        // 0.5 - 0.5 = 0.0, but max(0.0, 0.4) = 0.4
        XCTAssertEqual(manager.currentIntensity, 0.4, accuracy: 0.0001)
    }

    // MARK: - updateWarning() No-Op Test

    func testUpdateWarningIsNoOpWhenAtTarget() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 0.5
        manager.currentIntensity = 0.5

        manager.updateWarning()

        XCTAssertEqual(manager.currentIntensity, 0.5, accuracy: 0.0001)
    }

    func testUpdateWarningIsNoOpAtZero() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 0.0
        manager.currentIntensity = 0.0

        manager.updateWarning()

        XCTAssertEqual(manager.currentIntensity, 0.0, accuracy: 0.0001)
    }

    func testUpdateWarningIsNoOpAtOne() {
        let manager = WarningOverlayManager()
        manager.targetIntensity = 1.0
        manager.currentIntensity = 1.0

        manager.updateWarning()

        XCTAssertEqual(manager.currentIntensity, 1.0, accuracy: 0.0001)
    }
}
