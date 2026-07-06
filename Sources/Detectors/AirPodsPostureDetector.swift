import AppKit
import CoreMotion
import IOBluetooth
import os.log

private let log = OSLog(subsystem: "com.thelazydeveloper.dorso", category: "AirPodsDetector")

// MARK: - AirPods Product ID Detection

#if !APP_STORE
/// Private IOBluetooth API to access Bluetooth product/vendor IDs
@objc private protocol IOBluetoothDeviceIdentifiers {
    @objc optional var productID: UInt32 { get }
    @objc optional var vendorID: UInt32 { get }
}

private let appleVendorID: UInt32 = 0x004C

/// Apple AirPods product IDs that have motion sensors (head tracking capable)
private let compatibleProductIDs: Set<UInt32> = [
    0x200E,  // AirPods Pro (1st gen)
    0x2014,  // AirPods Pro (2nd gen) Lightning
    0x2030,  // AirPods Pro (2nd gen) USB-C
    0x2013,  // AirPods (3rd gen) Lightning
    0x2024,  // AirPods (3rd gen) MagSafe
    0x200A,  // AirPods Max (1st gen)
    0x2028,  // AirPods Max (2nd gen / USB-C)
    0x2036,  // AirPods 4 with ANC
]

/// Apple AirPods product IDs without motion sensors
private let incompatibleProductIDs: Set<UInt32> = [
    0x2002,  // AirPods (1st gen)
    0x200F,  // AirPods (2nd gen)
    0x2033,  // AirPods 4 (standard)
]
#endif

/// Represents a paired AirPods device
struct PairedAirPods {
    let name: String
    let isCompatible: Bool

    var compatibilityText: String {
        isCompatible ? L("airpods.compatible") : L("airpods.noMotionSensors")
    }
}

/// AirPods-based posture detection using head motion tracking
class AirPodsPostureDetector: NSObject, PostureDetector {
    // MARK: - PostureDetector Protocol

    let trackingSource: TrackingSource = .airpods

    var isAvailable: Bool {
        guard #available(macOS 14.0, *) else { return false }
        let manager = CMHeadphoneMotionManager()
        return manager.isDeviceMotionAvailable
    }

    private(set) var isActive: Bool = false

    var unavailableReason: String? {
        if #unavailable(macOS 14.0) {
            return L("airpods.requiresMacOS14")
        }
        if !isAvailable {
            return L("airpods.noCompatibleConnected")
        }
        return nil
    }

    /// Check if Motion & Fitness Activity permission is authorized
    var isAuthorized: Bool {
        guard #available(macOS 14.0, *) else { return false }
        return CMHeadphoneMotionManager.authorizationStatus() == .authorized
    }

    /// Observer token for app-activation notification (used to detect permission dialog dismissal).
    private(set) var activationObserver: NSObjectProtocol?

    /// Injectable status check for testing.
    /// In production this is nil and the real CMHeadphoneMotionManager API is used.
    var authorizationStatusOverride: (() -> CMAuthorizationStatus)?

    /// When true, skips creating CMHeadphoneMotionManager and starting motion updates.
    /// Used in tests where CoreMotion isn't available.
    var skipMotionUpdates: Bool = false

    /// Injectable notification name for testing. Defaults to didBecomeActiveNotification.
    var activationNotificationName: NSNotification.Name = NSApplication.didBecomeActiveNotification

    @available(macOS 14.0, *)
    private func currentAuthorizationStatus() -> CMAuthorizationStatus {
        authorizationStatusOverride?() ?? CMHeadphoneMotionManager.authorizationStatus()
    }

    /// Request Motion & Fitness Activity permission
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard #available(macOS 14.0, *) else {
            completion(false)
            return
        }

        let status = currentAuthorizationStatus()
        os_log(.info, log: log, "requestAuthorization: current status = %{public}@",
               String(describing: status))

        switch status {
        case .authorized:
            os_log(.info, log: log, "Already authorized, proceeding")
            completion(true)
        case .denied, .restricted:
            os_log(.info, log: log, "Authorization denied/restricted")
            completion(false)
        case .notDetermined:
            os_log(.info, log: log, "Status notDetermined - starting motion updates to trigger dialog")
            var hasCompleted = false
            let complete: (Bool) -> Void = { [weak self] authorized in
                guard !hasCompleted else { return }
                hasCompleted = true
                if let observer = self?.activationObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self?.activationObserver = nil
                }
                self?.motionManager?.stopDeviceMotionUpdates()
                self?.motionManager = nil  // Force start() to create a fresh manager
                DispatchQueue.main.async {
                    completion(authorized)
                }
            }

            // Start motion updates to trigger the system permission dialog.
            // The motion data callback also checks status, but only fires when
            // AirPods are in ears — the activation observer below covers the other case.
            if !skipMotionUpdates {
                if motionManager == nil {
                    motionManager = CMHeadphoneMotionManager()
                }
                guard motionManager != nil else {
                    completion(false)
                    return
                }

                motionManager!.startDeviceMotionUpdates(to: .main) { [weak self] _, _ in
                    guard !hasCompleted else { return }
                    guard let self else { return }
                    let newStatus = self.currentAuthorizationStatus()
                    if newStatus == .authorized {
                        os_log(.info, log: log, "Permission granted via motion callback")
                        complete(true)
                    } else if newStatus == .denied || newStatus == .restricted {
                        os_log(.info, log: log, "Permission denied via motion callback")
                        complete(false)
                    }
                }
            }

            // When the system permission dialog is dismissed, the app regains focus.
            // Check authorization status at that point to catch approval even when
            // AirPods aren't in ears (motion data callback won't fire without them).
            activationObserver = NotificationCenter.default.addObserver(
                forName: activationNotificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard !hasCompleted else { return }
                guard let self else { return }
                let newStatus = self.currentAuthorizationStatus()
                os_log(.info, log: log, "App activated - checking auth status: %{public}@",
                       String(describing: newStatus))
                if newStatus == .authorized {
                    os_log(.info, log: log, "Permission granted via activation observer")
                    complete(true)
                } else if newStatus == .denied || newStatus == .restricted {
                    os_log(.info, log: log, "Permission denied via activation observer")
                    complete(false)
                }
            }
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Paired AirPods Detection

    /// Get all paired AirPods devices
    func getPairedAirPods() -> [PairedAirPods] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        var airPodsList: [PairedAirPods] = []

        for device in devices {
            guard let name = device.name else { continue }
            let lowercaseName = name.lowercased()

            // Check if it's AirPods
            guard lowercaseName.contains("airpods") else { continue }

            let isCompatible = checkCompatibility(device: device, lowercaseName: lowercaseName)
            airPodsList.append(PairedAirPods(name: name, isCompatible: isCompatible))
        }

        return airPodsList
    }

    /// Check if an AirPods device has motion sensors.
    /// Uses Bluetooth product ID when available (direct distribution),
    /// falls back to name-based detection for App Store builds.
    private func checkCompatibility(device: IOBluetoothDevice, lowercaseName: String) -> Bool {
        #if !APP_STORE
        let identifiable = unsafeBitCast(device, to: IOBluetoothDeviceIdentifiers.self)
        if let vendorID = identifiable.vendorID, let productID = identifiable.productID,
           vendorID == appleVendorID {
            os_log(.debug, log: log, "AirPods '%{public}@' productID=0x%04X", device.name ?? "", productID)
            if compatibleProductIDs.contains(productID) { return true }
            if incompatibleProductIDs.contains(productID) { return false }
            // Unknown product ID — log it so we can add support later
            os_log(.info, log: log, "Unknown AirPods productID 0x%04X for '%{public}@', falling back to name check",
                   productID, device.name ?? "")
        }
        #endif

        // Fallback: name-based detection
        return lowercaseName.contains("pro") ||
               lowercaseName.contains("max") ||
               lowercaseName.contains("3") ||
               lowercaseName.contains("4")
    }

    /// Check if any paired AirPods are currently Bluetooth-connected.
    /// Unlike `isConnected` (which requires active motion tracking), this uses
    /// IOBluetooth and works without Motion permission.
    var isBluetoothConnected: Bool {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return false
        }
        return devices.contains { device in
            guard let name = device.name?.lowercased() else { return false }
            return name.contains("airpods") && device.isConnected()
        }
    }

    var onPostureReading: ((PostureReading) -> Void)?
    var onCalibrationUpdate: ((CalibrationSample) -> Void)?

    // MARK: - Internal State

    // Store as Any? to avoid availability annotation on the class
    private var _motionManager: Any?

    @available(macOS 14.0, *)
    private var motionManager: CMHeadphoneMotionManager? {
        get { _motionManager as? CMHeadphoneMotionManager }
        set { _motionManager = newValue }
    }

    private var calibrationData: AirPodsCalibrationData?
    private var intensity: CGFloat = 1.0
    private var deadZone: CGFloat = 0.03
    private var isMonitoring = false

    // Current motion values
    private(set) var currentPitch: Double = 0.0
    private(set) var currentRoll: Double = 0.0
    private(set) var currentYaw: Double = 0.0


    // MARK: - Thresholds

    /// Base threshold in radians (~8.5 degrees)
    private let baseThreshold: Double = 0.15

    /// Maximum additional threshold from dead zone setting (~28 degrees)
    private let maxDeadZoneThreshold: Double = 0.5

    /// Maximum excess past threshold for full severity (~17 degrees)
    private let maxExcessForFullSeverity: Double = 0.3

    // MARK: - Connection State (Protocol)

    /// Whether AirPods are actually in ears and sending motion data
    var isConnected: Bool {
        isReceivingMotionData
    }

    /// Callback when connection state changes (AirPods put in or removed from ears)
    var onConnectionStateChange: ((Bool) -> Void)? {
        get { onMotionDataAvailabilityChange }
        set { onMotionDataAvailabilityChange = newValue }
    }

    // MARK: - Internal Connection State

    /// Internal state tracking - use isConnected for external access
    private(set) var isReceivingMotionData: Bool = false

    /// Internal callback - use onConnectionStateChange for external access
    var onMotionDataAvailabilityChange: ((Bool) -> Void)?

    func start(completion: @escaping (Bool, String?) -> Void) {
        guard #available(macOS 14.0, *) else {
            os_log(.error, log: log, "macOS 14.0+ required for AirPods tracking")
            completion(false, L("airpods.requiresMacOS14"))
            return
        }

        if motionManager == nil {
            motionManager = CMHeadphoneMotionManager()
        }

        guard let manager = motionManager else {
            completion(false, L("airpods.failedCreateManager"))
            return
        }

        guard manager.isDeviceMotionAvailable else {
            completion(false, L("airpods.noCompatiblePaired"))
            return
        }

        // Treat already-running managers as active (idempotent start)
        if isActive || manager.isDeviceMotionActive {
            isActive = true
            manager.delegate = self
            manager.startConnectionStatusUpdates()
            completion(true, nil)
            return
        }

        os_log(.info, log: log, "Starting AirPods motion tracking")

        // Mark active before starting updates so early callbacks aren't dropped
        isActive = true

        // Set delegate for connection status callbacks
        manager.delegate = self
        manager.startConnectionStatusUpdates()
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, self.isActive else { return }

            if let error = error {
                os_log(.error, log: log, "Motion update error: %{public}@", error.localizedDescription)
                return
            }

            guard let motion = motion else { return }

            // If we're receiving motion data, AirPods are in ears
            // This is a fallback in case the delegate doesn't fire
            if !self.isReceivingMotionData {
                os_log(.info, log: log, "Received motion data - AirPods connected (fallback)")
                self.isReceivingMotionData = true
                self.onMotionDataAvailabilityChange?(true)
            }

            // Extract Euler angles (in radians)
            self.currentPitch = motion.attitude.pitch
            self.currentRoll = motion.attitude.roll
            self.currentYaw = motion.attitude.yaw

            // Send calibration update if handler is set
            self.onCalibrationUpdate?(.airPods(AirPodsCalibrationSample(
                pitch: self.currentPitch,
                roll: self.currentRoll,
                yaw: self.currentYaw
            )))

            // Evaluate posture if monitoring
            if self.isMonitoring, let calibration = self.calibrationData {
                self.evaluatePosture(calibration: calibration)
            }
        }

        // Complete immediately - calibration screen will wait for connection
        completion(true, nil)
    }

    func stop() {
        os_log(.info, log: log, "Stopping AirPods motion tracking")
        if let observer = activationObserver {
            NotificationCenter.default.removeObserver(observer)
            activationObserver = nil
        }
        if #available(macOS 14.0, *) {
            motionManager?.stopDeviceMotionUpdates()
            motionManager?.stopConnectionStatusUpdates()
            motionManager?.delegate = nil
        }
        isActive = false
        isReceivingMotionData = false
        isMonitoring = false
    }

    // MARK: - Connection Monitoring (for automatic mode fallback)

    /// Start monitoring AirPods connection state without full motion tracking.
    /// Used in automatic mode to detect when AirPods are put back in.
    func startConnectionMonitoring() {
        guard #available(macOS 14.0, *) else { return }

        if motionManager == nil {
            motionManager = CMHeadphoneMotionManager()
        }
        guard let manager = motionManager else { return }
        manager.delegate = self
        manager.startConnectionStatusUpdates()
        os_log(.info, log: log, "Started AirPods connection monitoring (no motion)")
    }

    /// Stop connection-only monitoring.
    func stopConnectionMonitoring() {
        guard #available(macOS 14.0, *) else { return }
        guard !isActive else { return } // Don't stop if full detector is running
        motionManager?.stopConnectionStatusUpdates()
        motionManager?.delegate = nil
        os_log(.info, log: log, "Stopped AirPods connection monitoring")
    }

    // MARK: - Calibration

    func getCurrentCalibrationValue() -> CalibrationSample {
        .airPods(AirPodsCalibrationSample(pitch: currentPitch, roll: currentRoll, yaw: currentYaw))
    }

    func createCalibrationData(from samples: [CalibrationSample]) -> CalibrationData? {
        let motionPoints: [AirPodsCalibrationSample] = samples.compactMap { sample in
            guard case .airPods(let motionSample) = sample else { return nil }
            return motionSample
        }
        guard !motionPoints.isEmpty else { return nil }

        // Average all captured points
        let avgPitch = motionPoints.map(\.pitch).reduce(0, +) / Double(motionPoints.count)
        let avgRoll = motionPoints.map(\.roll).reduce(0, +) / Double(motionPoints.count)
        let avgYaw = motionPoints.map(\.yaw).reduce(0, +) / Double(motionPoints.count)

        os_log(.info, log: log, "Created calibration: pitch=%.3f, roll=%.3f, yaw=%.3f", avgPitch, avgRoll, avgYaw)

        return AirPodsCalibrationData(pitch: avgPitch, roll: avgRoll, yaw: avgYaw)
    }

    // MARK: - Monitoring

    func beginMonitoring(with calibration: CalibrationData, intensity: CGFloat, deadZone: CGFloat) {
        guard let airPodsCalibration = calibration as? AirPodsCalibrationData else {
            os_log(.error, log: log, "Invalid calibration data type")
            return
        }

        self.calibrationData = airPodsCalibration
        self.intensity = intensity
        self.deadZone = deadZone
        self.isMonitoring = true

        os_log(.info, log: log, "Started monitoring with intensity=%.2f, deadZone=%.2f", intensity, deadZone)
    }

    func updateParameters(intensity: CGFloat, deadZone: CGFloat) {
        self.intensity = intensity
        self.deadZone = deadZone
    }

    // MARK: - Posture Evaluation

    private func evaluatePosture(calibration: AirPodsCalibrationData) {
        // Calculate signed difference (Current - Neutral)
        // Looking down decreases pitch (negative direction)
        let diff = currentPitch - calibration.pitch

        // Threshold: base + scaled dead zone
        let threshold = baseThreshold + (Double(deadZone) * maxDeadZoneThreshold)

        // Only detect forward lean (negative diff exceeding threshold)
        // Leaning back (positive diff) is ignored (e.g., stretching)
        let isBadPosture = diff < -threshold

        // Calculate severity
        var severity: Double = 0
        if isBadPosture {
            // How much past the threshold?
            let excess = abs(diff) - threshold
            severity = min(1.0, excess / maxExcessForFullSeverity)
        }

        let reading = PostureReading(
            timestamp: Date(),
            isBadPosture: isBadPosture,
            severity: severity
        )

        onPostureReading?(reading)
    }
}

// MARK: - CMHeadphoneMotionManagerDelegate

@available(macOS 14.0, *)
extension AirPodsPostureDetector: CMHeadphoneMotionManagerDelegate {
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        os_log(.info, log: log, "AirPods connected (in ears)")
        isReceivingMotionData = true
        let callback = onMotionDataAvailabilityChange
        DispatchQueue.main.async {
            callback?(true)
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        os_log(.info, log: log, "AirPods disconnected (removed from ears)")
        isReceivingMotionData = false
        let callback = onMotionDataAvailabilityChange
        DispatchQueue.main.async {
            callback?(false)
        }
    }
}
