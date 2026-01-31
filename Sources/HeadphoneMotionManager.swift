import Foundation
import CoreMotion

class HeadphoneMotionManager: ObservableObject {
    private var _motionManager: Any?
    
    @Published var isAvailable: Bool = false
    @Published var isActive: Bool = false
    @Published var currentPitch: Double = 0.0
    @Published var currentRoll: Double = 0.0
    @Published var currentYaw: Double = 0.0
    
    // Callback for continuous updates
    var onUpdate: ((_ pitch: Double, _ roll: Double, _ yaw: Double) -> Void)?
    
    // Queue for completion handlers waiting for permission/data
    private var pendingCompletions: [() -> Void] = []
    
    init() {
        if #available(macOS 14.0, *) {
            let manager = CMHeadphoneMotionManager()
            self._motionManager = manager
            self.isAvailable = manager.isDeviceMotionAvailable
        } else {
            self.isAvailable = false
        }
    }
    
    func startTracking(completion: (() -> Void)? = nil) {
        guard #available(macOS 14.0, *),
              let motionManager = _motionManager as? CMHeadphoneMotionManager,
              motionManager.isDeviceMotionAvailable else {
            return
        }
        
        // If we already have data flowing, call completion immediately
        if isActive {
            completion?()
            return
        }
        
        // Otherwise, queue it
        if let completion = completion {
            pendingCompletions.append(completion)
        }
        
        // If already started (but waiting for data/permission), just wait
        if motionManager.isDeviceMotionActive {
            return
        }
        
        // Start updates
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else { return }
            
            // Extract Euler angles (in radians)
            let pitch = motion.attitude.pitch
            let roll = motion.attitude.roll
            let yaw = motion.attitude.yaw
            
            // Update published properties
            self.currentPitch = pitch
            self.currentRoll = roll
            self.currentYaw = yaw
            
            // Mark as active (Permission granted & Data received)
            if !self.isActive {
                self.isActive = true
                // Fire all pending completions
                self.pendingCompletions.forEach { $0() }
                self.pendingCompletions.removeAll()
            }
            
            // Notify callback
            self.onUpdate?(pitch, roll, yaw)
        }
    }
    
    func stopTracking() {
        if #available(macOS 14.0, *),
           let motionManager = _motionManager as? CMHeadphoneMotionManager {
            motionManager.stopDeviceMotionUpdates()
        }
        isActive = false
        pendingCompletions.removeAll()
    }
}
