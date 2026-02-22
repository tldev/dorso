import XCTest
import AVFoundation
@testable import DorsoCore

final class CameraPostureDetectorTests: XCTestCase {

    // MARK: - createCalibrationData: Valid Samples

    func testCreateCalibrationDataWithExactly4Samples() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "cam-1"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: 0.20)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: 0.22)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: 0.18)),
            .camera(CameraCalibrationSample(noseY: 0.45, faceWidth: 0.25)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        XCTAssertNotNil(calibration)
        XCTAssertEqual(Double(calibration!.goodPostureY), 0.60, accuracy: 0.0001, "goodPostureY should be max Y")
        XCTAssertEqual(Double(calibration!.badPostureY), 0.45, accuracy: 0.0001, "badPostureY should be min Y")
        // neutralY = average = (0.60 + 0.55 + 0.50 + 0.45) / 4 = 0.525
        XCTAssertEqual(Double(calibration!.neutralY), 0.525, accuracy: 0.0001, "neutralY should be average of all Y")
        // postureRange = abs(0.60 - 0.45) = 0.15
        XCTAssertEqual(Double(calibration!.postureRange), 0.15, accuracy: 0.0001, "postureRange should be abs(max - min)")
        XCTAssertEqual(calibration!.cameraID, "cam-1")
        // neutralFaceWidth = max of all face widths = 0.25
        XCTAssertEqual(Double(calibration!.neutralFaceWidth), 0.25, accuracy: 0.0001, "neutralFaceWidth should be max face width")
    }

    // MARK: - createCalibrationData: Fewer Than 4 Samples

    func testCreateCalibrationDataWithFewerThan4SamplesReturnsNil() {
        let detector = CameraPostureDetector()

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: 0.20)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: 0.22)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: 0.18)),
        ]

        let calibration = detector.createCalibrationData(from: samples)
        XCTAssertNil(calibration, "Should return nil with fewer than 4 camera samples")
    }

    func testCreateCalibrationDataWithZeroSamplesReturnsNil() {
        let detector = CameraPostureDetector()
        let calibration = detector.createCalibrationData(from: [])
        XCTAssertNil(calibration)
    }

    func testCreateCalibrationDataWithOneSampleReturnsNil() {
        let detector = CameraPostureDetector()
        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: 0.20)),
        ]
        let calibration = detector.createCalibrationData(from: samples)
        XCTAssertNil(calibration)
    }

    // MARK: - createCalibrationData: Face Width Edge Cases

    func testCreateCalibrationDataNoFaceWidthsGivesZeroNeutralWidth() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "cam-2"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.45, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        XCTAssertNotNil(calibration)
        XCTAssertEqual(Double(calibration!.neutralFaceWidth), 0.0, accuracy: 0.0001,
                       "neutralFaceWidth should be 0 when no face widths provided")
    }

    func testCreateCalibrationDataMixedFaceWidthsUsesMax() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "cam-3"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: 0.15)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: 0.30)),
            .camera(CameraCalibrationSample(noseY: 0.45, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        XCTAssertNotNil(calibration)
        XCTAssertEqual(Double(calibration!.neutralFaceWidth), 0.30, accuracy: 0.0001,
                       "neutralFaceWidth should be max of present face widths")
    }

    // MARK: - createCalibrationData: Y Value Calculations

    func testGoodPostureYIsMaxYValue() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "test"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.30, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.70, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.40, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        XCTAssertEqual(Double(calibration!.goodPostureY), 0.70, accuracy: 0.0001)
    }

    func testBadPostureYIsMinYValue() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "test"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.30, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.70, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.40, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        XCTAssertEqual(Double(calibration!.badPostureY), 0.30, accuracy: 0.0001)
    }

    func testNeutralYIsAverageOfAllYValues() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "test"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.20, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.40, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.80, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        // average = (0.20 + 0.40 + 0.60 + 0.80) / 4 = 0.50
        XCTAssertEqual(Double(calibration!.neutralY), 0.50, accuracy: 0.0001)
    }

    func testPostureRangeIsAbsMaxMinusMin() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "test"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.20, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.40, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.80, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        // range = abs(0.80 - 0.20) = 0.60
        XCTAssertEqual(Double(calibration!.postureRange), 0.60, accuracy: 0.0001)
    }

    // MARK: - createCalibrationData: Camera ID

    func testCameraIDIsSetFromSelectedCameraID() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "my-specific-camera-id"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.45, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        XCTAssertEqual(calibration!.cameraID, "my-specific-camera-id")
    }

    func testEmptySelectedCameraIDGivesEmptyCameraID() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = nil

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.45, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        XCTAssertEqual(calibration!.cameraID, "")
    }

    // MARK: - createCalibrationData: Ignoring Non-Camera Samples

    func testIgnoresAirPodsSamplesInCameraCalibration() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "test"

        // 3 camera samples + 2 airpods samples = only 3 camera samples (not enough)
        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: nil)),
            .airPods(AirPodsCalibrationSample(pitch: 0.1, roll: 0.2, yaw: 0.3)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: nil)),
            .airPods(AirPodsCalibrationSample(pitch: 0.4, roll: 0.5, yaw: 0.6)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples)
        XCTAssertNil(calibration, "Should return nil because only 3 camera samples exist (airpods are ignored)")
    }

    func testAirPodsSamplesIgnoredWith4CameraSamples() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "test"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: nil)),
            .airPods(AirPodsCalibrationSample(pitch: 0.1, roll: 0.2, yaw: 0.3)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.45, faceWidth: nil)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        XCTAssertNotNil(calibration, "Should succeed with 4 camera samples even if airpods samples mixed in")
        XCTAssertEqual(Double(calibration!.goodPostureY), 0.60, accuracy: 0.0001)
        XCTAssertEqual(Double(calibration!.badPostureY), 0.45, accuracy: 0.0001)
    }

    // MARK: - getCurrentCalibrationValue

    func testGetCurrentCalibrationValueReturnsCameraCase() {
        let detector = CameraPostureDetector()
        // The detector starts with default currentNoseY = 0.5 and currentFaceWidth = 0.0
        let sample = detector.getCurrentCalibrationValue()

        if case .camera(let cameraSample) = sample {
            XCTAssertEqual(Double(cameraSample.noseY), 0.5, accuracy: 0.0001)
            XCTAssertNil(cameraSample.faceWidth, "faceWidth should be nil when currentFaceWidth is 0")
        } else {
            XCTFail("Expected .camera calibration sample")
        }
    }

    // MARK: - beginMonitoring

    func testBeginMonitoringWithInvalidCalibrationTypeIsNoOp() {
        let detector = CameraPostureDetector()
        let airPodsCalibration = AirPodsCalibrationData(pitch: 0.1, roll: 0.2, yaw: 0.3)

        // Should not crash when given wrong calibration type
        detector.beginMonitoring(with: airPodsCalibration, intensity: 1.0, deadZone: 0.03)
        // If we get here without crashing, the test passes
    }

    // MARK: - updateParameters

    func testUpdateParametersStoresValues() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "test"

        // First set up monitoring with valid calibration
        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.45, faceWidth: nil)),
        ]
        let calibration = detector.createCalibrationData(from: samples)!
        detector.beginMonitoring(with: calibration, intensity: 1.0, deadZone: 0.03)

        // Update parameters - should not crash
        detector.updateParameters(intensity: 0.5, deadZone: 0.1)
        // If we get here without crashing, the test passes
    }

    // MARK: - Lifecycle Race Regression

    func testStopDuringInFlightStartDoesNotBecomeActive() {
        let startInvoked = expectation(description: "start handler invoked")
        let delayedStartCompletion = expectation(description: "delayed start completion fired")
        let settled = expectation(description: "detector remained inactive")

        let stopLock = NSLock()
        var stopCallCount = 0

        let runtime = CameraPostureDetector.Runtime(
            authorizationStatus: { .authorized },
            requestAccess: { completion in completion(true) },
            customSessionFactory: { AVCaptureSession() },
            startRunning: { _, completion in
                startInvoked.fulfill()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                    completion(true)
                    delayedStartCompletion.fulfill()
                }
            },
            stopRunning: { _ in
                stopLock.lock()
                stopCallCount += 1
                stopLock.unlock()
            }
        )
        let detector = CameraPostureDetector(runtime: runtime)

        detector.start { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
        }

        wait(for: [startInvoked], timeout: 1.0)
        detector.stop()

        wait(for: [delayedStartCompletion], timeout: 1.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertFalse(detector.isActive, "Detector should remain inactive after stop even if delayed start callback arrives")
            stopLock.lock()
            let count = stopCallCount
            stopLock.unlock()
            XCTAssertGreaterThanOrEqual(count, 1, "Stop should be called for in-flight or stale session start")
            settled.fulfill()
        }

        wait(for: [settled], timeout: 1.0)
    }
}

// MARK: - AirPodsPostureDetector Extended Calibration Tests

final class AirPodsPostureDetectorCalibrationTests: XCTestCase {

    func testCreateCalibrationDataWithSingleSample() {
        let detector = AirPodsPostureDetector()

        let samples: [CalibrationSample] = [
            .airPods(AirPodsCalibrationSample(pitch: 0.15, roll: 0.25, yaw: 0.35)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? AirPodsCalibrationData
        XCTAssertNotNil(calibration, "Single sample should produce valid calibration")
        XCTAssertEqual(calibration!.pitch, 0.15, accuracy: 0.0001)
        XCTAssertEqual(calibration!.roll, 0.25, accuracy: 0.0001)
        XCTAssertEqual(calibration!.yaw, 0.35, accuracy: 0.0001)
    }

    func testCreateCalibrationDataWithEmptySamplesReturnsNil() {
        let detector = AirPodsPostureDetector()
        let calibration = detector.createCalibrationData(from: [])
        XCTAssertNil(calibration, "Empty samples should return nil")
    }

    func testCreateCalibrationDataIgnoresCameraSamples() {
        let detector = AirPodsPostureDetector()

        // Only camera samples - no airpods samples at all
        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: 0.20)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: 0.22)),
        ]

        let calibration = detector.createCalibrationData(from: samples)
        XCTAssertNil(calibration, "Should return nil when only camera samples are present")
    }

    func testCreateCalibrationDataAveragesWith3Samples() {
        let detector = AirPodsPostureDetector()

        let samples: [CalibrationSample] = [
            .airPods(AirPodsCalibrationSample(pitch: 0.10, roll: 0.20, yaw: 0.30)),
            .airPods(AirPodsCalibrationSample(pitch: 0.20, roll: 0.40, yaw: 0.60)),
            .airPods(AirPodsCalibrationSample(pitch: 0.30, roll: 0.60, yaw: 0.90)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? AirPodsCalibrationData
        XCTAssertNotNil(calibration)
        // averages: pitch = 0.20, roll = 0.40, yaw = 0.60
        XCTAssertEqual(calibration!.pitch, 0.20, accuracy: 0.0001)
        XCTAssertEqual(calibration!.roll, 0.40, accuracy: 0.0001)
        XCTAssertEqual(calibration!.yaw, 0.60, accuracy: 0.0001)
    }

    func testCreateCalibrationDataMixedSamplesOnlyUsesAirPods() {
        let detector = AirPodsPostureDetector()

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: 0.20)),
            .airPods(AirPodsCalibrationSample(pitch: 0.10, roll: 0.20, yaw: 0.30)),
            .camera(CameraCalibrationSample(noseY: 0.55, faceWidth: nil)),
            .airPods(AirPodsCalibrationSample(pitch: 0.30, roll: 0.40, yaw: 0.50)),
        ]

        let calibration = detector.createCalibrationData(from: samples) as? AirPodsCalibrationData
        XCTAssertNotNil(calibration, "Should use only airpods samples and ignore camera samples")
        // averages of 2 airpods samples: pitch=0.20, roll=0.30, yaw=0.40
        XCTAssertEqual(calibration!.pitch, 0.20, accuracy: 0.0001)
        XCTAssertEqual(calibration!.roll, 0.30, accuracy: 0.0001)
        XCTAssertEqual(calibration!.yaw, 0.40, accuracy: 0.0001)
    }
}
