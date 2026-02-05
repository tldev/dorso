import Foundation

// MARK: - Pause Reason

enum PauseReason: Equatable {
    case noProfile
    case onTheGo
    case cameraDisconnected
    case screenLocked
    case airPodsRemoved
}

// MARK: - App State

enum AppState: Equatable {
    case disabled
    case calibrating
    case monitoring
    case paused(PauseReason)

    var isActive: Bool {
        switch self {
        case .monitoring, .calibrating: return true
        case .disabled, .paused: return false
        }
    }
}

