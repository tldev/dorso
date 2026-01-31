import Foundation
import AppKit

// MARK: - Posture Reading

/// Represents a single posture measurement from any detection source
struct PostureReading {
    let timestamp: Date
    let isBadPosture: Bool
    let severity: Double  // 0.0 (good) to 1.0 (very bad)

    static let good = PostureReading(timestamp: Date(), isBadPosture: false, severity: 0)
}

// MARK: - Calibration Data

/// Protocol for detector-specific calibration data
protocol CalibrationData: Codable {
    var isValid: Bool { get }
}

/// Camera-based calibration profile
struct CameraCalibrationData: CalibrationData {
    let goodPostureY: CGFloat
    let badPostureY: CGFloat
    let neutralY: CGFloat
    let postureRange: CGFloat
    let cameraID: String

    var isValid: Bool {
        postureRange > 0.01 && !cameraID.isEmpty
    }
}

/// AirPods motion calibration profile
struct AirPodsCalibrationData: CalibrationData {
    let pitch: Double
    let roll: Double
    let yaw: Double

    var isValid: Bool { true }
}

// MARK: - Tracking Source

enum TrackingSource: String, Codable, CaseIterable, Identifiable {
    case camera = "camera"
    case airpods = "airpods"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .airpods: return "AirPods"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera"
        case .airpods: return "airpodspro"
        }
    }

    var description: String {
        switch self {
        case .camera:
            return "Uses your camera to track head position. Works with any Mac camera."
        case .airpods:
            return "Uses motion sensors to detect head tilt. Requires AirPods Pro, Max, or 3rd gen."
        }
    }

    var requirementDescription: String {
        switch self {
        case .camera:
            return "Requires camera access"
        case .airpods:
            return "Requires macOS 14+ and compatible AirPods"
        }
    }
}

// MARK: - Posture Detector Protocol

/// Protocol that all posture detection methods must implement
protocol PostureDetector: AnyObject {
    /// The type of tracking this detector provides
    var trackingSource: TrackingSource { get }

    /// Whether this detection method is available on this system
    var isAvailable: Bool { get }

    /// Whether the detector is currently active
    var isActive: Bool { get }

    /// Whether the detector is currently connected and receiving data
    /// For camera: always true when active. For AirPods: true when in ears.
    var isConnected: Bool { get }

    /// Human-readable reason if not available
    var unavailableReason: String? { get }

    /// Whether motion permission is authorized (always true for camera)
    var isAuthorized: Bool { get }

    /// Request motion permission if needed, calls completion when authorized or denied
    func requestAuthorization(completion: @escaping (Bool) -> Void)

    /// Called when posture is evaluated (only during monitoring)
    var onPostureReading: ((PostureReading) -> Void)? { get set }

    /// Called during calibration with raw position data
    var onCalibrationUpdate: ((Any) -> Void)? { get set }

    /// Called when connection state changes (e.g., AirPods removed from ears)
    /// Not all detectors use this - camera is always "connected" when active
    var onConnectionStateChange: ((Bool) -> Void)? { get set }

    // MARK: - Lifecycle

    /// Start the detector (request permissions, initialize hardware)
    func start(completion: @escaping (Bool, String?) -> Void)

    /// Stop the detector and release resources
    func stop()

    // MARK: - Calibration

    /// Get current calibration value (detector-specific type)
    func getCurrentCalibrationValue() -> Any

    /// Create calibration data from captured points
    func createCalibrationData(from points: [Any]) -> CalibrationData?

    // MARK: - Monitoring

    /// Begin monitoring with the given calibration data
    func beginMonitoring(with calibration: CalibrationData, intensity: CGFloat, deadZone: CGFloat)

    /// Update monitoring parameters
    func updateParameters(intensity: CGFloat, deadZone: CGFloat)
}

// MARK: - Settings Keys Extension

extension SettingsKeys {
    static let cameraCalibration = "cameraCalibration"
    static let airPodsCalibration = "airPodsCalibration"
}
