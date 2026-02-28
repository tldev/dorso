import XCTest
@testable import DorsoCore

final class PostureEngineTransitionTests: XCTestCase {

    // MARK: - canTransition: Allowed Transitions

    func testCanTransitionFromDisabledToMonitoring() {
        XCTAssertTrue(PostureEngine.canTransition(from: .disabled, to: .monitoring))
    }

    func testCanTransitionFromDisabledToPausedNoProfile() {
        XCTAssertTrue(PostureEngine.canTransition(from: .disabled, to: .paused(.noProfile)))
    }

    func testCanTransitionFromDisabledToCalibrating() {
        XCTAssertTrue(PostureEngine.canTransition(from: .disabled, to: .calibrating))
    }

    func testCanTransitionFromMonitoringToDisabled() {
        XCTAssertTrue(PostureEngine.canTransition(from: .monitoring, to: .disabled))
    }

    func testCanTransitionFromMonitoringToPausedScreenLocked() {
        XCTAssertTrue(PostureEngine.canTransition(from: .monitoring, to: .paused(.screenLocked)))
    }

    func testCanTransitionFromMonitoringToCalibrating() {
        XCTAssertTrue(PostureEngine.canTransition(from: .monitoring, to: .calibrating))
    }

    func testCanTransitionFromPausedNoProfileToDisabled() {
        XCTAssertTrue(PostureEngine.canTransition(from: .paused(.noProfile), to: .disabled))
    }

    func testCanTransitionFromPausedNoProfileToMonitoring() {
        XCTAssertTrue(PostureEngine.canTransition(from: .paused(.noProfile), to: .monitoring))
    }

    func testCanTransitionFromPausedNoProfileToCalibrating() {
        XCTAssertTrue(PostureEngine.canTransition(from: .paused(.noProfile), to: .calibrating))
    }

    func testCanTransitionFromCalibratingToMonitoring() {
        XCTAssertTrue(PostureEngine.canTransition(from: .calibrating, to: .monitoring))
    }

    func testCanTransitionFromCalibratingToPausedNoProfile() {
        XCTAssertTrue(PostureEngine.canTransition(from: .calibrating, to: .paused(.noProfile)))
    }

    func testCanTransitionFromCalibratingToDisabled() {
        XCTAssertTrue(PostureEngine.canTransition(from: .calibrating, to: .disabled))
    }

    // MARK: - canTransition: Same State (disallowed for non-paused)

    func testCannotTransitionDisabledToDisabled() {
        XCTAssertFalse(PostureEngine.canTransition(from: .disabled, to: .disabled))
    }

    func testCannotTransitionMonitoringToMonitoring() {
        XCTAssertFalse(PostureEngine.canTransition(from: .monitoring, to: .monitoring))
    }

    func testCannotTransitionCalibratingToCalibrating() {
        XCTAssertFalse(PostureEngine.canTransition(from: .calibrating, to: .calibrating))
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
                PostureEngine.canTransition(from: .monitoring, to: .paused(reason)),
                "Should allow .monitoring -> .paused(.\(reason))"
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
        XCTAssertTrue(PostureEngine.shouldDetectorRun(for: .monitoring, trackingSource: .camera))
    }

    func testShouldDetectorRunMonitoringAirPods() {
        XCTAssertTrue(PostureEngine.shouldDetectorRun(for: .monitoring, trackingSource: .airpods))
    }

    func testShouldDetectorRunCalibratingCamera() {
        XCTAssertTrue(PostureEngine.shouldDetectorRun(for: .calibrating, trackingSource: .camera))
    }

    func testShouldDetectorRunCalibratingAirPods() {
        XCTAssertTrue(PostureEngine.shouldDetectorRun(for: .calibrating, trackingSource: .airpods))
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
        let state = PostureEngine.stateWhenEnabling(
            isCalibrated: false,
            detectorAvailable: false,
            trackingSource: .camera
        )
        XCTAssertEqual(state, .paused(.noProfile))
    }

    func testStateWhenEnablingCalibratedAndAvailableReturnsMonitoring() {
        let state = PostureEngine.stateWhenEnabling(
            isCalibrated: true,
            detectorAvailable: true,
            trackingSource: .camera
        )
        XCTAssertEqual(state, .monitoring)
    }

    func testStateWhenEnablingCalibratedButUnavailableReturnsCameraDisconnectedForCamera() {
        let state = PostureEngine.stateWhenEnabling(
            isCalibrated: true,
            detectorAvailable: false,
            trackingSource: .camera
        )
        XCTAssertEqual(state, .paused(.cameraDisconnected))
    }

    func testStateWhenEnablingCalibratedButUnavailableReturnsAirPodsRemovedForAirPods() {
        let state = PostureEngine.stateWhenEnabling(
            isCalibrated: true,
            detectorAvailable: false,
            trackingSource: .airpods
        )
        XCTAssertEqual(state, .paused(.airPodsRemoved))
    }

    func testStateWhenEnablingNotCalibratedButAvailableReturnsNoProfile() {
        let state = PostureEngine.stateWhenEnabling(
            isCalibrated: false,
            detectorAvailable: true,
            trackingSource: .airpods
        )
        XCTAssertEqual(state, .paused(.noProfile))
    }

    // MARK: - Calibration Authorization Denied

    func testStateWhenCalibrationAuthorizationDeniedWithCalibrationReturnsMonitoring() {
        let state = PostureEngine.stateWhenCalibrationAuthorizationDenied(isCalibrated: true)
        XCTAssertEqual(state, .monitoring)
    }

    func testStateWhenCalibrationAuthorizationDeniedWithoutCalibrationReturnsNoProfile() {
        let state = PostureEngine.stateWhenCalibrationAuthorizationDenied(isCalibrated: false)
        XCTAssertEqual(state, .paused(.noProfile))
    }

    func testStateWhenCalibrationAuthorizationGrantedReturnsCalibrating() {
        let state = PostureEngine.stateWhenCalibrationAuthorizationGranted()
        XCTAssertEqual(state, .calibrating)
    }

    func testStateWhenCalibrationCancelsWithCalibrationReturnsMonitoring() {
        let state = PostureEngine.stateWhenCalibrationCancels(isCalibrated: true)
        XCTAssertEqual(state, .monitoring)
    }

    func testStateWhenCalibrationCancelsWithoutCalibrationReturnsNoProfile() {
        let state = PostureEngine.stateWhenCalibrationCancels(isCalibrated: false)
        XCTAssertEqual(state, .paused(.noProfile))
    }

    func testStateWhenCalibrationCompletesReturnsMonitoring() {
        let state = PostureEngine.stateWhenCalibrationCompletes()
        XCTAssertEqual(state, .monitoring)
    }

    // MARK: - Monitoring Start

    func testStateWhenMonitoringStartsInMarketingModeMonitorsWithoutBeginningSession() {
        let result = PostureEngine.stateWhenMonitoringStarts(
            isMarketingMode: true,
            trackingSource: .camera,
            isCalibrated: false,
            isConnected: false
        )

        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertFalse(result.shouldBeginMonitoringSession)
    }

    func testStateWhenMonitoringStartsWithoutCalibrationPausesNoProfile() {
        let result = PostureEngine.stateWhenMonitoringStarts(
            isMarketingMode: false,
            trackingSource: .camera,
            isCalibrated: false,
            isConnected: true
        )

        XCTAssertEqual(result.newState, .paused(.noProfile))
        XCTAssertFalse(result.shouldBeginMonitoringSession)
    }

    func testStateWhenMonitoringStartsForDisconnectedAirPodsPausesRemovedAndBeginsSession() {
        let result = PostureEngine.stateWhenMonitoringStarts(
            isMarketingMode: false,
            trackingSource: .airpods,
            isCalibrated: true,
            isConnected: false
        )

        XCTAssertEqual(result.newState, .paused(.airPodsRemoved))
        XCTAssertTrue(result.shouldBeginMonitoringSession)
    }

    func testStateWhenMonitoringStartsForConnectedCameraMonitorsAndBeginsSession() {
        let result = PostureEngine.stateWhenMonitoringStarts(
            isMarketingMode: false,
            trackingSource: .camera,
            isCalibrated: true,
            isConnected: true
        )

        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertTrue(result.shouldBeginMonitoringSession)
    }

    // MARK: - Initial Setup

    func testStateWhenInitialSetupRunsInMarketingModeStartsMonitoringWithoutOnboarding() {
        let result = PostureEngine.stateWhenInitialSetupRuns(
            isMarketingMode: true,
            trackingSource: .camera,
            hasCameraProfile: false,
            profileCameraAvailable: false,
            hasValidAirPodsCalibration: false
        )

        XCTAssertFalse(result.shouldApplyStartupCameraProfile)
        XCTAssertTrue(result.shouldStartMonitoring)
        XCTAssertFalse(result.shouldShowOnboarding)
    }

    func testStateWhenInitialSetupRunsForCameraWithAvailableProfileAppliesProfileAndStartsMonitoring() {
        let result = PostureEngine.stateWhenInitialSetupRuns(
            isMarketingMode: false,
            trackingSource: .camera,
            hasCameraProfile: true,
            profileCameraAvailable: true,
            hasValidAirPodsCalibration: false
        )

        XCTAssertTrue(result.shouldApplyStartupCameraProfile)
        XCTAssertTrue(result.shouldStartMonitoring)
        XCTAssertFalse(result.shouldShowOnboarding)
    }

    func testStateWhenInitialSetupRunsForCameraWithoutAvailableProfileShowsOnboarding() {
        let result = PostureEngine.stateWhenInitialSetupRuns(
            isMarketingMode: false,
            trackingSource: .camera,
            hasCameraProfile: true,
            profileCameraAvailable: false,
            hasValidAirPodsCalibration: false
        )

        XCTAssertFalse(result.shouldApplyStartupCameraProfile)
        XCTAssertFalse(result.shouldStartMonitoring)
        XCTAssertTrue(result.shouldShowOnboarding)
    }

    func testStateWhenInitialSetupRunsForAirPodsWithCalibrationStartsMonitoring() {
        let result = PostureEngine.stateWhenInitialSetupRuns(
            isMarketingMode: false,
            trackingSource: .airpods,
            hasCameraProfile: false,
            profileCameraAvailable: false,
            hasValidAirPodsCalibration: true
        )

        XCTAssertFalse(result.shouldApplyStartupCameraProfile)
        XCTAssertTrue(result.shouldStartMonitoring)
        XCTAssertFalse(result.shouldShowOnboarding)
    }

    // MARK: - Pause On The Go Setting

    func testStateWhenPauseOnTheGoDisablesFromOnTheGoPauseResumesMonitoring() {
        let state = PostureEngine.stateWhenPauseOnTheGoSettingChanges(
            currentState: .paused(.onTheGo),
            isEnabled: false
        )
        XCTAssertEqual(state, .monitoring)
    }

    func testStateWhenPauseOnTheGoEnabledKeepsOnTheGoPauseState() {
        let state = PostureEngine.stateWhenPauseOnTheGoSettingChanges(
            currentState: .paused(.onTheGo),
            isEnabled: true
        )
        XCTAssertEqual(state, .paused(.onTheGo))
    }

    // MARK: - Screen Lock / Unlock Transitions

    func testStateWhenScreenLocksMonitoringTransitionsToScreenLockedAndCapturesState() {
        let result = PostureEngine.stateWhenScreenLocks(
            currentState: .monitoring,
            trackingSource: .camera,
            stateBeforeLock: nil
        )

        XCTAssertEqual(result.newState, .paused(.screenLocked))
        XCTAssertEqual(result.stateBeforeLock, .monitoring)
    }

    func testStateWhenScreenLocksCalibratingTransitionsToScreenLockedAndCapturesState() {
        let result = PostureEngine.stateWhenScreenLocks(
            currentState: .calibrating,
            trackingSource: .camera,
            stateBeforeLock: nil
        )

        XCTAssertEqual(result.newState, .paused(.screenLocked))
        XCTAssertEqual(result.stateBeforeLock, .calibrating)
    }

    func testStateWhenScreenLocksPausedNoProfileNoTransition() {
        let result = PostureEngine.stateWhenScreenLocks(
            currentState: .paused(.noProfile),
            trackingSource: .camera,
            stateBeforeLock: nil
        )

        XCTAssertEqual(result.newState, .paused(.noProfile))
        XCTAssertNil(result.stateBeforeLock)
    }

    func testStateWhenScreenLocksPausedAirPodsRemovedTransitionsForAirPods() {
        let result = PostureEngine.stateWhenScreenLocks(
            currentState: .paused(.airPodsRemoved),
            trackingSource: .airpods,
            stateBeforeLock: nil
        )

        XCTAssertEqual(result.newState, .paused(.screenLocked))
        XCTAssertEqual(result.stateBeforeLock, .paused(.airPodsRemoved))
    }

    func testStateWhenScreenUnlocksRestoresMonitoringAndRequestsRestart() {
        let result = PostureEngine.stateWhenScreenUnlocks(
            currentState: .paused(.screenLocked),
            stateBeforeLock: .monitoring
        )

        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertNil(result.stateBeforeLock)
        XCTAssertTrue(result.shouldRestartMonitoring)
    }

    func testStateWhenScreenUnlocksRestoresCalibratingWithoutRestartFlag() {
        let result = PostureEngine.stateWhenScreenUnlocks(
            currentState: .paused(.screenLocked),
            stateBeforeLock: .calibrating
        )

        XCTAssertEqual(result.newState, .calibrating)
        XCTAssertNil(result.stateBeforeLock)
        XCTAssertFalse(result.shouldRestartMonitoring)
    }

    func testStateWhenScreenUnlocksWithNoCapturedStateRemainsScreenLocked() {
        let result = PostureEngine.stateWhenScreenUnlocks(
            currentState: .paused(.screenLocked),
            stateBeforeLock: nil
        )

        XCTAssertEqual(result.newState, .paused(.screenLocked))
        XCTAssertNil(result.stateBeforeLock)
        XCTAssertFalse(result.shouldRestartMonitoring)
    }

    // MARK: - AirPods Connection Transitions

    func testStateWhenAirPodsConnectsFromRemovedPauseRestartsMonitoring() {
        let result = PostureEngine.stateWhenAirPodsConnectionChanges(
            currentState: .paused(.airPodsRemoved),
            trackingSource: .airpods,
            isConnected: true
        )

        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertTrue(result.shouldRestartMonitoring)
    }

    func testStateWhenAirPodsDisconnectsFromMonitoringPausesRemoved() {
        let result = PostureEngine.stateWhenAirPodsConnectionChanges(
            currentState: .monitoring,
            trackingSource: .airpods,
            isConnected: false
        )

        XCTAssertEqual(result.newState, .paused(.airPodsRemoved))
        XCTAssertFalse(result.shouldRestartMonitoring)
    }

    func testStateWhenAirPodsConnectionChangesIgnoredForCameraSource() {
        let result = PostureEngine.stateWhenAirPodsConnectionChanges(
            currentState: .monitoring,
            trackingSource: .camera,
            isConnected: false
        )

        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertFalse(result.shouldRestartMonitoring)
    }

    // MARK: - Camera Connect Transitions

    func testStateWhenCameraConnectsWithMatchingProfileStartsMonitoring() {
        let result = PostureEngine.stateWhenCameraConnects(
            currentState: .paused(.cameraDisconnected),
            trackingSource: .camera,
            hasMatchingProfileForConnectedCamera: true
        )

        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertTrue(result.shouldSelectAndStartMonitoring)
    }

    func testStateWhenCameraConnectsWithoutMatchFromDisconnectedBecomesNoProfile() {
        let result = PostureEngine.stateWhenCameraConnects(
            currentState: .paused(.cameraDisconnected),
            trackingSource: .camera,
            hasMatchingProfileForConnectedCamera: false
        )

        XCTAssertEqual(result.newState, .paused(.noProfile))
        XCTAssertFalse(result.shouldSelectAndStartMonitoring)
    }

    // MARK: - Camera Disconnect Transitions

    func testStateWhenCameraDisconnectsNonSelectedRequestsUISyncOnly() {
        let result = PostureEngine.stateWhenCameraDisconnects(
            currentState: .monitoring,
            trackingSource: .camera,
            disconnectedCameraIsSelected: false,
            hasFallbackCamera: true,
            fallbackMatchesProfile: true
        )

        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertEqual(result.action, .syncUIOnly)
    }

    func testStateWhenCameraDisconnectsSelectedWithFallbackProfileSwitchesAndMonitors() {
        let result = PostureEngine.stateWhenCameraDisconnects(
            currentState: .monitoring,
            trackingSource: .camera,
            disconnectedCameraIsSelected: true,
            hasFallbackCamera: true,
            fallbackMatchesProfile: true
        )

        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertEqual(result.action, .switchToFallback(startMonitoring: true))
    }

    func testStateWhenCameraDisconnectsSelectedWithFallbackNoProfileSwitchesAndPausesNoProfile() {
        let result = PostureEngine.stateWhenCameraDisconnects(
            currentState: .monitoring,
            trackingSource: .camera,
            disconnectedCameraIsSelected: true,
            hasFallbackCamera: true,
            fallbackMatchesProfile: false
        )

        XCTAssertEqual(result.newState, .paused(.noProfile))
        XCTAssertEqual(result.action, .switchToFallback(startMonitoring: false))
    }

    func testStateWhenCameraDisconnectsSelectedWithNoFallbackPausesDisconnected() {
        let result = PostureEngine.stateWhenCameraDisconnects(
            currentState: .monitoring,
            trackingSource: .camera,
            disconnectedCameraIsSelected: true,
            hasFallbackCamera: false,
            fallbackMatchesProfile: false
        )

        XCTAssertEqual(result.newState, .paused(.cameraDisconnected))
        XCTAssertEqual(result.action, .none)
    }

    // MARK: - Display Configuration Transitions

    func testStateWhenDisplayConfigurationChangesInDisabledStateNoTransition() {
        let result = PostureEngine.stateWhenDisplayConfigurationChanges(
            currentState: .disabled,
            trackingSource: .camera,
            pauseOnTheGoEnabled: true,
            isLaptopOnlyConfiguration: true,
            hasAnyCamera: false,
            hasMatchingProfileCamera: false,
            selectedCameraMatchesProfile: false
        )

        XCTAssertEqual(result.newState, .disabled)
        XCTAssertFalse(result.shouldSwitchToProfileCamera)
        XCTAssertFalse(result.shouldStartMonitoring)
    }

    func testStateWhenDisplayConfigurationChangesWithPauseOnTheGoPausesOnTheGo() {
        let result = PostureEngine.stateWhenDisplayConfigurationChanges(
            currentState: .monitoring,
            trackingSource: .camera,
            pauseOnTheGoEnabled: true,
            isLaptopOnlyConfiguration: true,
            hasAnyCamera: true,
            hasMatchingProfileCamera: true,
            selectedCameraMatchesProfile: true
        )

        XCTAssertEqual(result.newState, .paused(.onTheGo))
        XCTAssertFalse(result.shouldSwitchToProfileCamera)
        XCTAssertFalse(result.shouldStartMonitoring)
    }

    func testStateWhenDisplayConfigurationChangesWithMatchingProfileRequestsSwitchAndStart() {
        let result = PostureEngine.stateWhenDisplayConfigurationChanges(
            currentState: .paused(.noProfile),
            trackingSource: .camera,
            pauseOnTheGoEnabled: false,
            isLaptopOnlyConfiguration: false,
            hasAnyCamera: true,
            hasMatchingProfileCamera: true,
            selectedCameraMatchesProfile: false
        )

        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertTrue(result.shouldSwitchToProfileCamera)
        XCTAssertTrue(result.shouldStartMonitoring)
    }

    func testStateWhenDisplayConfigurationChangesWithNoCamerasPausesDisconnected() {
        let result = PostureEngine.stateWhenDisplayConfigurationChanges(
            currentState: .monitoring,
            trackingSource: .camera,
            pauseOnTheGoEnabled: false,
            isLaptopOnlyConfiguration: false,
            hasAnyCamera: false,
            hasMatchingProfileCamera: false,
            selectedCameraMatchesProfile: false
        )

        XCTAssertEqual(result.newState, .paused(.cameraDisconnected))
        XCTAssertFalse(result.shouldSwitchToProfileCamera)
        XCTAssertFalse(result.shouldStartMonitoring)
    }

    // MARK: - Camera Selection Change

    func testStateWhenCameraSelectionChangesForCameraPausesNoProfile() {
        let state = PostureEngine.stateWhenCameraSelectionChanges(
            currentState: .monitoring,
            trackingSource: .camera
        )
        XCTAssertEqual(state, .paused(.noProfile))
    }

    // MARK: - Tracking Source Switch

    func testStateWhenSwitchingTrackingSourceToCalibratedSourceMonitors() {
        let result = PostureEngine.stateWhenSwitchingTrackingSource(
            currentState: .paused(.noProfile),
            currentSource: .camera,
            newSource: .airpods,
            isNewSourceCalibrated: true
        )

        XCTAssertEqual(result.newSource, .airpods)
        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertTrue(result.didSwitchSource)
        XCTAssertTrue(result.shouldStartMonitoring)
    }

    func testStateWhenSwitchingTrackingSourceToUncalibratedSourcePausesNoProfile() {
        let result = PostureEngine.stateWhenSwitchingTrackingSource(
            currentState: .monitoring,
            currentSource: .camera,
            newSource: .airpods,
            isNewSourceCalibrated: false
        )

        XCTAssertEqual(result.newSource, .airpods)
        XCTAssertEqual(result.newState, .paused(.noProfile))
        XCTAssertTrue(result.didSwitchSource)
        XCTAssertFalse(result.shouldStartMonitoring)
    }

    func testStateWhenSwitchingTrackingSourceToSameSourceIsNoOp() {
        let result = PostureEngine.stateWhenSwitchingTrackingSource(
            currentState: .monitoring,
            currentSource: .camera,
            newSource: .camera,
            isNewSourceCalibrated: true
        )

        XCTAssertEqual(result.newSource, .camera)
        XCTAssertEqual(result.newState, .monitoring)
        XCTAssertFalse(result.didSwitchSource)
        XCTAssertFalse(result.shouldStartMonitoring)
    }
}
