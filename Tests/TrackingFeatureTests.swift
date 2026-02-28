import XCTest
import ComposableArchitecture
@testable import DorsoCore

private actor EffectIntentRecorder {
    private var intents: [TrackingFeature.EffectIntent] = []

    func record(_ intent: TrackingFeature.EffectIntent) {
        intents.append(intent)
    }

    func drain() -> [TrackingFeature.EffectIntent] {
        defer { intents.removeAll() }
        return intents
    }
}

private extension TrackingRuntimeClient {
    static func recording(_ recorder: EffectIntentRecorder) -> Self {
        Self(
            startMonitoring: { await recorder.record(.startMonitoring) },
            beginMonitoringSession: { await recorder.record(.beginMonitoringSession) },
            applyStartupCameraProfile: { profile in
                await recorder.record(.applyStartupCameraProfile(profile))
            },
            showOnboarding: { await recorder.record(.showOnboarding) },
            switchCameraToMatchingProfile: { profile in
                await recorder.record(.switchCamera(.matchingProfile(profile)))
            },
            switchCameraToFallback: { cameraID, profile in
                await recorder.record(.switchCamera(.fallback(cameraID: cameraID, profile: profile)))
            },
            switchCameraToSelected: {
                await recorder.record(.switchCamera(.selectedCamera))
            },
            syncUI: { await recorder.record(.syncUI) },
            stopDetector: { source in await recorder.record(.stopDetector(source)) },
            persistTrackingSource: { await recorder.record(.persistTrackingSource) },
            resetMonitoringState: { await recorder.record(.resetMonitoringState) },
            showCalibrationPermissionDeniedAlert: {
                await recorder.record(.showCalibrationPermissionDeniedAlert)
            },
            openPrivacySettings: { await recorder.record(.openPrivacySettings) },
            showCameraCalibrationRetryAlert: { message in
                await recorder.record(.showCameraCalibrationRetryAlert(message: message))
            },
            retryCalibration: { await recorder.record(.retryCalibration) }
        )
    }
}

final class TrackingFeatureTests: XCTestCase {
    @MainActor
    private func makeStore(
        initialState: TrackingFeature.State,
        recorder: EffectIntentRecorder? = nil
    ) -> TestStore<TrackingFeature.State, TrackingFeature.Action> {
        if let recorder {
            return TestStore(initialState: initialState) {
                TrackingFeature()
            } withDependencies: {
                $0.trackingRuntime = .recording(recorder)
            }
        }

        return TestStore(initialState: initialState) {
            TrackingFeature()
        }
    }

    @MainActor
    private func assertIntents(
        _ expected: [TrackingFeature.EffectIntent],
        recorder: EffectIntentRecorder,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let actual = await recorder.drain()
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    @MainActor
    func testToggleEnabledUsesSourceSpecificUnavailableStateForAirPods() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .disabled,
                trackingMode: .manual,
                manualSource: .airpods,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        )

        await store.send(
            .toggleEnabled(
                trackingSource: .airpods,
                isCalibrated: true,
                detectorAvailable: false
            )
        ) {
            $0.appState = .paused(.airPodsRemoved)
        }
    }

    @MainActor
    func testToggleEnabledToMonitoringEmitsStartMonitoringIntent() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .disabled,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .toggleEnabled(
                trackingSource: .camera,
                isCalibrated: true,
                detectorAvailable: true
            )
        ) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testInitialSetupEvaluatedInMarketingModeEmitsStartMonitoringOnly() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(initialState: TrackingFeature.State(), recorder: recorder)

        await store.send(
            .initialSetupEvaluated(
                isMarketingMode: true,
                hasCameraProfile: false,
                profileCameraAvailable: false,
                hasValidAirPodsCalibration: false
            )
        )
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testInitialSetupEvaluatedForCameraWithAvailableProfileEmitsApplyProfileAndStartMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                manualSource: .camera
            ),
            recorder: recorder
        )

        await store.send(
            .initialSetupEvaluated(
                isMarketingMode: false,
                hasCameraProfile: true,
                profileCameraAvailable: true,
                hasValidAirPodsCalibration: false
            )
        )
        await store.finish()
        await assertIntents([.applyStartupCameraProfile(), .startMonitoring], recorder: recorder)
    }

    @MainActor
    func testInitialSetupEvaluatedForAirPodsWithoutCalibrationEmitsShowOnboarding() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                manualSource: .airpods
            ),
            recorder: recorder
        )

        await store.send(
            .initialSetupEvaluated(
                isMarketingMode: false,
                hasCameraProfile: false,
                profileCameraAvailable: false,
                hasValidAirPodsCalibration: false
            )
        )
        await store.finish()
        await assertIntents([.showOnboarding], recorder: recorder)
    }

    @MainActor
    func testPauseOnTheGoSettingDisabledFromOnTheGoPauseResumesMonitoring() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.onTheGo),
                manualSource: .camera
            )
        )

        await store.send(.pauseOnTheGoSettingChanged(isEnabled: false)) {
            $0.appState = .monitoring
        }
    }

    @MainActor
    func testPauseOnTheGoSettingEnabledKeepsCurrentState() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.onTheGo),
                manualSource: .camera
            )
        )

        await store.send(.pauseOnTheGoSettingChanged(isEnabled: true))
    }

    @MainActor
    func testStartMonitoringRequestedInMarketingModeMonitorsWithoutBeginningSession() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .disabled,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        )

        await store.send(
            .startMonitoringRequested(
                isMarketingMode: true,
                trackingSource: .camera,
                isCalibrated: false,
                isConnected: true
            )
        ) {
            $0.appState = .monitoring
        }
    }

    @MainActor
    func testStartMonitoringRequestedWithoutCalibrationPausesNoProfile() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .disabled,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        )

        await store.send(
            .startMonitoringRequested(
                isMarketingMode: false,
                trackingSource: .camera,
                isCalibrated: false,
                isConnected: true
            )
        ) {
            $0.appState = .paused(.noProfile)
        }
    }

    @MainActor
    func testStartMonitoringRequestedForDisconnectedAirPodsPausesRemovedAndBeginsSession() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .disabled,
                trackingMode: .manual,
                manualSource: .airpods,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .startMonitoringRequested(
                isMarketingMode: false,
                trackingSource: .airpods,
                isCalibrated: true,
                isConnected: false
            )
        ) {
            $0.appState = .paused(.airPodsRemoved)
        }
        await store.finish()
        await assertIntents([.beginMonitoringSession], recorder: recorder)
    }

    @MainActor
    func testStartMonitoringRequestedForConnectedCameraMonitorsAndBeginsSession() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .disabled,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .startMonitoringRequested(
                isMarketingMode: false,
                trackingSource: .camera,
                isCalibrated: true,
                isConnected: true
            )
        ) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.beginMonitoringSession], recorder: recorder)
    }

    @MainActor
    func testScreenLockUnlockRestoresMonitoringState() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.screenLocked) {
            $0.appState = .paused(.screenLocked)
            $0.stateBeforeLock = .monitoring
        }

        await store.send(.screenUnlocked) {
            $0.appState = .monitoring
            $0.stateBeforeLock = nil
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testCameraDisconnectFallbackNoProfilePausesNoProfile() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .cameraDisconnected(
                disconnectedCameraIsSelected: true,
                hasFallbackCamera: true,
                fallbackHasMatchingProfile: false
            )
        ) {
            $0.appState = .paused(.noProfile)
        }
        await store.finish()
        await assertIntents([.switchCamera(.fallback())], recorder: recorder)
    }

    @MainActor
    func testAirPodsReconnectMovesBackToMonitoringState() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.airPodsRemoved),
                trackingMode: .manual,
                manualSource: .airpods,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.airPodsConnectionChanged(true)) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testCalibrationAuthorizationDeniedReturnsMonitoringWhenSourceIsCalibrated() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .calibrating,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.calibrationAuthorizationDenied(isCalibrated: true)) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.showCalibrationPermissionDeniedAlert], recorder: recorder)
    }

    @MainActor
    func testCalibrationAuthorizationDeniedReturnsNoProfileWhenSourceIsNotCalibrated() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .calibrating,
                trackingMode: .manual,
                manualSource: .airpods,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.calibrationAuthorizationDenied(isCalibrated: false)) {
            $0.appState = .paused(.noProfile)
        }
        await store.finish()
        await assertIntents([.showCalibrationPermissionDeniedAlert], recorder: recorder)
    }

    @MainActor
    func testCalibrationOpenSettingsRequestedEmitsOpenPrivacySettingsIntent() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.noProfile),
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.calibrationOpenSettingsRequested)
        await store.finish()
        await assertIntents([.openPrivacySettings], recorder: recorder)
    }

    @MainActor
    func testCalibrationRetryRequestedEmitsRetryCalibrationIntent() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.cameraDisconnected),
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.calibrationRetryRequested)
        await store.finish()
        await assertIntents([.retryCalibration], recorder: recorder)
    }

    @MainActor
    func testCalibrationAuthorizationGrantedTransitionsToCalibrating() async {
        let store = TestStore(
            initialState: TrackingFeature.State(
                appState: .paused(.noProfile),
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
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

    @MainActor
    func testRuntimeDetectorStartFailureForCameraPausesCameraDisconnected() async {
        let store = TestStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        ) {
            TrackingFeature()
        }

        await store.send(.runtimeDetectorStartFailed(trackingSource: .camera)) {
            $0.appState = .paused(.cameraDisconnected)
        }
    }

    @MainActor
    func testRuntimeDetectorStartFailureForAirPodsPausesAirPodsRemoved() async {
        let store = TestStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .airpods,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        ) {
            TrackingFeature()
        }

        await store.send(.runtimeDetectorStartFailed(trackingSource: .airpods)) {
            $0.appState = .paused(.airPodsRemoved)
        }
    }

    @MainActor
    func testCalibrationStartFailureForCameraEmitsRetryAlertIntent() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .calibrating,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.calibrationStartFailed(errorMessage: "camera unavailable")) {
            $0.appState = .paused(.cameraDisconnected)
        }
        await store.finish()
        await assertIntents([.showCameraCalibrationRetryAlert(message: "camera unavailable")], recorder: recorder)
    }

    @MainActor
    func testCalibrationStartFailureForAirPodsDoesNotEmitRetryAlertIntent() async {
        let store = TestStore(
            initialState: TrackingFeature.State(
                appState: .calibrating,
                trackingMode: .manual,
                manualSource: .airpods,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        ) {
            TrackingFeature()
        }

        await store.send(.calibrationStartFailed(errorMessage: nil)) {
            $0.appState = .paused(.airPodsRemoved)
        }
    }

    @MainActor
    func testCalibrationCancelledReturnsMonitoringAndRequestsRestartWhenSourceIsCalibrated() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .calibrating,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.calibrationCancelled(isCalibrated: true)) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testCalibrationCancelledReturnsNoProfileWhenSourceIsNotCalibrated() async {
        let store = TestStore(
            initialState: TrackingFeature.State(
                appState: .calibrating,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        ) {
            TrackingFeature()
        }

        await store.send(.calibrationCancelled(isCalibrated: false)) {
            $0.appState = .paused(.noProfile)
        }
    }

    @MainActor
    func testCalibrationCompletedEmitsResetAndRestartMonitoringIntents() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .calibrating,
                trackingMode: .manual,
                manualSource: .airpods,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.calibrationCompleted) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.resetMonitoringState, .startMonitoring], recorder: recorder)
    }

    @MainActor
    func testCameraConnectWithMatchingProfileFromDisconnectedPauseMovesToMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.cameraDisconnected),
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.cameraConnected(hasMatchingProfile: true)) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.switchCamera(.matchingProfile()), .startMonitoring], recorder: recorder)
    }

    @MainActor
    func testCameraDisconnectNonSelectedLeavesStateUnchanged() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .cameraDisconnected(
                disconnectedCameraIsSelected: false,
                hasFallbackCamera: true,
                fallbackHasMatchingProfile: true
            )
        )
        await store.finish()
        await assertIntents([.syncUI], recorder: recorder)
    }

    @MainActor
    func testDisplayConfigurationWithPauseOnTheGoPausesOnTheGo() async {
        let store = TestStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        ) {
            TrackingFeature()
        }

        await store.send(
            .displayConfigurationChanged(
                pauseOnTheGoEnabled: true,
                isLaptopOnlyConfiguration: true,
                hasAnyCamera: true,
                hasMatchingProfileCamera: true,
                selectedCameraMatchesProfile: true
            )
        ) {
            $0.appState = .paused(.onTheGo)
        }
    }

    @MainActor
    func testDisplayConfigurationWithMatchingProfileEmitsSwitchAndStartMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.noProfile),
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .displayConfigurationChanged(
                pauseOnTheGoEnabled: false,
                isLaptopOnlyConfiguration: false,
                hasAnyCamera: true,
                hasMatchingProfileCamera: true,
                selectedCameraMatchesProfile: false
            )
        ) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.switchCamera(.matchingProfile()), .startMonitoring], recorder: recorder)
    }

    @MainActor
    func testDisplayConfigurationWithoutAnyCameraPausesDisconnected() async {
        let store = TestStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        ) {
            TrackingFeature()
        }

        await store.send(
            .displayConfigurationChanged(
                pauseOnTheGoEnabled: false,
                isLaptopOnlyConfiguration: false,
                hasAnyCamera: false,
                hasMatchingProfileCamera: false,
                selectedCameraMatchesProfile: false
            )
        ) {
            $0.appState = .paused(.cameraDisconnected)
        }
    }

    @MainActor
    func testCameraSelectionChangedEmitsSelectedCameraSwitchAndPausesNoProfile() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.cameraSelectionChanged) {
            $0.appState = .paused(.noProfile)
        }
        await store.finish()
        await assertIntents([.switchCamera(.selectedCamera)], recorder: recorder)
    }

    @MainActor
    func testSwitchTrackingSourceToUncalibratedSourcePausesNoProfileAndPersistsSource() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.switchTrackingSource(.airpods, isNewSourceCalibrated: false)) {
            $0.appState = .paused(.noProfile)
            $0.manualSource = .airpods
        }
        await store.finish()
        await assertIntents(
            [
                .stopDetector(.camera),
                .persistTrackingSource
            ],
            recorder: recorder
        )
    }

    @MainActor
    func testSwitchTrackingSourceToCalibratedSourceRequestsStartMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.noProfile),
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.switchTrackingSource(.airpods, isNewSourceCalibrated: true)) {
            $0.appState = .monitoring
            $0.manualSource = .airpods
        }
        await store.finish()
        await assertIntents(
            [
                .stopDetector(.camera),
                .persistTrackingSource,
                .startMonitoring
            ],
            recorder: recorder
        )
    }

    @MainActor
    func testSwitchTrackingSourceToSameSourceNoOp() async {
        let store = TestStore(
            initialState: TrackingFeature.State(
                appState: .paused(.noProfile),
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                autoReturnEnabled: false,
                stateBeforeLock: nil
            )
        ) {
            TrackingFeature()
        }

        await store.send(.switchTrackingSource(.camera, isNewSourceCalibrated: true))
    }
}
