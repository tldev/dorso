import XCTest
@testable import DorsoCore

final class TrackingCharacterizationTests: XCTestCase {

    func testLockWhileMonitoringUnlockRestoresMonitoringTimeline() {
        var harness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(.screenLocked)
        harness.send(.screenUnlocked)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.monitoring, .paused(.screenLocked), .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.stateBeforeLock),
            [nil, .monitoring, nil]
        )
        XCTAssertEqual(
            harness.timeline.map(\.detectorShouldRun),
            [true, false, true]
        )
        XCTAssertEqual(harness.timeline.last?.restartMonitoringRequested, true)
    }

    func testLockWhileCalibratingUnlockRestoresCalibratingTimeline() {
        var harness = TrackingScenarioHarness(
            state: .calibrating,
            trackingSource: .camera,
            isCalibrated: false,
            detectorAvailable: true
        )

        harness.send(.screenLocked)
        harness.send(.screenUnlocked)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.calibrating, .paused(.screenLocked), .calibrating]
        )
        XCTAssertEqual(
            harness.timeline.map(\.stateBeforeLock),
            [nil, .calibrating, nil]
        )
        XCTAssertEqual(
            harness.timeline.map(\.detectorShouldRun),
            [true, false, true]
        )
        XCTAssertEqual(harness.timeline.last?.restartMonitoringRequested, false)
    }

    func testLockWhilePausedNoProfileDoesNotChangeStateTimeline() {
        var harness = TrackingScenarioHarness(
            state: .paused(.noProfile),
            trackingSource: .camera,
            isCalibrated: false,
            detectorAvailable: true
        )

        harness.send(.screenLocked)
        harness.send(.screenUnlocked)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.paused(.noProfile), .paused(.noProfile), .paused(.noProfile)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.stateBeforeLock),
            [nil, nil, nil]
        )
        XCTAssertEqual(
            harness.timeline.map(\.detectorShouldRun),
            [false, false, false]
        )
    }

    func testUnlockWithoutCapturedStateRemainsScreenLocked() {
        var harness = TrackingScenarioHarness(
            state: .paused(.screenLocked),
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true,
            stateBeforeLock: nil
        )

        harness.send(.screenUnlocked)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.paused(.screenLocked), .paused(.screenLocked)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.stateBeforeLock),
            [nil, nil]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, false]
        )
    }

    func testEnableFromDisabledUsesSourceSpecificUnavailabilityReason() {
        var cameraHarness = TrackingScenarioHarness(
            state: .disabled,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: false
        )
        cameraHarness.send(.toggleEnabled)

        var airPodsHarness = TrackingScenarioHarness(
            state: .disabled,
            trackingSource: .airpods,
            isCalibrated: true,
            detectorAvailable: false
        )
        airPodsHarness.send(.toggleEnabled)

        XCTAssertEqual(
            cameraHarness.timeline.map(\.state),
            [.disabled, .paused(.cameraDisconnected)]
        )
        XCTAssertEqual(
            airPodsHarness.timeline.map(\.state),
            [.disabled, .paused(.airPodsRemoved)]
        )
    }

    func testCalibrationStartFailureUsesSourceSpecificUnavailabilityReason() {
        var cameraHarness = TrackingScenarioHarness(
            state: .calibrating,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: false
        )
        cameraHarness.send(.calibrationStartFailed)

        var airPodsHarness = TrackingScenarioHarness(
            state: .calibrating,
            trackingSource: .airpods,
            isCalibrated: true,
            detectorAvailable: false
        )
        airPodsHarness.send(.calibrationStartFailed)

        XCTAssertEqual(
            cameraHarness.timeline.map(\.state),
            [.calibrating, .paused(.cameraDisconnected)]
        )
        XCTAssertEqual(
            airPodsHarness.timeline.map(\.state),
            [.calibrating, .paused(.airPodsRemoved)]
        )
    }

    func testRuntimeDetectorStartFailureUsesSourceSpecificUnavailabilityReason() {
        var cameraHarness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )
        cameraHarness.send(.runtimeDetectorStartFailed)

        var airPodsHarness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .airpods,
            isCalibrated: true,
            detectorAvailable: true
        )
        airPodsHarness.send(.runtimeDetectorStartFailed)

        XCTAssertEqual(
            cameraHarness.timeline.map(\.state),
            [.monitoring, .paused(.cameraDisconnected)]
        )
        XCTAssertEqual(
            airPodsHarness.timeline.map(\.state),
            [.monitoring, .paused(.airPodsRemoved)]
        )
    }

    func testCalibrationAuthorizationDeniedReturnsMonitoringWhenCalibratedElseNoProfile() {
        var calibratedHarness = TrackingScenarioHarness(
            state: .calibrating,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )
        calibratedHarness.send(.calibrationAuthorizationDenied)

        var uncalibratedHarness = TrackingScenarioHarness(
            state: .calibrating,
            trackingSource: .camera,
            isCalibrated: false,
            detectorAvailable: true
        )
        uncalibratedHarness.send(.calibrationAuthorizationDenied)

        XCTAssertEqual(
            calibratedHarness.timeline.map(\.state),
            [.calibrating, .monitoring]
        )
        XCTAssertEqual(
            uncalibratedHarness.timeline.map(\.state),
            [.calibrating, .paused(.noProfile)]
        )
    }

    func testCalibrationAuthorizationGrantedTransitionsToCalibrating() {
        var harness = TrackingScenarioHarness(
            state: .paused(.noProfile),
            trackingSource: .camera,
            isCalibrated: false,
            detectorAvailable: true
        )

        harness.send(.calibrationAuthorizationGranted)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.paused(.noProfile), .calibrating]
        )
    }

    func testCalibrationCancelReturnsMonitoringWhenCalibratedAndRequestsRestart() {
        var harness = TrackingScenarioHarness(
            state: .calibrating,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(.calibrationCancelled)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.calibrating, .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, true]
        )
    }

    func testCalibrationCancelReturnsNoProfileWhenNotCalibrated() {
        var harness = TrackingScenarioHarness(
            state: .calibrating,
            trackingSource: .camera,
            isCalibrated: false,
            detectorAvailable: true
        )

        harness.send(.calibrationCancelled)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.calibrating, .paused(.noProfile)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, false]
        )
    }

    func testCalibrationCompletionResetsRuntimeAndRequestsMonitoringRestart() {
        var harness = TrackingScenarioHarness(
            state: .calibrating,
            trackingSource: .airpods,
            isCalibrated: false,
            detectorAvailable: true
        )

        harness.send(.calibrationCompleted)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.calibrating, .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.resetMonitoringRequested),
            [false, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, true]
        )
    }

    func testStartMonitoringWithoutCalibrationPausesNoProfileAndDoesNotBeginSession() {
        var harness = TrackingScenarioHarness(
            state: .disabled,
            trackingSource: .camera,
            isCalibrated: false,
            detectorAvailable: true
        )

        harness.send(.startMonitoringRequested(isMarketingMode: false, isConnected: true))

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.disabled, .paused(.noProfile)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.beginMonitoringRequested),
            [false, false]
        )
    }

    func testStartMonitoringForDisconnectedAirPodsPausesRemovedAndBeginsSession() {
        var harness = TrackingScenarioHarness(
            state: .disabled,
            trackingSource: .airpods,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(.startMonitoringRequested(isMarketingMode: false, isConnected: false))

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.disabled, .paused(.airPodsRemoved)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.beginMonitoringRequested),
            [false, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.detectorShouldRun),
            [false, true]
        )
    }

    func testStartMonitoringForConnectedSourceBeginsSessionAndMonitors() {
        var harness = TrackingScenarioHarness(
            state: .disabled,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(.startMonitoringRequested(isMarketingMode: false, isConnected: true))

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.disabled, .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.beginMonitoringRequested),
            [false, true]
        )
    }

    func testStartMonitoringInMarketingModeMonitorsWithoutBeginningSession() {
        var harness = TrackingScenarioHarness(
            state: .disabled,
            trackingSource: .camera,
            isCalibrated: false,
            detectorAvailable: true
        )

        harness.send(.startMonitoringRequested(isMarketingMode: true, isConnected: false))

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.disabled, .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.beginMonitoringRequested),
            [false, false]
        )
    }

    func testEnablePrioritizesNoProfileBeforeSourceUnavailability() {
        var harness = TrackingScenarioHarness(
            state: .disabled,
            trackingSource: .airpods,
            isCalibrated: false,
            detectorAvailable: false
        )
        harness.send(.toggleEnabled)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.disabled, .paused(.noProfile)]
        )
    }

    func testAirPodsDisconnectThenReconnectTimeline() {
        var harness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .airpods,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(.airPodsConnectionChanged(false))
        harness.send(.airPodsConnectionChanged(true))

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.monitoring, .paused(.airPodsRemoved), .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.detectorShouldRun),
            [true, true, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, false, true]
        )
    }

    func testCameraSelectedDisconnectWithFallbackProfileKeepsMonitoringAndRequestsSwitchAndRestart() {
        var harness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(
            .cameraDisconnected(
                disconnectedCameraIsSelected: true,
                hasFallbackCamera: true,
                fallbackHasMatchingProfile: true
            )
        )

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.monitoring, .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.fallbackSwitchRequested),
            [false, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, true]
        )
    }

    func testCameraConnectWithoutMatchingProfileFromDisconnectedBecomesNoProfile() {
        var harness = TrackingScenarioHarness(
            state: .paused(.cameraDisconnected),
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(.cameraConnected(hasMatchingProfile: false))

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.paused(.cameraDisconnected), .paused(.noProfile)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, false]
        )
    }

    func testDisplayChangeWithMatchingProfileRequestsSwitchAndMonitoring() {
        var harness = TrackingScenarioHarness(
            state: .paused(.noProfile),
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(
            .displayConfigurationChanged(
                pauseOnTheGoEnabled: false,
                isLaptopOnlyConfiguration: false,
                hasAnyCamera: true,
                hasMatchingProfileCamera: true,
                selectedCameraMatchesProfile: false
            )
        )

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.paused(.noProfile), .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.selectedCameraSwitchRequested),
            [false, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, true]
        )
    }

    func testCameraSelectionChangePausesNoProfileAndRequestsSwitch() {
        var harness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(.cameraSelectionChanged)

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.monitoring, .paused(.noProfile)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.selectedCameraSwitchRequested),
            [false, true]
        )
    }

    func testManualSourceSwitchToUncalibratedSourcePausesNoProfileAndPersistsSource() {
        var harness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(.switchTrackingSource(to: .airpods, isCalibrated: false))

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.monitoring, .paused(.noProfile)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.trackingSource),
            [.camera, .airpods]
        )
        XCTAssertEqual(
            harness.timeline.map(\.stopDetectorRequested),
            [false, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.persistSourceRequested),
            [false, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, false]
        )
    }

    func testManualSourceSwitchToCalibratedSourceRequestsMonitoringRestart() {
        var harness = TrackingScenarioHarness(
            state: .paused(.noProfile),
            trackingSource: .camera,
            isCalibrated: false,
            detectorAvailable: true
        )

        harness.send(.switchTrackingSource(to: .airpods, isCalibrated: true))

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.paused(.noProfile), .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.trackingSource),
            [.camera, .airpods]
        )
        XCTAssertEqual(
            harness.timeline.map(\.stopDetectorRequested),
            [false, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.persistSourceRequested),
            [false, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, true]
        )
    }

    func testCameraSelectedDisconnectWithFallbackNoProfilePausesNoProfileAndRequestsSwitchOnly() {
        var harness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(
            .cameraDisconnected(
                disconnectedCameraIsSelected: true,
                hasFallbackCamera: true,
                fallbackHasMatchingProfile: false
            )
        )

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.monitoring, .paused(.noProfile)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.fallbackSwitchRequested),
            [false, true]
        )
        XCTAssertEqual(
            harness.timeline.map(\.startMonitoringRequested),
            [false, false]
        )
    }

    func testCameraSelectedDisconnectWithoutFallbackPausesDisconnected() {
        var harness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(
            .cameraDisconnected(
                disconnectedCameraIsSelected: true,
                hasFallbackCamera: false,
                fallbackHasMatchingProfile: false
            )
        )

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.monitoring, .paused(.cameraDisconnected)]
        )
        XCTAssertEqual(
            harness.timeline.map(\.fallbackSwitchRequested),
            [false, false]
        )
    }

    func testCameraDisconnectNonSelectedRequestsUISyncOnly() {
        var harness = TrackingScenarioHarness(
            state: .monitoring,
            trackingSource: .camera,
            isCalibrated: true,
            detectorAvailable: true
        )

        harness.send(
            .cameraDisconnected(
                disconnectedCameraIsSelected: false,
                hasFallbackCamera: true,
                fallbackHasMatchingProfile: true
            )
        )

        XCTAssertEqual(
            harness.timeline.map(\.state),
            [.monitoring, .monitoring]
        )
        XCTAssertEqual(
            harness.timeline.map(\.uiSyncRequested),
            [false, true]
        )
    }
}
