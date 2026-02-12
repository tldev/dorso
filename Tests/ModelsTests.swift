import XCTest
@testable import PosturrCore

final class ModelsTests: XCTestCase {

    // MARK: - AppState Tests

    func testIsActiveForMonitoring() {
        XCTAssertTrue(AppState.monitoring.isActive)
    }

    func testIsActiveForCalibrating() {
        XCTAssertTrue(AppState.calibrating.isActive)
    }

    func testIsActiveForDisabled() {
        XCTAssertFalse(AppState.disabled.isActive)
    }

    func testIsActiveForPausedNoProfile() {
        XCTAssertFalse(AppState.paused(.noProfile).isActive)
    }

    func testIsActiveForPausedOnTheGo() {
        XCTAssertFalse(AppState.paused(.onTheGo).isActive)
    }

    func testIsActiveForPausedCameraDisconnected() {
        XCTAssertFalse(AppState.paused(.cameraDisconnected).isActive)
    }

    func testIsActiveForPausedScreenLocked() {
        XCTAssertFalse(AppState.paused(.screenLocked).isActive)
    }

    func testIsActiveForPausedAirPodsRemoved() {
        XCTAssertFalse(AppState.paused(.airPodsRemoved).isActive)
    }

    func testAppStateEquatable() {
        XCTAssertEqual(AppState.paused(.noProfile), AppState.paused(.noProfile))
        XCTAssertNotEqual(AppState.paused(.noProfile), AppState.paused(.screenLocked))
        XCTAssertNotEqual(AppState.disabled, AppState.monitoring)
        XCTAssertEqual(AppState.monitoring, AppState.monitoring)
        XCTAssertEqual(AppState.calibrating, AppState.calibrating)
        XCTAssertEqual(AppState.disabled, AppState.disabled)
    }

    // MARK: - TrackingSource Tests

    func testTrackingSourceRawValues() {
        XCTAssertEqual(TrackingSource.camera.rawValue, "camera")
        XCTAssertEqual(TrackingSource.airpods.rawValue, "airpods")
    }

    func testTrackingSourceDisplayName() {
        XCTAssertEqual(TrackingSource.camera.displayName, "Camera")
        XCTAssertEqual(TrackingSource.airpods.displayName, "AirPods")
    }

    func testTrackingSourceIcon() {
        XCTAssertEqual(TrackingSource.camera.icon, "camera")
        XCTAssertEqual(TrackingSource.airpods.icon, "airpodspro")
    }

    func testTrackingSourceDescription() {
        XCTAssertTrue(TrackingSource.camera.description.contains("camera"))
        XCTAssertTrue(TrackingSource.airpods.description.contains("motion sensors"))
    }

    func testTrackingSourceRequirementDescription() {
        XCTAssertEqual(TrackingSource.camera.requirementDescription, "Requires camera access")
        XCTAssertTrue(TrackingSource.airpods.requirementDescription.contains("macOS 14+"))
    }

    func testTrackingSourceCaseIterable() {
        XCTAssertEqual(TrackingSource.allCases.count, 2)
        XCTAssertTrue(TrackingSource.allCases.contains(.camera))
        XCTAssertTrue(TrackingSource.allCases.contains(.airpods))
    }

    func testTrackingSourceCodableRoundtrip() throws {
        for source in TrackingSource.allCases {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(TrackingSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }

    // MARK: - CameraCalibrationData Tests

    func testCameraCalibrationDataIsValidWhenValid() {
        let data = CameraCalibrationData(
            goodPostureY: 0.5, badPostureY: 0.3, neutralY: 0.4,
            postureRange: 0.2, cameraID: "FaceTimeHD"
        )
        XCTAssertTrue(data.isValid)
    }

    func testCameraCalibrationDataIsInvalidWhenPostureRangeTooSmall() {
        let data = CameraCalibrationData(
            goodPostureY: 0.5, badPostureY: 0.3, neutralY: 0.4,
            postureRange: 0.01, cameraID: "FaceTimeHD"
        )
        XCTAssertFalse(data.isValid)
    }

    func testCameraCalibrationDataIsInvalidWhenPostureRangeZero() {
        let data = CameraCalibrationData(
            goodPostureY: 0.5, badPostureY: 0.3, neutralY: 0.4,
            postureRange: 0.0, cameraID: "FaceTimeHD"
        )
        XCTAssertFalse(data.isValid)
    }

    func testCameraCalibrationDataIsInvalidWhenCameraIDEmpty() {
        let data = CameraCalibrationData(
            goodPostureY: 0.5, badPostureY: 0.3, neutralY: 0.4,
            postureRange: 0.2, cameraID: ""
        )
        XCTAssertFalse(data.isValid)
    }

    func testCameraCalibrationDataIsInvalidWhenBothInvalid() {
        let data = CameraCalibrationData(
            goodPostureY: 0.5, badPostureY: 0.3, neutralY: 0.4,
            postureRange: 0.005, cameraID: ""
        )
        XCTAssertFalse(data.isValid)
    }

    // MARK: - AirPodsCalibrationData Tests

    func testAirPodsCalibrationDataIsAlwaysValid() {
        let data = AirPodsCalibrationData(pitch: 0.1, roll: 0.2, yaw: 0.3)
        XCTAssertTrue(data.isValid)
    }

    func testAirPodsCalibrationDataIsValidWithZeros() {
        let data = AirPodsCalibrationData(pitch: 0, roll: 0, yaw: 0)
        XCTAssertTrue(data.isValid)
    }

    // MARK: - CalibrationSample Tests

    func testCalibrationSampleCameraEquatable() {
        let sample1 = CalibrationSample.camera(CameraCalibrationSample(noseY: 0.5, faceWidth: 0.3))
        let sample2 = CalibrationSample.camera(CameraCalibrationSample(noseY: 0.5, faceWidth: 0.3))
        let sample3 = CalibrationSample.camera(CameraCalibrationSample(noseY: 0.6, faceWidth: 0.3))
        XCTAssertEqual(sample1, sample2)
        XCTAssertNotEqual(sample1, sample3)
    }

    func testCalibrationSampleAirPodsEquatable() {
        let sample1 = CalibrationSample.airPods(AirPodsCalibrationSample(pitch: 0.1, roll: 0.2, yaw: 0.3))
        let sample2 = CalibrationSample.airPods(AirPodsCalibrationSample(pitch: 0.1, roll: 0.2, yaw: 0.3))
        let sample3 = CalibrationSample.airPods(AirPodsCalibrationSample(pitch: 0.4, roll: 0.2, yaw: 0.3))
        XCTAssertEqual(sample1, sample2)
        XCTAssertNotEqual(sample1, sample3)
    }

    func testCalibrationSampleMixedTypesNotEqual() {
        let cameraSample = CalibrationSample.camera(CameraCalibrationSample(noseY: 0.1, faceWidth: nil))
        let airPodsSample = CalibrationSample.airPods(AirPodsCalibrationSample(pitch: 0.1, roll: 0.2, yaw: 0.3))
        XCTAssertNotEqual(cameraSample, airPodsSample)
    }

    func testCameraCalibrationSampleEquatable() {
        let a = CameraCalibrationSample(noseY: 0.5, faceWidth: 0.3)
        let b = CameraCalibrationSample(noseY: 0.5, faceWidth: 0.3)
        let c = CameraCalibrationSample(noseY: 0.5, faceWidth: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testAirPodsCalibrationSampleEquatable() {
        let a = AirPodsCalibrationSample(pitch: 0.1, roll: 0.2, yaw: 0.3)
        let b = AirPodsCalibrationSample(pitch: 0.1, roll: 0.2, yaw: 0.3)
        let c = AirPodsCalibrationSample(pitch: 0.1, roll: 0.2, yaw: 0.4)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - WarningMode Tests

    func testWarningModeUsesWarningOverlayForGlow() {
        XCTAssertTrue(WarningMode.glow.usesWarningOverlay)
    }

    func testWarningModeUsesWarningOverlayForBorder() {
        XCTAssertTrue(WarningMode.border.usesWarningOverlay)
    }

    func testWarningModeUsesWarningOverlayForSolid() {
        XCTAssertTrue(WarningMode.solid.usesWarningOverlay)
    }

    func testWarningModeDoesNotUseWarningOverlayForBlur() {
        XCTAssertFalse(WarningMode.blur.usesWarningOverlay)
    }

    func testWarningModeDoesNotUseWarningOverlayForNone() {
        XCTAssertFalse(WarningMode.none.usesWarningOverlay)
    }

    func testWarningModeRawValues() {
        XCTAssertEqual(WarningMode.blur.rawValue, "blur")
        XCTAssertEqual(WarningMode.glow.rawValue, "glow")
        XCTAssertEqual(WarningMode.border.rawValue, "border")
        XCTAssertEqual(WarningMode.solid.rawValue, "solid")
        XCTAssertEqual(WarningMode.none.rawValue, "none")
    }

    func testWarningModeCaseIterable() {
        XCTAssertEqual(WarningMode.allCases.count, 5)
        XCTAssertTrue(WarningMode.allCases.contains(.blur))
        XCTAssertTrue(WarningMode.allCases.contains(.glow))
        XCTAssertTrue(WarningMode.allCases.contains(.border))
        XCTAssertTrue(WarningMode.allCases.contains(.solid))
        XCTAssertTrue(WarningMode.allCases.contains(.none))
    }

    func testWarningModeCodableRoundtrip() throws {
        for mode in WarningMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(WarningMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - DetectionMode Tests

    func testDetectionModeFrameRates() {
        XCTAssertEqual(DetectionMode.responsive.frameRate, 10.0)
        XCTAssertEqual(DetectionMode.balanced.frameRate, 4.0)
        XCTAssertEqual(DetectionMode.performance.frameRate, 2.0)
    }

    func testDetectionModeDisplayNames() {
        XCTAssertEqual(DetectionMode.responsive.displayName, "Responsive")
        XCTAssertEqual(DetectionMode.balanced.displayName, "Balanced")
        XCTAssertEqual(DetectionMode.performance.displayName, "Performance")
    }

    func testDetectionModeRawValues() {
        XCTAssertEqual(DetectionMode.responsive.rawValue, "responsive")
        XCTAssertEqual(DetectionMode.balanced.rawValue, "balanced")
        XCTAssertEqual(DetectionMode.performance.rawValue, "performance")
    }

    func testDetectionModeCodableRoundtrip() throws {
        for mode in DetectionMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(DetectionMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - KeyboardShortcut Tests

    func testDefaultShortcutKeyCode() {
        XCTAssertEqual(KeyboardShortcut.defaultShortcut.keyCode, 35)
    }

    func testDefaultShortcutModifiers() {
        XCTAssertTrue(KeyboardShortcut.defaultShortcut.modifiers.contains(.control))
        XCTAssertTrue(KeyboardShortcut.defaultShortcut.modifiers.contains(.option))
    }

    func testDefaultShortcutDisplayString() {
        XCTAssertEqual(KeyboardShortcut.defaultShortcut.displayString, "⌃⌥P")
    }

    func testDisplayStringWithCommandShift() {
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift])
        XCTAssertEqual(shortcut.displayString, "⇧⌘A")
    }

    func testDisplayStringWithAllModifiers() {
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.control, .option, .shift, .command])
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘A")
    }

    func testDisplayStringWithNoModifiers() {
        let shortcut = KeyboardShortcut(keyCode: 49, modifiers: [])
        XCTAssertEqual(shortcut.displayString, "Space")
    }

    func testKeyCharacterReturnsLowercase() {
        XCTAssertEqual(KeyboardShortcut.defaultShortcut.keyCharacter, "p")
    }

    func testKeyCharacterForLetterA() {
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command])
        XCTAssertEqual(shortcut.keyCharacter, "a")
    }

    func testKeyboardShortcutEquatable() {
        let a = KeyboardShortcut(keyCode: 35, modifiers: [.control, .option])
        let b = KeyboardShortcut(keyCode: 35, modifiers: [.control, .option])
        let c = KeyboardShortcut(keyCode: 0, modifiers: [.command])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - PostureReading Tests

    func testPostureReadingGood() {
        let reading = PostureReading.good
        XCTAssertFalse(reading.isBadPosture)
        XCTAssertEqual(reading.severity, 0)
    }

    // MARK: - DailyStats Tests

    func testDayKeyFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2025, month: 3, day: 15)
        let date = calendar.date(from: components)!
        let key = DailyStats.dayKey(for: date, calendar: calendar)
        XCTAssertEqual(key, "2025-03-15")
    }

    func testDayKeyInstanceProperty() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2025, month: 1, day: 5)
        let date = calendar.date(from: components)!
        let stats = DailyStats(date: date, totalSeconds: 100, slouchSeconds: 10, slouchCount: 1)
        // dayKey uses Calendar.current, so use the static method for controlled test
        let expected = DailyStats.dayKey(for: date)
        XCTAssertEqual(stats.dayKey, expected)
    }

    func testPostureScoreZeroWhenNoTime() {
        let stats = DailyStats(date: Date(), totalSeconds: 0, slouchSeconds: 0, slouchCount: 0)
        XCTAssertEqual(stats.postureScore, 0.0)
    }

    func testPostureScorePerfectWhenNoSlouching() {
        let stats = DailyStats(date: Date(), totalSeconds: 3600, slouchSeconds: 0, slouchCount: 0)
        XCTAssertEqual(stats.postureScore, 100.0)
    }

    func testPostureScoreFiftyWhenHalfSlouching() {
        let stats = DailyStats(date: Date(), totalSeconds: 100, slouchSeconds: 50, slouchCount: 5)
        XCTAssertEqual(stats.postureScore, 50.0)
    }

    func testPostureScoreClampsAtZero() {
        // slouchSeconds > totalSeconds should clamp to 0, not go negative
        let stats = DailyStats(date: Date(), totalSeconds: 100, slouchSeconds: 200, slouchCount: 10)
        XCTAssertEqual(stats.postureScore, 0.0)
    }

    func testPostureScoreDoesNotExceed100() {
        let stats = DailyStats(date: Date(), totalSeconds: 1000, slouchSeconds: 0, slouchCount: 0)
        XCTAssertLessThanOrEqual(stats.postureScore, 100.0)
    }

    func testDailyStatsIdentifiable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2025, month: 6, day: 1)
        let date = calendar.date(from: components)!
        let stats = DailyStats(date: date, totalSeconds: 500, slouchSeconds: 100, slouchCount: 3)
        XCTAssertEqual(stats.id, stats.dayKey)
    }
}
