import XCTest
@testable import DorsoCore

final class TrackingAdapterTransitionTests: XCTestCase {
    func testCameraReconnectFlowDoesNotOverwriteRuntimeFallbackWhenStartMonitoringIntentExists() {
        let committed = TrackingAdapterTransition.committedAppState(
            currentStateAfterEffects: .paused(.noProfile),
            reducerState: .monitoring,
            effectIntents: [.switchCamera(.matchingProfile()), .startMonitoring]
        )

        XCTAssertEqual(committed, .paused(.noProfile))
    }

    func testDisplayFlowDoesNotOverwriteRuntimeFallbackWhenStartMonitoringIntentExists() {
        let committed = TrackingAdapterTransition.committedAppState(
            currentStateAfterEffects: .paused(.cameraDisconnected),
            reducerState: .monitoring,
            effectIntents: [.startMonitoring]
        )

        XCTAssertEqual(committed, .paused(.cameraDisconnected))
    }

    func testReducerStateCommitsWhenNoStartMonitoringIntentExists() {
        let committed = TrackingAdapterTransition.committedAppState(
            currentStateAfterEffects: .paused(.cameraDisconnected),
            reducerState: .paused(.noProfile),
            effectIntents: [.switchCamera(.fallback())]
        )

        XCTAssertEqual(committed, .paused(.noProfile))
    }
}
