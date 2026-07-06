import Foundation

/// Icon types that map to MenuBarIcon - keeps this module UI-framework agnostic
enum MenuBarIconType: Equatable {
    case good
    case bad
    case away
    case paused
    case calibrating
}

/// Pure representation of the UI state - no dependencies on AppKit
struct PostureUIState: Equatable {
    let statusText: String
    let icon: MenuBarIconType
    let isEnabled: Bool
    let canRecalibrate: Bool

    /// Derives the complete UI state from the current app state and flags
    static func derive(
        from appState: AppState,
        isCalibrated: Bool,
        isCurrentlyAway: Bool,
        isCurrentlySlouching: Bool,
        trackingSource: TrackingSource,
        isOnFallback: Bool = false
    ) -> PostureUIState {
        switch appState {
        case .disabled:
            return PostureUIState(
                statusText: L("status.disabled"),
                icon: .paused,
                isEnabled: false,
                canRecalibrate: true
            )

        case .calibrating:
            return PostureUIState(
                statusText: L("status.calibrating"),
                icon: .calibrating,
                isEnabled: true,
                canRecalibrate: false
            )

        case .monitoring:
            let (statusText, icon) = monitoringState(
                isCalibrated: isCalibrated,
                isCurrentlyAway: isCurrentlyAway,
                isCurrentlySlouching: isCurrentlySlouching,
                isOnFallback: isOnFallback,
                fallbackSource: trackingSource
            )
            return PostureUIState(
                statusText: statusText,
                icon: icon,
                isEnabled: true,
                canRecalibrate: true
            )

        case .paused(let reason):
            let statusText = pausedStatusText(reason: reason, trackingSource: trackingSource)
            return PostureUIState(
                statusText: statusText,
                icon: .paused,
                isEnabled: true,
                canRecalibrate: true
            )
        }
    }

    private static func monitoringState(
        isCalibrated: Bool,
        isCurrentlyAway: Bool,
        isCurrentlySlouching: Bool,
        isOnFallback: Bool = false,
        fallbackSource: TrackingSource = .camera
    ) -> (String, MenuBarIconType) {
        guard isCalibrated else {
            return (L("status.starting"), .good)
        }

        let suffix = isOnFallback ? " (\(fallbackSource.displayName))" : ""

        if isCurrentlyAway {
            return (L("status.away") + suffix, .away)
        } else if isCurrentlySlouching {
            return (L("status.slouching") + suffix, .bad)
        } else {
            return (L("status.goodPosture") + suffix, .good)
        }
    }

    private static func pausedStatusText(reason: PauseReason, trackingSource: TrackingSource) -> String {
        switch reason {
        case .noProfile:
            return L("status.calibrationNeeded")
        case .onTheGo:
            return L("status.pausedOnTheGo")
        case .cameraDisconnected:
            return trackingSource == .camera ? L("status.cameraDisconnected") : L("status.airPodsDisconnected")
        case .screenLocked:
            return L("status.pausedScreenLocked")
        case .airPodsRemoved:
            return L("status.pausedPutInAirPods")
        }
    }
}
