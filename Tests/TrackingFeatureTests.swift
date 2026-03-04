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
            updateBlur: { await recorder.record(.updateBlur) },
            trackAnalytics: { interval, isSlouching in
                await recorder.record(
                    .trackAnalytics(interval: interval, isSlouching: isSlouching)
                )
            },
            recordSlouchEvent: { await recorder.record(.recordSlouchEvent) },
            stopDetector: { source in await recorder.record(.stopDetector(source)) },
            persistTrackingSource: { await recorder.record(.persistTrackingSource) },
            showCalibrationPermissionDeniedAlert: {
                await recorder.record(.showCalibrationPermissionDeniedAlert)
            },
            openPrivacySettings: { await recorder.record(.openPrivacySettings) },
            showCameraCalibrationRetryAlert: { message in
                await recorder.record(.showCameraCalibrationRetryAlert(message: message))
            },
            retryCalibration: { await recorder.record(.retryCalibration) },
            startCalibrationForSource: { source in
                await recorder.record(.startCalibrationForSource(source))
            }
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
    func testPostureReadingReceivedUpdatesMonitoringStateAndEmitsPostureEffects() async {
        let recorder = EffectIntentRecorder()
        var initialState = TrackingFeature.State(
            appState: .monitoring,
            manualSource: .camera
        )
        initialState.postureConfig.frameThreshold = 1
        initialState.postureConfig.warningOnsetDelay = 0

        let store = makeStore(initialState: initialState, recorder: recorder)
        let reading = PostureReading(
            timestamp: Date(timeIntervalSince1970: 100),
            isBadPosture: true,
            severity: 0.7
        )

        await store.send(.postureReadingReceived(reading, isMarketingMode: false)) {
            $0.monitoringState.isCurrentlySlouching = true
            $0.monitoringState.consecutiveBadFrames = 1
            $0.monitoringState.postureWarningIntensity = 0.7
            $0.monitoringState.badPostureStartTime = reading.timestamp
            $0.lastPostureReadingTime = reading.timestamp
        }
        await store.finish()
        await assertIntents([.recordSlouchEvent, .syncUI, .updateBlur], recorder: recorder)
    }

    @MainActor
    func testPostureReadingReceivedWithPriorTimestampEmitsAnalyticsAndBlur() async {
        let recorder = EffectIntentRecorder()
        var initialState = TrackingFeature.State(
            appState: .monitoring,
            manualSource: .camera
        )
        initialState.lastPostureReadingTime = Date(timeIntervalSince1970: 100)

        let store = makeStore(initialState: initialState, recorder: recorder)
        let reading = PostureReading(
            timestamp: Date(timeIntervalSince1970: 101.5),
            isBadPosture: false,
            severity: 0
        )

        await store.send(.postureReadingReceived(reading, isMarketingMode: false)) {
            $0.monitoringState.consecutiveGoodFrames = 1
            $0.lastPostureReadingTime = reading.timestamp
        }
        await store.finish()
        await assertIntents(
            [
                .trackAnalytics(interval: 1.5, isSlouching: false),
                .updateBlur
            ],
            recorder: recorder
        )
    }

    @MainActor
    func testAwayStateChangedUpdatesReducerStateAndEmitsUIAndBlur() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                manualSource: .camera
            ),
            recorder: recorder
        )

        await store.send(.awayStateChanged(true, isMarketingMode: false)) {
            $0.monitoringState.isCurrentlyAway = true
        }
        await store.finish()
        await assertIntents([.syncUI, .updateBlur], recorder: recorder)
    }

    @MainActor
    func testAwayStateChangedInMarketingModeProducesNoEffects() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                manualSource: .camera
            ),
            recorder: recorder
        )

        await store.send(.awayStateChanged(true, isMarketingMode: true))
        await store.finish()
        await assertIntents([], recorder: recorder)
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
            $0.cameraReadiness.connected = true
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
            $0.airPodsReadiness.connected = true
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
    func testCalibrationCompletedEmitsRestartMonitoringIntent() async {
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

        await store.send(.calibrationCompleted(source: .airpods)) {
            $0.airPodsReadiness.calibrated = true
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
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
            $0.cameraReadiness.connected = true
            $0.cameraReadiness.calibrated = true
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
            $0.activeSource = .airpods
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
            $0.activeSource = .airpods
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

    // MARK: - Automatic Mode Tests

    private func readyReadiness() -> TrackingSourceReadiness {
        TrackingSourceReadiness(permissionGranted: true, connected: true, calibrated: true, available: true)
    }

    private func connectedNotCalibrated() -> TrackingSourceReadiness {
        TrackingSourceReadiness(permissionGranted: true, connected: true, calibrated: false, available: true)
    }

    private func disconnectedCalibrated() -> TrackingSourceReadiness {
        TrackingSourceReadiness(permissionGranted: true, connected: false, calibrated: true, available: true)
    }

    // MARK: setTrackingMode(.automatic)

    @MainActor
    func testSetTrackingModeAutomaticWithPreferredReadySwitchesToPreferred() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .airpods,
                activeSource: .camera,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: readyReadiness()
            ),
            recorder: recorder
        )

        await store.send(.setTrackingMode(.automatic)) {
            $0.trackingMode = .automatic
            $0.activeSource = .airpods
        }
        await store.finish()
        await assertIntents(
            [.stopDetector(.camera), .beginMonitoringSession, .persistTrackingSource, .syncUI],
            recorder: recorder
        )
    }

    @MainActor
    func testSetTrackingModeAutomaticWithPreferredNotReadyFallsBack() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .airpods,
                activeSource: .camera,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: disconnectedCalibrated()
            ),
            recorder: recorder
        )

        await store.send(.setTrackingMode(.automatic)) {
            $0.trackingMode = .automatic
            // Camera stays active as fallback, no source change
        }
        await store.finish()
        await assertIntents([], recorder: recorder)
    }

    @MainActor
    func testSetTrackingModeAutomaticWithNeitherReadyPauses() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .airpods,
                activeSource: .camera,
                cameraReadiness: disconnectedCalibrated(),
                airPodsReadiness: disconnectedCalibrated()
            )
        )

        await store.send(.setTrackingMode(.automatic)) {
            $0.trackingMode = .automatic
            $0.appState = .paused(.airPodsRemoved)
        }
    }

    // MARK: setTrackingMode(.manual) from automatic

    @MainActor
    func testSetTrackingModeManualFromAutomaticSwitchesSourceAndBeginsMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .automatic,
                manualSource: .camera,
                preferredSource: .airpods,
                activeSource: .airpods,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: readyReadiness()
            ),
            recorder: recorder
        )

        await store.send(.setTrackingMode(.manual)) {
            $0.trackingMode = .manual
            $0.activeSource = .camera
        }
        await store.finish()
        await assertIntents([.beginMonitoringSession], recorder: recorder)
    }

    @MainActor
    func testSetTrackingModeManualSameSourceNoBeginMonitoring() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .automatic,
                manualSource: .camera,
                preferredSource: .camera,
                activeSource: .camera,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: readyReadiness()
            )
        )

        await store.send(.setTrackingMode(.manual)) {
            $0.trackingMode = .manual
        }
    }

    // MARK: setPreferredSource

    @MainActor
    func testSetPreferredSourceSwitchesActiveInAutomatic() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .automatic,
                manualSource: .camera,
                preferredSource: .airpods,
                activeSource: .airpods,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: readyReadiness()
            ),
            recorder: recorder
        )

        await store.send(.setPreferredSource(.camera)) {
            $0.preferredSource = .camera
            $0.activeSource = .camera
        }
        await store.finish()
        await assertIntents(
            [.stopDetector(.airpods), .beginMonitoringSession, .persistTrackingSource, .syncUI],
            recorder: recorder
        )
    }

    @MainActor
    func testSetPreferredSourceInManualModeNoResolve() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                preferredSource: .camera,
                activeSource: .camera,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: readyReadiness()
            )
        )

        await store.send(.setPreferredSource(.airpods)) {
            $0.preferredSource = .airpods
        }
    }

    // MARK: setManualSource

    @MainActor
    func testSetManualSourceWhileMonitoringBeginsNewSession() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                activeSource: .camera
            ),
            recorder: recorder
        )

        await store.send(.setManualSource(.airpods)) {
            $0.manualSource = .airpods
            $0.activeSource = .airpods
        }
        await store.finish()
        await assertIntents([.beginMonitoringSession], recorder: recorder)
    }

    @MainActor
    func testSetManualSourceSameSourceNoEffect() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                activeSource: .camera
            )
        )

        await store.send(.setManualSource(.camera))
    }

    @MainActor
    func testSetManualSourceWhileNotMonitoringNoBeginSession() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.noProfile),
                trackingMode: .manual,
                manualSource: .camera,
                activeSource: .camera
            )
        )

        await store.send(.setManualSource(.airpods)) {
            $0.manualSource = .airpods
            $0.activeSource = .airpods
        }
    }

    // MARK: calibrationCompleted in automatic mode

    @MainActor
    func testCalibrationCompletedInAutomaticModeResolvesAndBeginsMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .calibrating,
                trackingMode: .automatic,
                manualSource: .camera,
                preferredSource: .camera,
                activeSource: .camera,
                cameraReadiness: connectedNotCalibrated(),
                airPodsReadiness: readyReadiness()
            ),
            recorder: recorder
        )

        await store.send(.calibrationCompleted(source: .camera)) {
            $0.cameraReadiness.calibrated = true
            $0.activeSource = .camera
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents(
            [.beginMonitoringSession, .persistTrackingSource, .syncUI],
            recorder: recorder
        )
    }

    @MainActor
    func testCalibrationCompletedForFallbackInAutomaticAutoReturnsToPreferred() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .calibrating,
                trackingMode: .automatic,
                manualSource: .camera,
                preferredSource: .airpods,
                activeSource: .camera,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: connectedNotCalibrated()
            ),
            recorder: recorder
        )

        await store.send(.calibrationCompleted(source: .airpods)) {
            $0.airPodsReadiness.calibrated = true
            $0.activeSource = .airpods
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents(
            [.stopDetector(.camera), .beginMonitoringSession, .persistTrackingSource, .syncUI],
            recorder: recorder
        )
    }

    // MARK: Auto-return via airPodsConnectionChanged

    @MainActor
    func testAirPodsReconnectInAutomaticModeAutoReturnsToPreferred() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .automatic,
                manualSource: .camera,
                preferredSource: .airpods,
                activeSource: .camera,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: disconnectedCalibrated()
            ),
            recorder: recorder
        )

        await store.send(.airPodsConnectionChanged(true)) {
            $0.airPodsReadiness.connected = true
            $0.activeSource = .airpods
        }
        await store.finish()
        await assertIntents(
            [.stopDetector(.camera), .beginMonitoringSession, .persistTrackingSource, .syncUI],
            recorder: recorder
        )
    }

    @MainActor
    func testAirPodsDisconnectInAutomaticModeFallsBackToCamera() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .automatic,
                manualSource: .camera,
                preferredSource: .airpods,
                activeSource: .airpods,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: readyReadiness()
            ),
            recorder: recorder
        )

        await store.send(.airPodsConnectionChanged(false)) {
            $0.airPodsReadiness.connected = false
            $0.activeSource = .camera
        }
        await store.finish()
        await assertIntents(
            [.stopDetector(.airpods), .beginMonitoringSession, .persistTrackingSource, .syncUI],
            recorder: recorder
        )
    }

    // MARK: sourceReadinessChanged

    @MainActor
    func testSourceReadinessChangedInAutomaticModeTriggersResolve() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.airPodsRemoved),
                trackingMode: .automatic,
                manualSource: .camera,
                preferredSource: .airpods,
                activeSource: .camera,
                cameraReadiness: readyReadiness(),
                airPodsReadiness: disconnectedCalibrated()
            ),
            recorder: recorder
        )

        let ready = readyReadiness()
        await store.send(.sourceReadinessChanged(source: .airpods, readiness: ready)) {
            $0.airPodsReadiness = ready
            $0.activeSource = .airpods
            $0.appState = .monitoring
        }
        await store.finish()
        // No stopDetector because previous state was paused (detector wasn't running)
        await assertIntents(
            [.beginMonitoringSession, .persistTrackingSource, .syncUI],
            recorder: recorder
        )
    }

    @MainActor
    func testSourceReadinessChangedInManualModeNoResolve() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                trackingMode: .manual,
                manualSource: .camera,
                activeSource: .camera,
                cameraReadiness: readyReadiness()
            )
        )

        let ready = readyReadiness()
        await store.send(.sourceReadinessChanged(source: .airpods, readiness: ready)) {
            $0.airPodsReadiness = ready
        }
    }

    // MARK: PostureEngine.resolveActiveSource

    @MainActor
    func testResolveActiveSourcePreferredReadyUsesPreferred() {
        let result = PostureEngine.resolveActiveSource(
            preferred: .airpods,
            currentActive: .camera,
            currentState: .monitoring,
            preferredReadiness: readyReadiness(),
            fallbackReadiness: readyReadiness(),
            autoReturn: true
        )
        XCTAssertEqual(result.activeSource, .airpods)
        XCTAssertEqual(result.newState, .monitoring)
    }

    @MainActor
    func testResolveActiveSourcePreferredNotReadyUsesFallback() {
        let result = PostureEngine.resolveActiveSource(
            preferred: .airpods,
            currentActive: .camera,
            currentState: .monitoring,
            preferredReadiness: disconnectedCalibrated(),
            fallbackReadiness: readyReadiness(),
            autoReturn: true
        )
        XCTAssertEqual(result.activeSource, .camera)
        XCTAssertEqual(result.newState, .monitoring)
    }

    @MainActor
    func testResolveActiveSourceNeitherReadyPauses() {
        let result = PostureEngine.resolveActiveSource(
            preferred: .airpods,
            currentActive: .camera,
            currentState: .monitoring,
            preferredReadiness: disconnectedCalibrated(),
            fallbackReadiness: disconnectedCalibrated(),
            autoReturn: true
        )
        XCTAssertNil(result.activeSource)
        XCTAssertEqual(result.newState, .paused(.airPodsRemoved))
    }

    @MainActor
    func testResolveActiveSourcePreferredConnectedNotCalibratedPausesNoProfile() {
        let result = PostureEngine.resolveActiveSource(
            preferred: .airpods,
            currentActive: .camera,
            currentState: .monitoring,
            preferredReadiness: connectedNotCalibrated(),
            fallbackReadiness: TrackingSourceReadiness(),
            autoReturn: true
        )
        XCTAssertNil(result.activeSource)
        XCTAssertEqual(result.newState, .paused(.noProfile))
    }
}
