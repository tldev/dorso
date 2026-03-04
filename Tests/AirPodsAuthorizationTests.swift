import XCTest
import CoreMotion
import ComposableArchitecture
@testable import DorsoCore

/// Custom notification used to simulate app activation in tests.
private let testActivationNotification = NSNotification.Name("TestAppDidBecomeActive")

final class AirPodsAuthorizationTests: XCTestCase {

    private func makeDetector(statusSequence: [CMAuthorizationStatus]) -> AirPodsPostureDetector {
        let detector = AirPodsPostureDetector()
        detector.skipMotionUpdates = true
        detector.activationNotificationName = testActivationNotification
        var callCount = 0
        detector.authorizationStatusOverride = {
            callCount += 1
            let index = min(callCount - 1, statusSequence.count - 1)
            return statusSequence[index]
        }
        return detector
    }

    // MARK: - Activation observer fires completion when status changes to authorized

    @MainActor
    func testActivationObserverCallsCompletionWhenAuthorized() async {
        let detector = makeDetector(statusSequence: [.notDetermined, .authorized])

        let exp = expectation(description: "completion called with true")
        detector.requestAuthorization { authorized in
            XCTAssertTrue(authorized)
            exp.fulfill()
        }

        // Simulate the permission dialog being dismissed and the app regaining focus
        NotificationCenter.default.post(name: testActivationNotification, object: nil)

        await fulfillment(of: [exp], timeout: 1.0)
    }

    // MARK: - Activation observer fires completion when status changes to denied

    @MainActor
    func testActivationObserverCallsCompletionWhenDenied() async {
        let detector = makeDetector(statusSequence: [.notDetermined, .denied])

        let exp = expectation(description: "completion called with false")
        detector.requestAuthorization { authorized in
            XCTAssertFalse(authorized)
            exp.fulfill()
        }

        NotificationCenter.default.post(name: testActivationNotification, object: nil)

        await fulfillment(of: [exp], timeout: 1.0)
    }

    // MARK: - Completion called only once even with multiple activations

    @MainActor
    func testCompletionCalledOnlyOnce() async {
        let detector = makeDetector(statusSequence: [.notDetermined, .authorized])

        var completionCount = 0
        let exp = expectation(description: "completion called")
        detector.requestAuthorization { _ in
            completionCount += 1
            exp.fulfill()
        }

        NotificationCenter.default.post(name: testActivationNotification, object: nil)
        NotificationCenter.default.post(name: testActivationNotification, object: nil)
        NotificationCenter.default.post(name: testActivationNotification, object: nil)

        await fulfillment(of: [exp], timeout: 1.0)

        // Let any remaining async dispatches settle
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(completionCount, 1)
    }

    // MARK: - Observer removed after completion

    @MainActor
    func testObserverRemovedAfterCompletion() async {
        let detector = makeDetector(statusSequence: [.notDetermined, .authorized])

        let exp = expectation(description: "completion called")
        detector.requestAuthorization { _ in
            exp.fulfill()
        }

        NotificationCenter.default.post(name: testActivationNotification, object: nil)
        await fulfillment(of: [exp], timeout: 1.0)

        XCTAssertNil(detector.activationObserver, "Observer should be cleaned up after completion")
    }

    // MARK: - Activation while still notDetermined does not complete

    @MainActor
    func testActivationWhileStillNotDeterminedDoesNotComplete() {
        // Status stays notDetermined even after activation (user hasn't responded yet)
        let detector = makeDetector(statusSequence: [.notDetermined])

        var result: Bool?
        detector.requestAuthorization { authorized in
            result = authorized
        }

        NotificationCenter.default.post(name: testActivationNotification, object: nil)

        // Process any pending async dispatches
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertNil(result, "Should not complete while still notDetermined")
        XCTAssertNotNil(detector.activationObserver, "Observer should remain active")
    }

    // MARK: - Already authorized completes immediately

    @MainActor
    func testAlreadyAuthorizedCompletesImmediately() {
        let detector = makeDetector(statusSequence: [.authorized])

        var result: Bool?
        detector.requestAuthorization { authorized in
            result = authorized
        }

        XCTAssertEqual(result, true)
        XCTAssertNil(detector.activationObserver)
    }

    // MARK: - Already denied completes immediately

    @MainActor
    func testAlreadyDeniedCompletesImmediately() {
        let detector = makeDetector(statusSequence: [.denied])

        var result: Bool?
        detector.requestAuthorization { authorized in
            result = authorized
        }

        XCTAssertEqual(result, false)
        XCTAssertNil(detector.activationObserver)
    }

    // MARK: - State machine: authorization granted transitions AirPods to calibrating

    @MainActor
    func testCalibrationAuthorizationGrantedForAirPodsTransitionsToCalibrating() async {
        let store = TestStore(
            initialState: TrackingFeature.State(
                appState: .paused(.noProfile),
                trackingMode: .manual,
                manualSource: .airpods,
                preferredSource: .airpods,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        ) {
            TrackingFeature()
        }

        await store.send(.calibrationAuthorizationGranted) {
            $0.appState = .calibrating
        }
    }

    // MARK: - Stop cleans up activation observer

    @MainActor
    func testStopCleansUpActivationObserver() {
        let detector = makeDetector(statusSequence: [.notDetermined])
        detector.requestAuthorization { _ in }

        XCTAssertNotNil(detector.activationObserver, "Observer should be active")

        detector.stop()

        XCTAssertNil(detector.activationObserver, "Observer should be cleaned up on stop")
    }
}
