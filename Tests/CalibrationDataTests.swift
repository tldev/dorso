import XCTest
@testable import PosturrCore

final class CalibrationDataTests: XCTestCase {

    func testCameraCalibrationDataCreationUsesMaxFaceWidthAsNeutral() {
        let detector = CameraPostureDetector()
        detector.selectedCameraID = "test-camera"

        let samples: [CalibrationSample] = [
            .camera(CameraCalibrationSample(noseY: 0.60, faceWidth: 0.20)),
            .camera(CameraCalibrationSample(noseY: 0.50, faceWidth: nil)),
            .camera(CameraCalibrationSample(noseY: 0.40, faceWidth: 0.25)),
            .camera(CameraCalibrationSample(noseY: 0.30, faceWidth: nil))
        ]

        let calibration = detector.createCalibrationData(from: samples) as? CameraCalibrationData
        XCTAssertNotNil(calibration)
        XCTAssertEqual(calibration?.cameraID, "test-camera")
        XCTAssertEqual(Double(calibration?.goodPostureY ?? 0), 0.60, accuracy: 0.0001)
        XCTAssertEqual(Double(calibration?.badPostureY ?? 0), 0.30, accuracy: 0.0001)
        XCTAssertEqual(Double(calibration?.neutralY ?? 0), 0.45, accuracy: 0.0001)
        XCTAssertEqual(Double(calibration?.postureRange ?? 0), 0.30, accuracy: 0.0001)
        XCTAssertEqual(Double(calibration?.neutralFaceWidth ?? 0), 0.25, accuracy: 0.0001)
    }

    func testAirPodsCalibrationDataCreationAveragesSamples() {
        let detector = AirPodsPostureDetector()

        let samples: [CalibrationSample] = [
            .airPods(AirPodsCalibrationSample(pitch: 0.10, roll: 0.20, yaw: 0.30)),
            .airPods(AirPodsCalibrationSample(pitch: 0.30, roll: 0.40, yaw: 0.50))
        ]

        let calibration = detector.createCalibrationData(from: samples) as? AirPodsCalibrationData
        XCTAssertNotNil(calibration)
        XCTAssertEqual(calibration?.pitch ?? 0, 0.20, accuracy: 0.0001)
        XCTAssertEqual(calibration?.roll ?? 0, 0.30, accuracy: 0.0001)
        XCTAssertEqual(calibration?.yaw ?? 0, 0.40, accuracy: 0.0001)
    }
}

