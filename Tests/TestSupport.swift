import Foundation

@testable import DorsoCore

extension UserDefaults {
    /// A cleared suite, so tests never read or write the real app preferences
    static func makeTestSuite() -> UserDefaults {
        let name = "com.thelazydeveloper.dorso.tests"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Could not create the test defaults suite")
        }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

extension CameraCalibrationData {
    static func valid(cameraID: String = "camera") -> CameraCalibrationData {
        CameraCalibrationData(goodPostureY: 0.6, badPostureY: 0.4, neutralY: 0.5, postureRange: 0.2, cameraID: cameraID)
    }
}

extension AirPodsCalibrationData {
    static let valid = AirPodsCalibrationData(pitch: 0.1, roll: -0.2, yaw: 0.05)
}
