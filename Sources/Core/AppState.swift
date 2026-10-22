import Foundation

// MARK: - Pause Reason

enum PauseReason: Equatable {
    case noProfile
    case onTheGo
    case cameraDisconnected
    case screenLocked
    case airPodsRemoved
    case onBattery
    case timed(until: Date)

    /// Sticky pauses ignore device and source changes (cameras, displays,
    /// AirPods readiness); only their own cause or a direct user action
    /// lifts them. The battery pause lifts on AC power or when its setting
    /// is turned off.
    var isSticky: Bool {
        self == .onBattery
    }
}

// MARK: - App State

enum AppState: Equatable {
    case disabled
    case calibrating
    case monitoring
    case paused(PauseReason)

    var isStickyPause: Bool {
        if case .paused(let reason) = self { return reason.isSticky }
        return false
    }

    var isActive: Bool {
        switch self {
        case .monitoring, .calibrating: return true
        case .disabled, .paused: return false
        }
    }
}
