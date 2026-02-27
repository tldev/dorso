import Foundation

// MARK: - Pause Reason

enum PauseReason: Equatable {
    case sourceUnavailable
    case noProfile
    case onTheGo
    case cameraDisconnected
    case screenLocked
    case airPodsRemoved
}

// MARK: - App State

enum AppState: Equatable {
    case disabled
    case calibrating(TrackingSource = .camera)
    case monitoring(TrackingSource = .camera)
    case paused(PauseReason, context: PauseContext? = nil)

    var isActive: Bool {
        switch self {
        case .monitoring, .calibrating: return true
        case .disabled, .paused: return false
        }
    }
}
