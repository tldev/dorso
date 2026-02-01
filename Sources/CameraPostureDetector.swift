import Foundation
import AVFoundation
import Vision
import os.log

private let log = OSLog(subsystem: "com.posturr", category: "CameraDetector")

/// Camera-based posture detection using Vision framework
class CameraPostureDetector: NSObject, PostureDetector {
    // MARK: - PostureDetector Protocol

    let trackingSource: TrackingSource = .camera

    var isAvailable: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .authorized || status == .notDetermined
    }

    private(set) var isActive: Bool = false

    /// Camera is always "connected" - no separate connection state like AirPods
    /// (Camera doesn't have an equivalent to "put in your ears")
    var isConnected: Bool { true }

    /// Connection state changes (not used for camera - always connected when active)
    var onConnectionStateChange: ((Bool) -> Void)?

    /// Camera permission is handled separately via AVCaptureDevice
    var isAuthorized: Bool { true }

    /// Camera authorization is handled in start() - this is a no-op
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    var unavailableReason: String? {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .denied:
            return "Camera access denied. Enable in System Settings > Privacy & Security > Camera."
        case .restricted:
            return "Camera access is restricted on this device."
        default:
            if getAvailableCameras().isEmpty {
                return "No camera found."
            }
            return nil
        }
    }

    var onPostureReading: ((PostureReading) -> Void)?
    var onCalibrationUpdate: ((Any) -> Void)?

    // MARK: - Camera State

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let captureQueue = DispatchQueue(label: "posturr.camera.capture")

    var selectedCameraID: String?
    private var isMonitoring = false

    // MARK: - Calibration State

    private var calibrationData: CameraCalibrationData?
    private var intensity: CGFloat = 1.0
    private var deadZone: CGFloat = 0.03

    // MARK: - Detection State

    private var currentNoseY: CGFloat = 0.5
    private var currentFaceWidth: CGFloat = 0.0
    private var noseYHistory: [CGFloat] = []
    private let smoothingWindow = 5
    private var isCurrentlySlouching = false

    // Frame throttling
    private var lastFrameTime: Date = .distantPast
    var baseFrameInterval: TimeInterval = 0.25  // Configured frame interval (e.g., from detection mode)

    /// Actual frame interval - faster when slouching for quicker recovery detection
    private var frameInterval: TimeInterval {
        isCurrentlySlouching ? 0.1 : baseFrameInterval
    }

    // MARK: - Away Detection

    var blurWhenAway: Bool = false
    private var consecutiveNoDetectionFrames = 0
    private let awayFrameThreshold = 15
    var onAwayStateChange: ((Bool) -> Void)?

    // MARK: - Lifecycle

    func start(completion: @escaping (Bool, String?) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            setupCamera()
            startSession()
            completion(true, nil)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                        self?.startSession()
                        completion(true, nil)
                    } else {
                        completion(false, "Camera access denied")
                    }
                }
            }

        case .denied:
            completion(false, "Camera access denied. Enable in System Settings > Privacy & Security > Camera.")

        case .restricted:
            completion(false, "Camera access is restricted on this device.")

        @unknown default:
            completion(false, "Unknown camera authorization status")
        }
    }

    func stop() {
        os_log(.info, log: log, "Stopping camera capture")
        captureSession?.stopRunning()
        isActive = false
        isMonitoring = false
    }

    // MARK: - Calibration

    func getCurrentCalibrationValue() -> Any {
        if currentFaceWidth > 0 {
            return CalibrationPoint(noseY: currentNoseY, faceWidth: currentFaceWidth)
        }
        return currentNoseY
    }

    func createCalibrationData(from points: [Any]) -> CalibrationData? {
        var yValues: [CGFloat] = []
        var widthValues: [CGFloat] = []

        for point in points {
            if let calibrationPoint = point as? CalibrationPoint {
                yValues.append(calibrationPoint.noseY)
                widthValues.append(calibrationPoint.faceWidth)
            } else if let y = point as? CGFloat {
                yValues.append(y)
            }
        }

        guard yValues.count >= 4 else { return nil }

        let maxY = yValues.max() ?? 0.6
        let minY = yValues.min() ?? 0.4
        let avgY = yValues.reduce(0, +) / CGFloat(yValues.count)
        let range = abs(maxY - minY)
        let neutralWidth = widthValues.isEmpty ? 0.0 : widthValues.reduce(0, +) / CGFloat(widthValues.count)

        os_log(.info, log: log, "Created calibration: goodY=%.3f, badY=%.3f, range=%.3f, neutralWidth=%.3f", maxY, minY, range, neutralWidth)

        return CameraCalibrationData(
            goodPostureY: maxY,
            badPostureY: minY,
            neutralY: avgY,
            postureRange: range,
            cameraID: selectedCameraID ?? "",
            neutralFaceWidth: neutralWidth
        )
    }

    // MARK: - Monitoring

    func beginMonitoring(with calibration: CalibrationData, intensity: CGFloat, deadZone: CGFloat) {
        guard let cameraCalibration = calibration as? CameraCalibrationData else {
            os_log(.error, log: log, "Invalid calibration data type")
            return
        }

        self.calibrationData = cameraCalibration
        self.intensity = intensity
        self.deadZone = deadZone
        self.isMonitoring = true
        self.isCurrentlySlouching = false
        self.noseYHistory.removeAll()

        os_log(.info, log: log, "Started monitoring with intensity=%.2f, deadZone=%.2f", intensity, deadZone)
    }

    func updateParameters(intensity: CGFloat, deadZone: CGFloat) {
        self.intensity = intensity
        self.deadZone = deadZone
    }

    // MARK: - Camera Management

    func getAvailableCameras() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        return discoverySession.devices
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .cif352x288  // Low resolution for CPU efficiency

        let cameras = getAvailableCameras()
        let camera: AVCaptureDevice?

        if let selectedID = selectedCameraID {
            camera = cameras.first { $0.uniqueID == selectedID }
        } else {
            camera = cameras.first { $0.position == .front } ?? cameras.first
        }

        guard let selectedCamera = camera,
              let input = try? AVCaptureDeviceInput(device: selectedCamera) else {
            os_log(.error, log: log, "Failed to create camera input")
            return
        }

        selectedCameraID = selectedCamera.uniqueID
        captureSession?.addInput(input)

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        videoOutput?.setSampleBufferDelegate(self, queue: captureQueue)

        if let videoOutput = videoOutput {
            captureSession?.addOutput(videoOutput)
        }

        os_log(.info, log: log, "Camera setup complete: %{public}@", selectedCamera.localizedName)
    }

    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.isActive = true
                os_log(.info, log: log, "Camera session started")
            }
        }
    }

    func switchCamera(to cameraID: String) {
        let wasRunning = captureSession?.isRunning ?? false

        if wasRunning {
            captureSession?.stopRunning()
        }

        // Remove existing inputs
        if let inputs = captureSession?.inputs {
            for input in inputs {
                captureSession?.removeInput(input)
            }
        }

        let cameras = getAvailableCameras()
        guard let camera = cameras.first(where: { $0.uniqueID == cameraID }),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            os_log(.error, log: log, "Failed to switch to camera: %{public}@", cameraID)
            return
        }

        selectedCameraID = cameraID
        captureSession?.addInput(input)

        if wasRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.startRunning()
            }
        }

        os_log(.info, log: log, "Switched to camera: %{public}@", camera.localizedName)
    }

    // MARK: - Frame Processing

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        let bodyRequest = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            if let results = request.results as? [VNHumanBodyPoseObservation], let body = results.first {
                self?.analyzeBodyPose(body)
            } else {
                self?.tryFaceDetection(pixelBuffer: pixelBuffer)
            }
        }

        do {
            try handler.perform([bodyRequest])
        } catch {
            tryFaceDetection(pixelBuffer: pixelBuffer)
        }
    }

    private func analyzeBodyPose(_ body: VNHumanBodyPoseObservation) {
        guard let nose = try? body.recognizedPoint(.nose), nose.confidence > 0.3 else {
            return
        }

        consecutiveNoDetectionFrames = 0
        handleDetection(noseY: nose.location.y)
    }

    private func tryFaceDetection(pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        let faceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            if let results = request.results as? [VNFaceObservation], let face = results.first {
                self?.consecutiveNoDetectionFrames = 0
                self?.handleDetection(noseY: face.boundingBox.midY, faceWidth: face.boundingBox.width)
            } else {
                self?.handleNoDetection()
            }
        }

        try? handler.perform([faceRequest])
    }

    private func handleDetection(noseY: CGFloat, faceWidth: CGFloat? = nil) {
        currentNoseY = noseY
        if let width = faceWidth {
            currentFaceWidth = width
        }

        // Send calibration update
        if let width = faceWidth {
            onCalibrationUpdate?(CalibrationPoint(noseY: noseY, faceWidth: width))
        } else {
            onCalibrationUpdate?(noseY)
        }

        // Reset away state
        if blurWhenAway {
            onAwayStateChange?(false)
        }

        // Evaluate posture if monitoring
        if isMonitoring, let calibration = calibrationData {
            evaluatePosture(currentY: noseY, currentFaceWidth: faceWidth ?? 0, calibration: calibration)
        }
    }

    private func handleNoDetection() {
        guard blurWhenAway else { return }

        consecutiveNoDetectionFrames += 1

        if consecutiveNoDetectionFrames >= awayFrameThreshold {
            onAwayStateChange?(true)
        }
    }

    // MARK: - Posture Evaluation

    private func smoothNoseY(_ rawY: CGFloat) -> CGFloat {
        noseYHistory.append(rawY)
        if noseYHistory.count > smoothingWindow {
            noseYHistory.removeFirst()
        }
        return noseYHistory.reduce(0, +) / CGFloat(noseYHistory.count)
    }

    private func evaluatePosture(currentY: CGFloat, currentFaceWidth: CGFloat, calibration: CameraCalibrationData) {
        let smoothedY = smoothNoseY(currentY)

        // Vertical position detection (slouching down)
        let slouchAmount = calibration.badPostureY - smoothedY
        let deadZoneThreshold = deadZone * calibration.postureRange

        let enterThreshold = deadZoneThreshold
        let exitThreshold = deadZoneThreshold * 0.7
        let threshold = isCurrentlySlouching ? exitThreshold : enterThreshold

        var isBadPosture = slouchAmount > threshold

        // Forward-head detection (moving closer to screen)
        let forwardHeadThreshold = 1.0 + max(CameraCalibrationData.forwardHeadBaseThreshold, deadZone)
        var forwardHeadSeverity: Double = 0.0

        if calibration.neutralFaceWidth > 0 && currentFaceWidth > 0 {
            let ratio = currentFaceWidth / calibration.neutralFaceWidth
            if ratio > forwardHeadThreshold {
                isBadPosture = true
                let sizeExcess = ratio - forwardHeadThreshold
                forwardHeadSeverity = min(1.0, max(0.0, Double(sizeExcess / CameraCalibrationData.forwardHeadSeverityRange)))
            }
        }

        // Calculate combined severity
        var severity: Double = 0.0

        if isBadPosture {
            // Vertical severity
            let pastDeadZone = slouchAmount - deadZoneThreshold
            let remainingRange = max(0.01, calibration.postureRange - deadZoneThreshold)
            let verticalSeverity = min(1.0, max(0.0, pastDeadZone / remainingRange))

            severity = max(Double(verticalSeverity), forwardHeadSeverity)

            // Ensure minimum severity when forward-head posture is detected
            if forwardHeadSeverity > 0 && severity < CameraCalibrationData.forwardHeadMinSeverity {
                severity = CameraCalibrationData.forwardHeadMinSeverity
            }
        }

        // Update hysteresis state
        if isBadPosture {
            isCurrentlySlouching = true
        } else if !isBadPosture && severity == 0 {
            isCurrentlySlouching = false
        }

        let reading = PostureReading(
            timestamp: Date(),
            isBadPosture: isBadPosture,
            severity: severity
        )

        DispatchQueue.main.async {
            self.onPostureReading?(reading)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraPostureDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= frameInterval else { return }
        lastFrameTime = now

        processFrame(pixelBuffer)
    }
}
