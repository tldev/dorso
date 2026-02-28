import XCTest
@testable import DorsoCore

final class TrackingParityReplayTests: XCTestCase {
    private struct Scenario {
        let name: String
        let initialState: AppState
        let trackingSource: TrackingSource
        let isCalibrated: Bool
        let detectorAvailable: Bool
        let stateBeforeLock: AppState?
        let events: [TrackingScenarioEvent]
    }

    @MainActor
    func testLegacyAndReducerParityAcrossContractTimelineMatrix() async {
        let scenarios: [Scenario] = [
            .init(
                name: "lock-monitoring-unlock",
                initialState: .monitoring,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.screenLocked, .screenUnlocked]
            ),
            .init(
                name: "lock-calibrating-unlock",
                initialState: .calibrating,
                trackingSource: .camera,
                isCalibrated: false,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.screenLocked, .screenUnlocked]
            ),
            .init(
                name: "lock-paused-no-profile-noop",
                initialState: .paused(.noProfile),
                trackingSource: .camera,
                isCalibrated: false,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.screenLocked, .screenUnlocked]
            ),
            .init(
                name: "unlock-without-state-before-lock",
                initialState: .paused(.screenLocked),
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.screenUnlocked]
            ),
            .init(
                name: "toggle-enable-camera-unavailable",
                initialState: .disabled,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: false,
                stateBeforeLock: nil,
                events: [.toggleEnabled]
            ),
            .init(
                name: "toggle-enable-airpods-unavailable",
                initialState: .disabled,
                trackingSource: .airpods,
                isCalibrated: true,
                detectorAvailable: false,
                stateBeforeLock: nil,
                events: [.toggleEnabled]
            ),
            .init(
                name: "toggle-enable-prioritizes-no-profile",
                initialState: .disabled,
                trackingSource: .airpods,
                isCalibrated: false,
                detectorAvailable: false,
                stateBeforeLock: nil,
                events: [.toggleEnabled]
            ),
            .init(
                name: "calibration-start-failure-camera",
                initialState: .calibrating,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: false,
                stateBeforeLock: nil,
                events: [.calibrationStartFailed]
            ),
            .init(
                name: "calibration-start-failure-airpods",
                initialState: .calibrating,
                trackingSource: .airpods,
                isCalibrated: true,
                detectorAvailable: false,
                stateBeforeLock: nil,
                events: [.calibrationStartFailed]
            ),
            .init(
                name: "runtime-start-failure-camera",
                initialState: .monitoring,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.runtimeDetectorStartFailed]
            ),
            .init(
                name: "runtime-start-failure-airpods",
                initialState: .monitoring,
                trackingSource: .airpods,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.runtimeDetectorStartFailed]
            ),
            .init(
                name: "calibration-denied-calibrated",
                initialState: .calibrating,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.calibrationAuthorizationDenied]
            ),
            .init(
                name: "calibration-denied-uncalibrated",
                initialState: .calibrating,
                trackingSource: .camera,
                isCalibrated: false,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.calibrationAuthorizationDenied]
            ),
            .init(
                name: "calibration-granted",
                initialState: .paused(.noProfile),
                trackingSource: .camera,
                isCalibrated: false,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.calibrationAuthorizationGranted]
            ),
            .init(
                name: "calibration-cancel-calibrated",
                initialState: .calibrating,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.calibrationCancelled]
            ),
            .init(
                name: "calibration-cancel-uncalibrated",
                initialState: .calibrating,
                trackingSource: .camera,
                isCalibrated: false,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.calibrationCancelled]
            ),
            .init(
                name: "calibration-completed",
                initialState: .calibrating,
                trackingSource: .airpods,
                isCalibrated: false,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.calibrationCompleted]
            ),
            .init(
                name: "start-monitoring-without-calibration",
                initialState: .disabled,
                trackingSource: .camera,
                isCalibrated: false,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.startMonitoringRequested(isMarketingMode: false, isConnected: true)]
            ),
            .init(
                name: "start-monitoring-airpods-disconnected",
                initialState: .disabled,
                trackingSource: .airpods,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.startMonitoringRequested(isMarketingMode: false, isConnected: false)]
            ),
            .init(
                name: "start-monitoring-connected-source",
                initialState: .disabled,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.startMonitoringRequested(isMarketingMode: false, isConnected: true)]
            ),
            .init(
                name: "start-monitoring-marketing-mode",
                initialState: .disabled,
                trackingSource: .camera,
                isCalibrated: false,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.startMonitoringRequested(isMarketingMode: true, isConnected: false)]
            ),
            .init(
                name: "airpods-disconnect-reconnect",
                initialState: .monitoring,
                trackingSource: .airpods,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.airPodsConnectionChanged(false), .airPodsConnectionChanged(true)]
            ),
            .init(
                name: "camera-selected-disconnect-fallback-profile",
                initialState: .monitoring,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [
                    .cameraDisconnected(
                        disconnectedCameraIsSelected: true,
                        hasFallbackCamera: true,
                        fallbackHasMatchingProfile: true
                    )
                ]
            ),
            .init(
                name: "camera-connect-no-match-from-disconnected",
                initialState: .paused(.cameraDisconnected),
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.cameraConnected(hasMatchingProfile: false)]
            ),
            .init(
                name: "display-change-matching-profile",
                initialState: .paused(.noProfile),
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [
                    .displayConfigurationChanged(
                        pauseOnTheGoEnabled: false,
                        isLaptopOnlyConfiguration: false,
                        hasAnyCamera: true,
                        hasMatchingProfileCamera: true,
                        selectedCameraMatchesProfile: false
                    )
                ]
            ),
            .init(
                name: "camera-selection-changed",
                initialState: .monitoring,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.cameraSelectionChanged]
            ),
            .init(
                name: "switch-source-uncalibrated",
                initialState: .monitoring,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.switchTrackingSource(to: .airpods, isCalibrated: false)]
            ),
            .init(
                name: "switch-source-calibrated",
                initialState: .paused(.noProfile),
                trackingSource: .camera,
                isCalibrated: false,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [.switchTrackingSource(to: .airpods, isCalibrated: true)]
            ),
            .init(
                name: "camera-selected-disconnect-fallback-no-profile",
                initialState: .monitoring,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [
                    .cameraDisconnected(
                        disconnectedCameraIsSelected: true,
                        hasFallbackCamera: true,
                        fallbackHasMatchingProfile: false
                    )
                ]
            ),
            .init(
                name: "camera-selected-disconnect-no-fallback",
                initialState: .monitoring,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [
                    .cameraDisconnected(
                        disconnectedCameraIsSelected: true,
                        hasFallbackCamera: false,
                        fallbackHasMatchingProfile: false
                    )
                ]
            ),
            .init(
                name: "camera-disconnect-non-selected",
                initialState: .monitoring,
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true,
                stateBeforeLock: nil,
                events: [
                    .cameraDisconnected(
                        disconnectedCameraIsSelected: false,
                        hasFallbackCamera: true,
                        fallbackHasMatchingProfile: true
                    )
                ]
            )
        ]

        for scenario in scenarios {
            await assertScenarioParity(scenario)
        }
    }

    @MainActor
    private func assertScenarioParity(
        _ scenario: Scenario,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        var legacyHarness = TrackingScenarioHarness(
            state: scenario.initialState,
            trackingSource: scenario.trackingSource,
            isCalibrated: scenario.isCalibrated,
            detectorAvailable: scenario.detectorAvailable,
            stateBeforeLock: scenario.stateBeforeLock
        )

        var reducerHarness = TrackingReducerScenarioHarness(
            state: scenario.initialState,
            trackingSource: scenario.trackingSource,
            isCalibrated: scenario.isCalibrated,
            detectorAvailable: scenario.detectorAvailable,
            stateBeforeLock: scenario.stateBeforeLock
        )

        for event in scenario.events {
            legacyHarness.send(event)
            await reducerHarness.send(event)
        }

        XCTAssertEqual(
            reducerHarness.timeline,
            legacyHarness.timeline,
            "Parity mismatch for scenario: \(scenario.name)",
            file: file,
            line: line
        )
    }
}
