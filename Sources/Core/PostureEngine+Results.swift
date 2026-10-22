import Foundation

/// Result of processing a posture reading
struct PostureReadingResult: Equatable {
    let newState: PostureMonitoringState
    let effects: [PostureEngineEffect]
}

/// Result of processing an away state change
struct AwayChangeResult: Equatable {
    let newState: PostureMonitoringState
    let shouldUpdateUI: Bool
}

/// Result of applying screen lock behavior to tracking state
struct ScreenLockTransitionResult: Equatable {
    let newState: AppState
    let stateBeforeLock: AppState?
}

/// Result of applying screen unlock behavior to tracking state
struct ScreenUnlockTransitionResult: Equatable {
    let newState: AppState
    let stateBeforeLock: AppState?
    let shouldRestartMonitoring: Bool
}

/// Result of processing an AirPods connection change
struct AirPodsConnectionTransitionResult: Equatable {
    let newState: AppState
    let shouldRestartMonitoring: Bool
}

/// Result of a power source change or pause-on-battery setting change
struct PowerSourceTransitionResult: Equatable {
    let newState: AppState
    let shouldRestartMonitoring: Bool
}

/// Result of camera-connect handling
struct CameraConnectedTransitionResult: Equatable {
    let newState: AppState
    let shouldSelectAndStartMonitoring: Bool
}

enum CameraDisconnectedAction: Equatable {
    case none
    case syncUIOnly
    case switchToFallback(startMonitoring: Bool)
}

/// Result of camera-disconnect handling
struct CameraDisconnectedTransitionResult: Equatable {
    let newState: AppState
    let action: CameraDisconnectedAction
}

/// What a display configuration change can see about the cameras and settings.
struct DisplayConfigurationContext: Equatable {
    var pauseOnTheGoEnabled: Bool
    var isLaptopOnlyConfiguration: Bool
    var hasAnyCamera: Bool
    var hasMatchingProfileCamera: Bool
    var selectedCameraMatchesProfile: Bool
}

/// Result of handling display configuration changes.
struct DisplayConfigurationTransitionResult: Equatable {
    let newState: AppState
    let shouldSwitchToProfileCamera: Bool
    let shouldStartMonitoring: Bool
}

/// Result of switching tracking source manually.
struct SourceSwitchTransitionResult: Equatable {
    let newSource: TrackingSource
    let newState: AppState
    let didSwitchSource: Bool
    let shouldStartMonitoring: Bool
}

/// Result of attempting to start monitoring.
struct MonitoringStartTransitionResult: Equatable {
    let newState: AppState
    let shouldBeginMonitoringSession: Bool
}

/// Result of evaluating startup/initial-setup behavior.
struct InitialSetupTransitionResult: Equatable {
    let shouldApplyStartupCameraProfile: Bool
    let shouldStartMonitoring: Bool
    let shouldShowOnboarding: Bool
}

/// Result of automatic source resolution
struct SourceResolutionResult: Equatable {
    /// The source to activate, or nil to keep current
    let activeSource: TrackingSource?
    let newState: AppState
    let shouldStartMonitoring: Bool
}
