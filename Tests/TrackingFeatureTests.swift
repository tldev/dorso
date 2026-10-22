import ComposableArchitecture
import XCTest

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

extension TrackingRuntimeClient {
    fileprivate static func recording(_ recorder: EffectIntentRecorder) -> Self {
        Self(perform: { intent in await recorder.record(intent) })
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
                airPodsCalibration: .valid,
                stateBeforeLock: nil
            )
        )

        await store.send(
            .toggleEnabled(detectorAvailable: false)
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
                cameraCalibration: .valid(),
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .toggleEnabled(detectorAvailable: true)
        ) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testInitialSetupEvaluatedInMarketingModeEmitsStartMonitoringOnly() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(initialState: TrackingFeature.State(isMarketingMode: true), recorder: recorder)

        await store.send(
            .initialSetupEvaluated(cameraProfile: nil, profileCameraAvailable: false)
        )
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testInitialSetupEvaluatedForCameraWithAvailableProfileAppliesProfileAndStartsMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                manualSource: .camera
            ),
            recorder: recorder
        )

        let profile = ProfileData(
            goodPostureY: 0.6, badPostureY: 0.4, neutralY: 0.5, postureRange: 0.2, cameraID: "cam")
        await store.send(.initialSetupEvaluated(cameraProfile: profile, profileCameraAvailable: true)) {
            $0.selectedCameraID = "cam"
            $0.cameraCalibration = CameraCalibrationData(profile: profile)
            $0.cameraReadiness.calibrated = true
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
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
            .initialSetupEvaluated(cameraProfile: nil, profileCameraAvailable: false)
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

        await store.send(.pauseOnTheGoSettingChanged(isEnabled: true)) {
            $0.pauseOnTheGoEnabled = true
        }
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

        await store.send(.postureReadingReceived(reading)) {
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

        await store.send(.postureReadingReceived(reading)) {
            $0.monitoringState.consecutiveGoodFrames = 1
            $0.lastPostureReadingTime = reading.timestamp
        }
        await store.finish()
        await assertIntents(
            [
                .trackAnalytics(interval: 1.5, isSlouching: false),
                .updateBlur,
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

        await store.send(.awayStateChanged(true)) {
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
                manualSource: .camera,
                isMarketingMode: true
            ),
            recorder: recorder
        )

        await store.send(.awayStateChanged(true))
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
                isMarketingMode: true,
                stateBeforeLock: nil
            )
        )

        await store.send(
            .startMonitoringRequested(isConnected: true)
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
            .startMonitoringRequested(isConnected: true)
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
                airPodsCalibration: .valid,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .startMonitoringRequested(isConnected: false)
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
                cameraCalibration: .valid(),
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .startMonitoringRequested(isConnected: true)
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

    // MARK: - Calibration and Camera Ownership

    private func profile(cameraID: String, goodY: CGFloat = 0.6) -> ProfileData {
        ProfileData(
            goodPostureY: goodY, badPostureY: goodY - 0.2, neutralY: goodY - 0.1, postureRange: 0.2, cameraID: cameraID)
    }

    @MainActor
    func testCalibrationChangesKeepReadinessInStep() async {
        let store = makeStore(initialState: TrackingFeature.State())

        await store.send(.cameraCalibrationChanged(.valid())) {
            $0.cameraCalibration = .valid()
            $0.cameraReadiness.calibrated = true
        }
        await store.send(.cameraCalibrationChanged(nil)) {
            $0.cameraCalibration = nil
            $0.cameraReadiness.calibrated = false
        }
    }

    @MainActor
    func testMarketingModeCountsEverySourceAsCalibrated() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(initialState: TrackingFeature.State(isMarketingMode: true), recorder: recorder)

        await store.send(.toggleEnabled(detectorAvailable: true)) {
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testDisplayChangeLoadsCalibrationWhenSelectedCameraAlreadyMatches() async {
        let recorder = EffectIntentRecorder()
        let desk = profile(cameraID: "builtin", goodY: 0.7)
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                cameraCalibration: .valid(cameraID: "builtin"),
                selectedCameraID: "builtin"
            ),
            recorder: recorder
        )

        await store.send(
            .displayConfigurationChanged(
                isLaptopOnlyConfiguration: false,
                hasAnyCamera: true,
                hasMatchingProfileCamera: true,
                matchingProfile: desk
            )
        ) {
            $0.cameraCalibration = CameraCalibrationData(profile: desk)
            $0.cameraReadiness.calibrated = true
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testDeskProfileWithConnectedCameraSelectsItAndSwitches() async {
        let recorder = EffectIntentRecorder()
        let desk = profile(cameraID: "external")
        let store = makeStore(
            initialState: TrackingFeature.State(selectedCameraID: "builtin"),
            recorder: recorder
        )

        await store.send(.deskProfileApplied(desk, isCameraAvailable: true)) {
            $0.selectedCameraID = "external"
            $0.cameraCalibration = CameraCalibrationData(profile: desk)
            $0.cameraReadiness.calibrated = true
        }
        await store.finish()
        await assertIntents([.switchCamera(to: "external")], recorder: recorder)
    }

    @MainActor
    func testDeskProfileWithSameCameraLoadsCalibrationWithoutSwitching() async {
        let recorder = EffectIntentRecorder()
        let desk = profile(cameraID: "builtin", goodY: 0.8)
        let store = makeStore(
            initialState: TrackingFeature.State(
                cameraCalibration: .valid(cameraID: "builtin"), selectedCameraID: "builtin"),
            recorder: recorder
        )

        await store.send(.deskProfileApplied(desk, isCameraAvailable: true)) {
            $0.cameraCalibration = CameraCalibrationData(profile: desk)
            $0.cameraReadiness.calibrated = true
        }
        await store.finish()
        await assertIntents([], recorder: recorder)
    }

    @MainActor
    func testDeskProfileWithMissingCameraClearsCalibration() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                cameraReadiness: TrackingSourceReadiness(calibrated: true),
                cameraCalibration: .valid(cameraID: "builtin"),
                selectedCameraID: "builtin"
            )
        )

        await store.send(.deskProfileApplied(profile(cameraID: "external"), isCameraAvailable: false)) {
            $0.cameraCalibration = nil
            $0.cameraReadiness.calibrated = false
        }
    }

    @MainActor
    func testDeskSwitchWhileMonitoringRestartsSessionWithoutDisplayRules() async {
        // Laptop-only with pause-on-the-go on: a desk switch must not pause
        let recorder = EffectIntentRecorder()
        let desk = profile(cameraID: "builtin", goodY: 0.8)
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                cameraCalibration: .valid(cameraID: "builtin"),
                selectedCameraID: "builtin",
                pauseOnTheGoEnabled: true
            ),
            recorder: recorder
        )

        await store.send(.deskProfileApplied(desk, isCameraAvailable: true)) {
            $0.cameraCalibration = CameraCalibrationData(profile: desk)
            $0.cameraReadiness.calibrated = true
        }
        await store.finish()
        await assertIntents([.beginMonitoringSession], recorder: recorder)
    }

    @MainActor
    func testDeskSwitchResumesTrackingPausedForMissingCalibration() async {
        let recorder = EffectIntentRecorder()
        let desk = profile(cameraID: "builtin")
        let store = makeStore(
            initialState: TrackingFeature.State(appState: .paused(.noProfile), selectedCameraID: "builtin"),
            recorder: recorder
        )

        await store.send(.deskProfileApplied(desk, isCameraAvailable: true)) {
            $0.cameraCalibration = CameraCalibrationData(profile: desk)
            $0.cameraReadiness.calibrated = true
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testDeskSwitchLeavesOtherPausesAlone() async {
        let desk = profile(cameraID: "builtin")
        for pause in [PauseReason.onTheGo, .onBattery, .screenLocked] {
            let store = makeStore(
                initialState: TrackingFeature.State(appState: .paused(pause), selectedCameraID: "builtin")
            )
            await store.send(.deskProfileApplied(desk, isCameraAvailable: true)) {
                $0.cameraCalibration = CameraCalibrationData(profile: desk)
                $0.cameraReadiness.calibrated = true
            }
        }
    }

    @MainActor
    func testDeskSwitchToMissingCameraWhileMonitoringPausesForCalibration() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                cameraReadiness: TrackingSourceReadiness(calibrated: true),
                cameraCalibration: .valid(cameraID: "builtin"),
                selectedCameraID: "builtin"
            )
        )

        await store.send(.deskProfileApplied(profile(cameraID: "external"), isCameraAvailable: false)) {
            $0.cameraCalibration = nil
            $0.cameraReadiness.calibrated = false
            $0.appState = .paused(.noProfile)
        }
    }

    @MainActor
    func testCameraConnectInAutomaticModeAppliesMatchingProfile() async {
        let recorder = EffectIntentRecorder()
        let desk = profile(cameraID: "external")
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.cameraDisconnected),
                trackingMode: .automatic,
                preferredSource: .camera,
                selectedCameraID: "builtin"
            ),
            recorder: recorder
        )

        await store.send(.cameraConnected(matchingProfile: desk)) {
            $0.cameraReadiness.connected = true
            $0.cameraReadiness.calibrated = true
            $0.selectedCameraID = "external"
            $0.cameraCalibration = CameraCalibrationData(profile: desk)
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents(
            [.switchCamera(to: "external"), .beginMonitoringSession, .persistTrackingSource, .syncUI],
            recorder: recorder)
    }

    // MARK: - Timed Pause

    @MainActor
    func testTimedPauseMasksMonitoringAndSchedulesEnd() async {
        let recorder = EffectIntentRecorder()
        let end = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                monitoringState: PostureMonitoringState(isCurrentlySlouching: true, postureWarningIntensity: 0.5)
            ),
            recorder: recorder
        )

        await store.send(.timedPauseRequested(until: end)) {
            $0.timedPauseEnd = end
            $0.monitoringState = PostureMonitoringState()
        }
        XCTAssertEqual(store.state.effectiveAppState, .paused(.timed(until: end)))
        await store.finish()
        await assertIntents([.scheduleTimedPauseEnd(end)], recorder: recorder)
    }

    @MainActor
    func testTimedPauseIgnoredWhileDisabled() async {
        let store = makeStore(initialState: TrackingFeature.State(appState: .disabled))
        await store.send(.timedPauseRequested(until: Date(timeIntervalSince1970: 1_000)))
    }

    @MainActor
    func testTimedPauseDropsPostureReadings() async {
        let end = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(
            initialState: TrackingFeature.State(appState: .monitoring, timedPauseEnd: end)
        )
        let reading = PostureReading(timestamp: Date(), isBadPosture: true, severity: 1)
        await store.send(.postureReadingReceived(reading))
    }

    @MainActor
    func testTimedPauseEndResumesMonitoringSession() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                timedPauseEnd: Date(timeIntervalSince1970: 1_000)
            ),
            recorder: recorder
        )

        await store.send(.timedPauseEnded) {
            $0.timedPauseEnd = nil
        }
        XCTAssertEqual(store.state.effectiveAppState, .monitoring)
        await store.finish()
        await assertIntents([.cancelTimedPauseEnd, .beginMonitoringSession], recorder: recorder)
    }

    @MainActor
    func testTimedPauseDeadlineReachedEndsMatchingPause() async {
        let recorder = EffectIntentRecorder()
        let end = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(
            initialState: TrackingFeature.State(appState: .monitoring, timedPauseEnd: end),
            recorder: recorder
        )

        await store.send(.timedPauseDeadlineReached(end)) {
            $0.timedPauseEnd = nil
        }
        await store.finish()
        await assertIntents([.cancelTimedPauseEnd, .beginMonitoringSession], recorder: recorder)
    }

    @MainActor
    func testStaleDeadlineFromReplacedTimerDoesNotEndNewerPause() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                timedPauseEnd: Date(timeIntervalSince1970: 2_000)
            ),
            recorder: recorder
        )

        await store.send(.timedPauseDeadlineReached(Date(timeIntervalSince1970: 1_000)))
        await store.finish()
        await assertIntents([], recorder: recorder)
    }

    @MainActor
    func testTimedPauseEndLandsInBatteryPauseThatStartedUnderneath() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                pauseOnBatteryEnabled: true,
                timedPauseEnd: Date(timeIntervalSince1970: 1_000)
            ),
            recorder: recorder
        )

        await store.send(.powerSourceChanged(isOnBattery: true)) {
            $0.isOnBattery = true
            $0.appState = .paused(.onBattery)
        }
        await store.send(.timedPauseEnded) {
            $0.timedPauseEnd = nil
        }
        XCTAssertEqual(store.state.effectiveAppState, .paused(.onBattery))
        await store.finish()
        await assertIntents([.cancelTimedPauseEnd], recorder: recorder)
    }

    @MainActor
    func testDisablingCancelsTimedPause() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                timedPauseEnd: Date(timeIntervalSince1970: 1_000)
            ),
            recorder: recorder
        )

        await store.send(.toggleEnabled(detectorAvailable: true)) {
            $0.appState = .disabled
            $0.timedPauseEnd = nil
        }
        await store.finish()
        await assertIntents([.cancelTimedPauseEnd], recorder: recorder)
    }

    @MainActor
    func testRecalibratingCancelsTimedPause() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                timedPauseEnd: Date(timeIntervalSince1970: 1_000)
            ),
            recorder: recorder
        )

        await store.send(.calibrationAuthorizationGranted) {
            $0.appState = .calibrating
            $0.timedPauseEnd = nil
        }
        await store.finish()
        await assertIntents([.cancelTimedPauseEnd], recorder: recorder)
    }

    // MARK: - Pause on Battery

    @MainActor
    func testPowerSourceChangesToBatteryPausesMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                pauseOnBatteryEnabled: true
            ),
            recorder: recorder
        )

        await store.send(.powerSourceChanged(isOnBattery: true)) {
            $0.isOnBattery = true
            $0.appState = .paused(.onBattery)
        }
        await store.finish()
        await assertIntents([], recorder: recorder)
    }

    @MainActor
    func testPowerSourceReturnsToACResumesMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.onBattery),
                pauseOnBatteryEnabled: true,
                isOnBattery: true
            ),
            recorder: recorder
        )

        await store.send(.powerSourceChanged(isOnBattery: false)) {
            $0.isOnBattery = false
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testPowerSourceChangeWithSettingDisabledOnlyRecordsBatteryState() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(appState: .monitoring),
            recorder: recorder
        )

        await store.send(.powerSourceChanged(isOnBattery: true)) {
            $0.isOnBattery = true
        }
        await store.finish()
        await assertIntents([], recorder: recorder)
    }

    @MainActor
    func testEnablingPauseOnBatteryWhileOnBatteryPauses() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                isOnBattery: true
            ),
            recorder: recorder
        )

        await store.send(.setPauseOnBatteryEnabled(true)) {
            $0.pauseOnBatteryEnabled = true
            $0.appState = .paused(.onBattery)
        }
        await store.finish()
        await assertIntents([], recorder: recorder)
    }

    @MainActor
    func testDisablingPauseOnBatteryResumesMonitoring() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.onBattery),
                pauseOnBatteryEnabled: true,
                isOnBattery: true
            ),
            recorder: recorder
        )

        await store.send(.setPauseOnBatteryEnabled(false)) {
            $0.pauseOnBatteryEnabled = false
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.startMonitoring], recorder: recorder)
    }

    @MainActor
    func testScreenUnlockOnBatteryLandsInBatteryPause() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                pauseOnBatteryEnabled: true
            ),
            recorder: recorder
        )

        await store.send(.screenLocked) {
            $0.appState = .paused(.screenLocked)
            $0.stateBeforeLock = .monitoring
        }

        // Unplugged while the screen was locked (e.g. lid closed and moved)
        await store.send(.powerSourceChanged(isOnBattery: true)) {
            $0.isOnBattery = true
        }

        await store.send(.screenUnlocked) {
            $0.appState = .paused(.onBattery)
            $0.stateBeforeLock = nil
        }
        await store.finish()
        await assertIntents([], recorder: recorder)
    }

    @MainActor
    func testAutomaticModeReadinessChangeDoesNotLiftBatteryPause() async {
        let recorder = EffectIntentRecorder()
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .paused(.onBattery),
                trackingMode: .automatic,
                manualSource: .camera,
                preferredSource: .airpods,
                autoReturnEnabled: true,
                pauseOnBatteryEnabled: true,
                isOnBattery: true
            ),
            recorder: recorder
        )

        let readiness = TrackingSourceReadiness(
            permissionGranted: true,
            connected: true,
            calibrated: true,
            available: true
        )
        await store.send(.sourceReadinessChanged(source: .airpods, readiness: readiness)) {
            $0.airPodsReadiness = readiness
        }
        await store.finish()
        await assertIntents([], recorder: recorder)
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
                selectedCameraID: "builtin",
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .cameraDisconnected(cameraID: "builtin", fallbackCameraID: "external", profile: nil)
        ) {
            $0.appState = .paused(.noProfile)
            $0.cameraReadiness.connected = true
            $0.selectedCameraID = "external"
        }
        await store.finish()
        await assertIntents([.switchCamera(to: "external")], recorder: recorder)
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
                cameraCalibration: .valid(),
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.calibrationAuthorizationDenied) {
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

        await store.send(.calibrationAuthorizationDenied) {
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
    func testCalibrationStartClearsSlouchWarning() async {
        let store = makeStore(
            initialState: TrackingFeature.State(
                appState: .monitoring,
                monitoringState: PostureMonitoringState(
                    consecutiveBadFrames: 12,
                    isCurrentlySlouching: true,
                    badPostureStartTime: Date(timeIntervalSince1970: 1_000),
                    postureWarningIntensity: 0.8
                ),
                lastPostureReadingTime: Date(timeIntervalSince1970: 1_000)
            )
        )

        await store.send(.calibrationAuthorizationGranted) {
            $0.appState = .calibrating
            $0.monitoringState = PostureMonitoringState()
            $0.lastPostureReadingTime = nil
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

        await store.send(.runtimeDetectorStartFailed) {
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

        await store.send(.runtimeDetectorStartFailed) {
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
                cameraCalibration: .valid(),
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.calibrationCancelled) {
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

        await store.send(.calibrationCancelled) {
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

        await store.send(.calibrationCompleted(.airPods(.valid))) {
            $0.airPodsCalibration = .valid
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

        let profile = ProfileData(
            goodPostureY: 0.6, badPostureY: 0.4, neutralY: 0.5, postureRange: 0.2, cameraID: "external")
        await store.send(.cameraConnected(matchingProfile: profile)) {
            $0.cameraReadiness.connected = true
            $0.cameraReadiness.calibrated = true
            $0.selectedCameraID = "external"
            $0.cameraCalibration = CameraCalibrationData(profile: profile)
            $0.appState = .monitoring
        }
        await store.finish()
        await assertIntents([.switchCamera(to: "external"), .startMonitoring], recorder: recorder)
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
                selectedCameraID: "builtin",
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(
            .cameraDisconnected(cameraID: "external", fallbackCameraID: "builtin", profile: nil)
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
                stateBeforeLock: nil,
                pauseOnTheGoEnabled: true
            )
        ) {
            TrackingFeature()
        }

        await store.send(
            .displayConfigurationChanged(
                isLaptopOnlyConfiguration: true,
                hasAnyCamera: true,
                hasMatchingProfileCamera: true,
                matchingProfile: nil
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
                selectedCameraID: "builtin",
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        let profile = ProfileData(
            goodPostureY: 0.6, badPostureY: 0.4, neutralY: 0.5, postureRange: 0.2, cameraID: "external")
        await store.send(
            .displayConfigurationChanged(
                isLaptopOnlyConfiguration: false,
                hasAnyCamera: true,
                hasMatchingProfileCamera: true,
                matchingProfile: profile
            )
        ) {
            $0.appState = .monitoring
            $0.selectedCameraID = "external"
            $0.cameraCalibration = CameraCalibrationData(profile: profile)
            $0.cameraReadiness.calibrated = true
        }
        await store.finish()
        await assertIntents([.switchCamera(to: "external"), .startMonitoring], recorder: recorder)
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
                isLaptopOnlyConfiguration: false,
                hasAnyCamera: false,
                hasMatchingProfileCamera: false,
                matchingProfile: nil
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

        await store.send(.cameraSelectionChanged("external")) {
            $0.selectedCameraID = "external"
            $0.appState = .paused(.noProfile)
        }
        await store.finish()
        await assertIntents([.switchCamera(to: "external")], recorder: recorder)
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

        await store.send(.switchTrackingSource(.airpods)) {
            $0.appState = .paused(.noProfile)
            $0.manualSource = .airpods
            $0.activeSource = .airpods
        }
        await store.finish()
        await assertIntents(
            [
                .stopDetector(.camera),
                .persistTrackingSource,
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
                airPodsCalibration: .valid,
                stateBeforeLock: nil
            ),
            recorder: recorder
        )

        await store.send(.switchTrackingSource(.airpods)) {
            $0.appState = .monitoring
            $0.manualSource = .airpods
            $0.activeSource = .airpods
        }
        await store.finish()
        await assertIntents(
            [
                .stopDetector(.camera),
                .persistTrackingSource,
                .startMonitoring,
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

        await store.send(.switchTrackingSource(.camera))
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

        await store.send(.calibrationCompleted(.camera(.valid()))) {
            $0.cameraCalibration = .valid()
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

        await store.send(.calibrationCompleted(.airPods(.valid))) {
            $0.airPodsCalibration = .valid
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
