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
        trackingSource: TrackingSource
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
                isCurrentlySlouching: isCurrentlySlouching
            )
            return PostureUIState(
                statusText: statusText,
                icon: icon,
                isEnabled: true,
                canRecalibrate: true
            )

        case .paused(let reason, let context):
            let statusText = pausedStatusText(reason: reason, context: context, trackingSource: trackingSource)
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
        isCurrentlySlouching: Bool
    ) -> (String, MenuBarIconType) {
        guard isCalibrated else {
            return (L("status.starting"), .good)
        }

        if isCurrentlyAway {
            return (L("status.away"), .away)
        } else if isCurrentlySlouching {
            return (L("status.slouching"), .bad)
        } else {
            return (L("status.goodPosture"), .good)
        }
    }

    private static func pausedStatusText(reason: PauseReason, context: PauseContext?, trackingSource: TrackingSource) -> String {
        switch reason {
        case .sourceUnavailable:
            return sourceUnavailableStatus(context: context)
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

    private static func sourceUnavailableStatus(context: PauseContext?) -> String {
        guard let context else {
            return L("status.paused")
        }

        let sourceName = context.targetSource.displayName
        let blocker = context.primaryBlocker ?? .needsConnection

        if context.isFallback {
            switch blocker {
            case .needsPermission:
                return L("status.pausedFallbackNeedsPermission", sourceName)
            case .permissionDenied:
                return L("status.pausedFallbackPermissionDenied", sourceName)
            case .needsConnection:
                return L("status.pausedFallbackNeedsConnection", sourceName)
            case .needsCalibration:
                return L("status.pausedFallbackNeedsCalibration", sourceName)
            }
        } else {
            switch blocker {
            case .needsPermission:
                return L("status.pausedSourceNeedsPermission", sourceName)
            case .permissionDenied:
                return L("status.pausedSourcePermissionDenied", sourceName)
            case .needsConnection:
                return L("status.pausedSourceNeedsConnection", sourceName)
            case .needsCalibration:
                return L("status.pausedSourceNeedsCalibration", sourceName)
            }
        }
    }
}
