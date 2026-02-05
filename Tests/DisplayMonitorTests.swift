import XCTest
@testable import PosturrCore

final class DisplayMonitorTests: XCTestCase {

    func testStartMonitoringRegistersOnce() {
        var registerCount = 0
        var removeCount = 0

        let monitor = DisplayMonitor(
            registerCallback: { _, _ in
                registerCount += 1
                return .success
            },
            removeCallback: { _, _ in
                removeCount += 1
                return .success
            }
        )

        monitor.startMonitoring()
        monitor.startMonitoring()

        XCTAssertEqual(registerCount, 1)
        XCTAssertEqual(removeCount, 0)
    }

    func testStopMonitoringRemovesOnce() {
        var registerCount = 0
        var removeCount = 0

        let monitor = DisplayMonitor(
            registerCallback: { _, _ in
                registerCount += 1
                return .success
            },
            removeCallback: { _, _ in
                removeCount += 1
                return .success
            }
        )

        monitor.startMonitoring()
        monitor.stopMonitoring()
        monitor.stopMonitoring()

        XCTAssertEqual(registerCount, 1)
        XCTAssertEqual(removeCount, 1)
    }

    func testFailedRegisterDoesNotRemoveOnStop() {
        var removeCount = 0

        let monitor = DisplayMonitor(
            registerCallback: { _, _ in
                return .illegalArgument
            },
            removeCallback: { _, _ in
                removeCount += 1
                return .success
            }
        )

        monitor.startMonitoring()
        monitor.stopMonitoring()

        XCTAssertEqual(removeCount, 0)
    }

    func testDeinitUnregistersCallback() {
        var removeCount = 0
        var registerCount = 0

        var monitor: DisplayMonitor? = DisplayMonitor(
            registerCallback: { _, _ in
                registerCount += 1
                return .success
            },
            removeCallback: { _, _ in
                removeCount += 1
                return .success
            }
        )

        monitor?.startMonitoring()
        XCTAssertEqual(registerCount, 1)

        monitor = nil
        XCTAssertEqual(removeCount, 1)
    }
}

