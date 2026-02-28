import AppKit
import XCTest
@testable import DorsoCore

final class AppDelegateTrackingIntegrationTests: XCTestCase {
    private func makeValidCameraCalibration(cameraID: String) -> CameraCalibrationData {
        CameraCalibrationData(
            goodPostureY: 0.6,
            badPostureY: 0.4,
            neutralY: 0.5,
            postureRange: 0.2,
            cameraID: cameraID
        )
    }

    private func makeValidAirPodsCalibration() -> AirPodsCalibrationData {
        AirPodsCalibrationData(
            pitch: 0.1,
            roll: -0.2,
            yaw: 0.05
        )
    }

    @MainActor
    func testInitialSetupFlowInMarketingModeRequestsMonitoringAndSkipsOnboarding() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.marketingModeOverride = true

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        var onboardingCalls = 0
        appDelegate.showOnboardingHandler = {
            onboardingCalls += 1
        }

        await appDelegate.initialSetupFlow()

        XCTAssertEqual(executedIntents, [.startMonitoring])
        XCTAssertEqual(onboardingCalls, 0)
        XCTAssertEqual(appDelegate.state, .monitoring)
        XCTAssertTrue(appDelegate.setupComplete)
    }

    @MainActor
    func testInitialSetupFlowForCameraWithAvailableProfileAppliesProfileAndStartsMonitoring() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.beginMonitoringSessionHandler = {}
        appDelegate.marketingModeOverride = false
        appDelegate.trackingSource = .camera

        let profile = ProfileData(
            goodPostureY: 0.58,
            badPostureY: 0.42,
            neutralY: 0.5,
            postureRange: 0.16,
            cameraID: "startup-camera"
        )
        appDelegate.initialSetupContextOverride = {
            InitialSetupContext(
                profile: profile,
                profileCameraAvailable: true,
                hasValidAirPodsCalibration: false
            )
        }

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        var onboardingCalls = 0
        appDelegate.showOnboardingHandler = {
            onboardingCalls += 1
        }

        await appDelegate.initialSetupFlow()

        XCTAssertEqual(executedIntents, [.applyStartupCameraProfile(profile), .startMonitoring, .beginMonitoringSession])
        XCTAssertEqual(onboardingCalls, 0)
        XCTAssertEqual(appDelegate.selectedCameraID, profile.cameraID)
        XCTAssertEqual(appDelegate.cameraCalibration?.cameraID, profile.cameraID)
        XCTAssertEqual(appDelegate.state, .monitoring)
    }

    @MainActor
    func testInitialSetupFlowForAirPodsWithCalibrationStartsMonitoringWithoutOnboarding() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.beginMonitoringSessionHandler = {}
        appDelegate.marketingModeOverride = false
        appDelegate.trackingSource = .airpods
        appDelegate.airPodsCalibration = makeValidAirPodsCalibration()
        appDelegate.initialSetupContextOverride = {
            InitialSetupContext(
                profile: nil,
                profileCameraAvailable: false,
                hasValidAirPodsCalibration: true
            )
        }

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        var onboardingCalls = 0
        appDelegate.showOnboardingHandler = {
            onboardingCalls += 1
        }

        await appDelegate.initialSetupFlow()

        XCTAssertTrue(executedIntents.contains(.startMonitoring))
        XCTAssertTrue(executedIntents.contains(.beginMonitoringSession))
        XCTAssertFalse(executedIntents.contains(.showOnboarding))
        XCTAssertEqual(onboardingCalls, 0)
        XCTAssertNotEqual(appDelegate.state, .disabled)
    }

    @MainActor
    func testInitialSetupFlowWithoutValidPathShowsOnboarding() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.marketingModeOverride = false
        appDelegate.trackingSource = .camera
        appDelegate.initialSetupContextOverride = {
            InitialSetupContext(
                profile: nil,
                profileCameraAvailable: false,
                hasValidAirPodsCalibration: false
            )
        }

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        var onboardingCalls = 0
        appDelegate.showOnboardingHandler = {
            onboardingCalls += 1
        }

        await appDelegate.initialSetupFlow()

        XCTAssertEqual(executedIntents, [.showOnboarding])
        XCTAssertEqual(onboardingCalls, 1)
        XCTAssertEqual(appDelegate.state, .disabled)
    }

    @MainActor
    func testSetPauseOnTheGoEnabledFalseFromOnTheGoPauseResumesMonitoringThroughReducer() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.state = .paused(.onTheGo)

        await appDelegate.setPauseOnTheGoEnabled(false)

        XCTAssertFalse(appDelegate.pauseOnTheGo)
        XCTAssertEqual(appDelegate.state, .monitoring)
    }

    @MainActor
    func testSetPauseOnTheGoEnabledTrueKeepsOnTheGoPauseState() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.state = .paused(.onTheGo)

        await appDelegate.setPauseOnTheGoEnabled(true)

        XCTAssertTrue(appDelegate.pauseOnTheGo)
        XCTAssertEqual(appDelegate.state, .paused(.onTheGo))
    }

    @MainActor
    func testCameraConnectedTransitionExecutesSwitchBeforeStartAndPreservesRuntimeFallbackState() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .paused(.cameraDisconnected)

        let profile = ProfileData(
            goodPostureY: 0.6,
            badPostureY: 0.4,
            neutralY: 0.5,
            postureRange: 0.0,
            cameraID: "camera-hot-plug"
        )

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchCameraConnectedTransitionForTesting(
            hasMatchingProfile: true,
            matchingProfile: profile
        )

        let expectedIntents: [TrackingFeature.EffectIntent] = [
            .switchCamera(.matchingProfile(profile)),
            .startMonitoring
        ]

        XCTAssertEqual(executedIntents, expectedIntents)
        XCTAssertEqual(appDelegate.selectedCameraID, profile.cameraID)
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testCameraConnectWithoutMatchingProfileFromDisconnectedPausesNoProfileWithoutRecoveryIntents() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .paused(.cameraDisconnected)

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchCameraConnectedTransitionForTesting(
            hasMatchingProfile: false,
            matchingProfile: nil
        )

        XCTAssertEqual(executedIntents, [])
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testDisplayConfigurationTransitionExecutesSwitchBeforeStartAndPreservesRuntimeFallbackState() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .paused(.cameraDisconnected)

        let profile = ProfileData(
            goodPostureY: 0.65,
            badPostureY: 0.35,
            neutralY: 0.5,
            postureRange: 0.0,
            cameraID: "camera-display"
        )

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchDisplayConfigurationTransitionForTesting(
            pauseOnTheGoEnabled: false,
            isLaptopOnlyConfiguration: false,
            hasAnyCamera: true,
            hasMatchingProfileCamera: true,
            selectedCameraMatchesProfile: false,
            matchingProfile: profile
        )

        let expectedIntents: [TrackingFeature.EffectIntent] = [
            .switchCamera(.matchingProfile(profile)),
            .startMonitoring
        ]

        XCTAssertEqual(executedIntents, expectedIntents)
        XCTAssertEqual(appDelegate.selectedCameraID, profile.cameraID)
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testCameraDisconnectWithFallbackProfileExecutesSwitchBeforeStartAndPreservesRuntimeFallbackState() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .monitoring

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchCameraDisconnectedTransitionForTesting(
            disconnectedCameraIsSelected: true,
            hasFallbackCamera: true,
            fallbackHasMatchingProfile: true,
            fallbackCamera: nil,
            fallbackProfile: nil
        )

        let expectedIntents: [TrackingFeature.EffectIntent] = [
            .switchCamera(.fallback()),
            .startMonitoring
        ]

        XCTAssertEqual(executedIntents, expectedIntents)
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testCameraDisconnectWithFallbackNoProfileCommitsReducerPauseWithoutRestartIntent() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .monitoring

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchCameraDisconnectedTransitionForTesting(
            disconnectedCameraIsSelected: true,
            hasFallbackCamera: true,
            fallbackHasMatchingProfile: false,
            fallbackCamera: nil,
            fallbackProfile: nil
        )

        let expectedIntents: [TrackingFeature.EffectIntent] = [
            .switchCamera(.fallback())
        ]

        XCTAssertEqual(executedIntents, expectedIntents)
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testCameraDisconnectWithoutFallbackPausesDisconnectedWithoutEffects() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .monitoring

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchCameraDisconnectedTransitionForTesting(
            disconnectedCameraIsSelected: true,
            hasFallbackCamera: false,
            fallbackHasMatchingProfile: false,
            fallbackCamera: nil,
            fallbackProfile: nil
        )

        XCTAssertEqual(executedIntents, [])
        XCTAssertEqual(appDelegate.state, .paused(.cameraDisconnected))
    }

    @MainActor
    func testCameraDisconnectForNonSelectedCameraRequestsUISyncOnlyAndKeepsState() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .monitoring

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchCameraDisconnectedTransitionForTesting(
            disconnectedCameraIsSelected: false,
            hasFallbackCamera: true,
            fallbackHasMatchingProfile: true,
            fallbackCamera: nil,
            fallbackProfile: nil
        )

        XCTAssertEqual(executedIntents, [.syncUI])
        XCTAssertEqual(appDelegate.state, .monitoring)
    }

    @MainActor
    func testDisplayPauseOnTheGoPrecedenceSuppressesSwitchAndRestartIntents() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .monitoring

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchDisplayConfigurationTransitionForTesting(
            pauseOnTheGoEnabled: true,
            isLaptopOnlyConfiguration: true,
            hasAnyCamera: true,
            hasMatchingProfileCamera: true,
            selectedCameraMatchesProfile: false,
            matchingProfile: nil
        )

        XCTAssertEqual(executedIntents, [])
        XCTAssertEqual(appDelegate.state, .paused(.onTheGo))
    }

    @MainActor
    func testDisplayChangeWithoutAnyCameraPausesDisconnectedWithoutRecoveryIntents() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .monitoring

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchDisplayConfigurationTransitionForTesting(
            pauseOnTheGoEnabled: false,
            isLaptopOnlyConfiguration: false,
            hasAnyCamera: false,
            hasMatchingProfileCamera: false,
            selectedCameraMatchesProfile: false,
            matchingProfile: nil
        )

        XCTAssertEqual(executedIntents, [])
        XCTAssertEqual(appDelegate.state, .paused(.cameraDisconnected))
    }

    @MainActor
    func testDisplayChangeWithoutMatchingProfilePausesNoProfileWithoutRecoveryIntents() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .monitoring

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchDisplayConfigurationTransitionForTesting(
            pauseOnTheGoEnabled: false,
            isLaptopOnlyConfiguration: false,
            hasAnyCamera: true,
            hasMatchingProfileCamera: false,
            selectedCameraMatchesProfile: false,
            matchingProfile: nil
        )

        XCTAssertEqual(executedIntents, [])
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testScreenLockUnlockFromMonitoringEmitsRestartIntentAndExitsScreenLockedState() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .monitoring

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        let lockIntentStartIndex = executedIntents.count
        await appDelegate.dispatchScreenLockedTransitionForTesting()
        XCTAssertEqual(Array(executedIntents.dropFirst(lockIntentStartIndex)), [])
        XCTAssertEqual(appDelegate.state, .paused(.screenLocked))

        let unlockIntentStartIndex = executedIntents.count
        await appDelegate.dispatchScreenUnlockedTransitionForTesting()
        XCTAssertEqual(Array(executedIntents.dropFirst(unlockIntentStartIndex)), [.startMonitoring])
        XCTAssertTrue(executedIntents.contains(.startMonitoring))
        XCTAssertNotEqual(appDelegate.state, .paused(.screenLocked))
    }

    @MainActor
    func testCameraSelectionTransitionEmitsSelectedCameraSwitchAndPausesNoProfile() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .monitoring
        appDelegate.trackingSource = .camera
        appDelegate.selectedCameraID = "camera-selected"

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchCameraSelectionTransitionForTesting()

        XCTAssertEqual(executedIntents, [.switchCamera(.selectedCamera)])
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testManualSourceSwitchToUncalibratedSourceStopsSetsAndPersistsWithoutRestartIntent() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .disabled
        appDelegate.trackingSource = .camera
        appDelegate.cameraCalibration = nil
        appDelegate.airPodsCalibration = nil

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchSwitchTrackingSourceTransitionForTesting(.airpods)
        let expectedIntents: [TrackingFeature.EffectIntent] = [
            .stopDetector(.camera),
            .setTrackingSource(.airpods),
            .persistTrackingSource
        ]

        XCTAssertEqual(executedIntents, expectedIntents)
        XCTAssertEqual(appDelegate.trackingSource, .airpods)
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testManualSourceSwitchToCalibratedSourceEmitsRestartAfterStopSetPersist() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .disabled
        appDelegate.trackingSource = .airpods
        appDelegate.cameraCalibration = makeValidCameraCalibration(cameraID: "camera-switch")
        appDelegate.airPodsCalibration = nil

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.dispatchSwitchTrackingSourceTransitionForTesting(.camera)
        let expectedPrefix: [TrackingFeature.EffectIntent] = [
            .stopDetector(.airpods),
            .setTrackingSource(.camera),
            .persistTrackingSource,
            .startMonitoring
        ]

        XCTAssertEqual(Array(executedIntents.prefix(expectedPrefix.count)), expectedPrefix)
        XCTAssertEqual(appDelegate.trackingSource, .camera)
        XCTAssertEqual(appDelegate.state, .monitoring)
    }

    @MainActor
    func testCancelCalibrationWhenCalibratedEmitsRestartIntentAndReturnsMonitoring() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .calibrating
        appDelegate.trackingSource = .camera
        appDelegate.cameraCalibration = makeValidCameraCalibration(cameraID: "camera-cancel")

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.cancelCalibration()

        XCTAssertTrue(executedIntents.contains(.startMonitoring))
        XCTAssertEqual(appDelegate.state, .monitoring)
    }

    @MainActor
    func testCancelCalibrationWhenUncalibratedPausesNoProfileWithoutRestartIntent() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .calibrating
        appDelegate.trackingSource = .camera
        appDelegate.cameraCalibration = nil

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        await appDelegate.cancelCalibration()

        XCTAssertFalse(executedIntents.contains(.startMonitoring))
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testFinishCalibrationEmitsResetThenRestartAndTransitionsToMonitoring() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }

        appDelegate.state = .calibrating
        appDelegate.trackingSource = .camera
        appDelegate.selectedCameraID = "camera-finish"

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        let samples: [CalibrationSample] = [
            .camera(.init(noseY: 0.4, faceWidth: 0.2)),
            .camera(.init(noseY: 0.5, faceWidth: 0.21)),
            .camera(.init(noseY: 0.6, faceWidth: 0.19)),
            .camera(.init(noseY: 0.55, faceWidth: 0.22))
        ]
        await appDelegate.finishCalibration(values: samples)

        let expectedPrefix: [TrackingFeature.EffectIntent] = [
            .resetMonitoringState,
            .startMonitoring
        ]
        XCTAssertEqual(Array(executedIntents.prefix(expectedPrefix.count)), expectedPrefix)
        XCTAssertEqual(appDelegate.state, .monitoring)
    }

    @MainActor
    func testCalibrationAuthorizationDeniedWithOpenSettingsDecisionExecutesOpenSettingsIntent() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}

        appDelegate.state = .calibrating
        appDelegate.trackingSource = .camera
        appDelegate.cameraCalibration = nil

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        var openSettingsInvocations = 0
        appDelegate.calibrationPermissionDeniedAlertDecision = { source in
            XCTAssertEqual(source, .camera)
            return true
        }
        appDelegate.openPrivacySettingsHandler = {
            openSettingsInvocations += 1
        }

        await appDelegate.dispatchCalibrationAuthorizationDeniedTransitionForTesting()

        XCTAssertEqual(executedIntents, [.showCalibrationPermissionDeniedAlert, .openPrivacySettings])
        XCTAssertEqual(openSettingsInvocations, 1)
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testCalibrationAuthorizationDeniedWithCancelDecisionSkipsOpenSettingsIntent() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}

        appDelegate.state = .calibrating
        appDelegate.trackingSource = .camera
        appDelegate.cameraCalibration = nil

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        var openSettingsInvocations = 0
        appDelegate.calibrationPermissionDeniedAlertDecision = { _ in false }
        appDelegate.openPrivacySettingsHandler = {
            openSettingsInvocations += 1
        }

        await appDelegate.dispatchCalibrationAuthorizationDeniedTransitionForTesting()

        XCTAssertEqual(executedIntents, [.showCalibrationPermissionDeniedAlert])
        XCTAssertEqual(openSettingsInvocations, 0)
        XCTAssertEqual(appDelegate.state, .paused(.noProfile))
    }

    @MainActor
    func testCalibrationStartFailedForCameraWithRetryDecisionExecutesRetryIntent() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}

        appDelegate.state = .calibrating
        appDelegate.trackingSource = .camera

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        var retryInvocations = 0
        appDelegate.cameraCalibrationRetryAlertDecision = { message in
            XCTAssertEqual(message, "camera unavailable")
            return true
        }
        appDelegate.retryCalibrationHandler = {
            retryInvocations += 1
        }

        await appDelegate.dispatchCalibrationStartFailedTransitionForTesting(
            errorMessage: "camera unavailable"
        )

        XCTAssertEqual(
            executedIntents,
            [.showCameraCalibrationRetryAlert(message: "camera unavailable"), .retryCalibration]
        )
        XCTAssertEqual(retryInvocations, 1)
        XCTAssertEqual(appDelegate.state, .paused(.cameraDisconnected))
    }

    @MainActor
    func testCalibrationStartFailedForCameraWithCancelDecisionSkipsRetryIntent() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}

        appDelegate.state = .calibrating
        appDelegate.trackingSource = .camera

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        var retryInvocations = 0
        appDelegate.cameraCalibrationRetryAlertDecision = { _ in false }
        appDelegate.retryCalibrationHandler = {
            retryInvocations += 1
        }

        await appDelegate.dispatchCalibrationStartFailedTransitionForTesting(
            errorMessage: nil
        )

        XCTAssertEqual(executedIntents, [.showCameraCalibrationRetryAlert(message: nil)])
        XCTAssertEqual(retryInvocations, 0)
        XCTAssertEqual(appDelegate.state, .paused(.cameraDisconnected))
    }

    @MainActor
    func testCalibrationStartFailedForAirPodsDoesNotEmitRetryAlertIntent() async {
        let appDelegate = AppDelegate()
        appDelegate.syncDetectorToStateOverride = {}
        appDelegate.menuBarManager.setup()
        defer { NSStatusBar.system.removeStatusItem(appDelegate.menuBarManager.statusItem) }
        appDelegate.syncDetectorToStateOverride = {}

        appDelegate.state = .paused(.airPodsRemoved)
        appDelegate.trackingSource = .airpods

        var executedIntents: [TrackingFeature.EffectIntent] = []
        appDelegate.trackingEffectIntentObserver = { intent in
            executedIntents.append(intent)
        }

        var retryAlertDecisionCalls = 0
        appDelegate.cameraCalibrationRetryAlertDecision = { _ in
            retryAlertDecisionCalls += 1
            return false
        }

        await appDelegate.dispatchCalibrationStartFailedTransitionForTesting(
            errorMessage: "ignored"
        )

        XCTAssertEqual(executedIntents, [])
        XCTAssertEqual(retryAlertDecisionCalls, 0)
        XCTAssertEqual(appDelegate.state, .paused(.airPodsRemoved))
    }
}
