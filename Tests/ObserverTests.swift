import XCTest

@testable import DorsoCore

// MARK: - ScreenLockObserver Tests

final class ScreenLockObserverTests: XCTestCase {

    private var observer: ScreenLockObserver!

    override func setUp() {
        super.setUp()
        observer = ScreenLockObserver()
    }

    override func tearDown() {
        observer = nil
        super.tearDown()
    }

    func testIsObservingIsFalseInitially() {
        XCTAssertFalse(observer.isObserving)
    }

    func testStartObservingSetsIsObservingTrue() {
        observer.startObserving()
        XCTAssertTrue(observer.isObserving)
    }

    func testStopObservingSetsIsObservingFalse() {
        observer.startObserving()
        observer.stopObserving()
        XCTAssertFalse(observer.isObserving)
    }

    func testStartObservingIsIdempotent() {
        var lockCount = 0
        observer.onScreenLocked = { lockCount += 1 }

        observer.startObserving()
        observer.startObserving()

        XCTAssertTrue(observer.isObserving, "Should still be observing")

        // Post a lock notification — should only fire once if not double-registered
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            deliverImmediately: true
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(lockCount, 1, "Callback should fire exactly once, proving no double registration")
    }

    func testStopObservingIsIdempotent() {
        observer.startObserving()
        observer.stopObserving()
        observer.stopObserving()

        XCTAssertFalse(observer.isObserving)
    }

    func testLockNotificationTriggersCallback() {
        let expectation = expectation(description: "onScreenLocked called")

        observer.onScreenLocked = {
            expectation.fulfill()
        }

        observer.startObserving()

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            deliverImmediately: true
        )

        waitForExpectations(timeout: 1.0)
    }

    func testUnlockNotificationTriggersCallback() {
        let expectation = expectation(description: "onScreenUnlocked called")

        observer.onScreenUnlocked = {
            expectation.fulfill()
        }

        observer.startObserving()

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            deliverImmediately: true
        )

        waitForExpectations(timeout: 1.0)
    }

    func testNotificationsDoNotFireAfterStopObserving() {
        var lockCount = 0
        var unlockCount = 0

        observer.onScreenLocked = { lockCount += 1 }
        observer.onScreenUnlocked = { unlockCount += 1 }

        observer.startObserving()
        observer.stopObserving()

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            deliverImmediately: true
        )
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            deliverImmediately: true
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertEqual(lockCount, 0, "Lock callback should not fire after stopObserving")
        XCTAssertEqual(unlockCount, 0, "Unlock callback should not fire after stopObserving")
    }

    func testSettingCallbacksAfterStartObservingWorks() {
        observer.startObserving()

        let expectation = expectation(description: "late-set callback fires")

        // Set callbacks after startObserving — they are captured weakly via self
        observer.onScreenLocked = {
            expectation.fulfill()
        }

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            deliverImmediately: true
        )

        waitForExpectations(timeout: 1.0)
    }

    func testDeinitStopsObserving() {
        var obs: ScreenLockObserver? = ScreenLockObserver()
        obs?.startObserving()
        XCTAssertTrue(obs?.isObserving == true)

        obs = nil
        // No crash or leak — deinit calls stopObserving
    }
}

// MARK: - CameraObserver Tests

final class CameraObserverTests: XCTestCase {

    private var observer: CameraObserver!

    override func setUp() {
        super.setUp()
        observer = CameraObserver()
    }

    override func tearDown() {
        observer = nil
        super.tearDown()
    }

    func testIsObservingIsFalseInitially() {
        XCTAssertFalse(observer.isObserving)
    }

    func testStartObservingSetsIsObservingTrue() {
        observer.startObserving()
        XCTAssertTrue(observer.isObserving)
    }

    func testStopObservingSetsIsObservingFalse() {
        observer.startObserving()
        observer.stopObserving()
        XCTAssertFalse(observer.isObserving)
    }

    func testStartObservingIsIdempotent() {
        observer.startObserving()
        observer.startObserving()

        XCTAssertTrue(observer.isObserving, "Should still be observing after double start")

        // Stop once should fully clean up
        observer.stopObserving()
        XCTAssertFalse(observer.isObserving)
    }

    func testStopObservingIsIdempotent() {
        observer.startObserving()
        observer.stopObserving()
        observer.stopObserving()

        XCTAssertFalse(observer.isObserving)
    }

    func testNotificationsDoNotFireAfterStopObserving() {
        var connectedCount = 0
        var disconnectedCount = 0

        observer.onCameraConnected = { _ in connectedCount += 1 }
        observer.onCameraDisconnected = { _ in disconnectedCount += 1 }

        observer.startObserving()
        observer.stopObserving()

        // Post notifications after stopping — callbacks should not fire
        NotificationCenter.default.post(
            name: NSNotification.Name.AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.post(
            name: NSNotification.Name.AVCaptureDeviceWasDisconnected,
            object: nil
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertEqual(connectedCount, 0, "Connected callback should not fire after stopObserving")
        XCTAssertEqual(disconnectedCount, 0, "Disconnected callback should not fire after stopObserving")
    }

    func testDeinitStopsObserving() {
        var obs: CameraObserver? = CameraObserver()
        obs?.startObserving()
        XCTAssertTrue(obs?.isObserving == true)

        obs = nil
        // No crash or leak — deinit calls stopObserving
    }

    func testStartStopStartCycle() {
        observer.startObserving()
        XCTAssertTrue(observer.isObserving)

        observer.stopObserving()
        XCTAssertFalse(observer.isObserving)

        observer.startObserving()
        XCTAssertTrue(observer.isObserving, "Should be able to restart after stopping")
    }
}

// MARK: - PowerSourceObserver Tests

final class PowerSourceObserverTests: XCTestCase {

    private var observer: PowerSourceObserver!

    override func setUp() {
        super.setUp()
        observer = PowerSourceObserver()
    }

    override func tearDown() {
        observer = nil
        super.tearDown()
    }

    func testIsObservingIsFalseInitially() {
        XCTAssertFalse(observer.isObserving)
    }

    func testStartObservingSetsIsObservingTrue() {
        observer.startObserving()
        XCTAssertTrue(observer.isObserving)
    }

    func testStopObservingSetsIsObservingFalse() {
        observer.startObserving()
        observer.stopObserving()
        XCTAssertFalse(observer.isObserving)
    }

    func testStartObservingIsIdempotent() {
        observer.startObserving()
        observer.startObserving()

        XCTAssertTrue(observer.isObserving, "Should still be observing after double start")

        observer.stopObserving()
        XCTAssertFalse(observer.isObserving)
    }

    func testStopObservingIsIdempotent() {
        observer.startObserving()
        observer.stopObserving()
        observer.stopObserving()

        XCTAssertFalse(observer.isObserving)
    }

    func testIsOnBatteryReflectsProvider() {
        observer.currentPowerSourceProvider = { true }
        XCTAssertTrue(observer.isOnBattery)

        observer.currentPowerSourceProvider = { false }
        XCTAssertFalse(observer.isOnBattery)
    }

    func testEvaluateFiresCallbackOnlyOnTransitions() {
        var isOnBattery = false
        observer.currentPowerSourceProvider = { isOnBattery }

        var received: [Bool] = []
        observer.onPowerSourceChanged = { received.append($0) }

        observer.startObserving()

        // Capacity-tick style notifications with no source change stay silent
        observer.evaluatePowerSource()
        observer.evaluatePowerSource()
        XCTAssertEqual(received, [])

        isOnBattery = true
        observer.evaluatePowerSource()
        observer.evaluatePowerSource()
        XCTAssertEqual(received, [true], "Repeated battery notifications should fire once")

        isOnBattery = false
        observer.evaluatePowerSource()
        XCTAssertEqual(received, [true, false])
    }

    func testDeinitStopsObserving() {
        var obs: PowerSourceObserver? = PowerSourceObserver()
        obs?.startObserving()
        XCTAssertTrue(obs?.isObserving == true)

        obs = nil
        // No crash or leak — deinit calls stopObserving
    }
}
