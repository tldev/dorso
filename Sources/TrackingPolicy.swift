import Foundation

enum TrackingPolicy: Equatable {
    case manual(source: TrackingSource)
    case automatic(preferred: TrackingSource, autoReturn: Bool = true)

    var mode: TrackingPolicyMode {
        switch self {
        case .manual: return .manual
        case .automatic: return .automatic
        }
    }

    var preferredSource: TrackingSource {
        switch self {
        case .manual(let source):
            return source
        case .automatic(let preferred, _):
            return preferred
        }
    }

    var manualSource: TrackingSource {
        switch self {
        case .manual(let source):
            return source
        case .automatic(let preferred, _):
            return preferred
        }
    }

    var autoReturnEnabled: Bool {
        switch self {
        case .manual:
            return false
        case .automatic(_, let autoReturn):
            return autoReturn
        }
    }
}

enum TrackingPolicyMode: String, Codable {
    case manual
    case automatic
}

enum PermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
}

enum ConnectionState: Equatable {
    case connected
    case disconnected
}

enum CalibrationState: Equatable {
    case calibrated
    case notCalibrated
}

enum SourceBlocker: String, Codable, Equatable, Hashable {
    case needsPermission
    case permissionDenied
    case needsConnection
    case needsCalibration

    var priority: Int {
        switch self {
        case .needsPermission: return 0
        case .permissionDenied: return 1
        case .needsConnection: return 2
        case .needsCalibration: return 3
        }
    }
}

struct SourceReadiness: Equatable {
    let source: TrackingSource
    let permissionState: PermissionState
    let connectionState: ConnectionState
    let calibrationState: CalibrationState
    let blockers: [SourceBlocker]

    var isReady: Bool { blockers.isEmpty }
}

enum TrackingAction: Equatable {
    case allowPermission(source: TrackingSource)
    case openPrivacySettings(source: TrackingSource)
    case connectDevice(source: TrackingSource)
    case calibrate(source: TrackingSource)
}

struct PauseContext: Equatable {
    let targetSource: TrackingSource
    let blockers: [SourceBlocker]
    let isFallback: Bool

    var primaryBlocker: SourceBlocker? {
        blockers.first
    }
}

struct TrackingDecision: Equatable {
    let activeSource: TrackingSource?
    let pauseContext: PauseContext?
    let primaryAction: TrackingAction?
    let secondaryAction: TrackingAction?
}

struct TrackingResolver {
    static func resolve(
        policy: TrackingPolicy,
        currentActiveSource: TrackingSource,
        readiness: [TrackingSource: SourceReadiness]
    ) -> TrackingDecision {
        switch policy {
        case .manual(let source):
            let sourceReadiness = readiness[source] ?? unresolvedReadiness(for: source)
            if sourceReadiness.isReady {
                return TrackingDecision(
                    activeSource: source,
                    pauseContext: nil,
                    primaryAction: nil,
                    secondaryAction: nil
                )
            }

            return pausedDecision(
                target: source,
                sourceReadiness: sourceReadiness,
                isFallback: false
            )

        case .automatic(let preferred, _):
            let other = preferred.other
            let preferredReadiness = readiness[preferred] ?? unresolvedReadiness(for: preferred)
            if preferredReadiness.isReady {
                return TrackingDecision(
                    activeSource: preferred,
                    pauseContext: nil,
                    primaryAction: nil,
                    secondaryAction: nil
                )
            }

            let fallbackReadiness = readiness[other] ?? unresolvedReadiness(for: other)
            if fallbackReadiness.isReady {
                return TrackingDecision(
                    activeSource: other,
                    pauseContext: nil,
                    primaryAction: nil,
                    secondaryAction: nil
                )
            }

            return pausedDecision(
                target: other,
                sourceReadiness: fallbackReadiness,
                isFallback: true
            )
        }
    }

    private static func pausedDecision(
        target: TrackingSource,
        sourceReadiness: SourceReadiness,
        isFallback: Bool
    ) -> TrackingDecision {
        let blockers = sourceReadiness.blockers.sorted { $0.priority < $1.priority }
        let pauseContext = PauseContext(targetSource: target, blockers: blockers, isFallback: isFallback)

        return TrackingDecision(
            activeSource: nil,
            pauseContext: pauseContext,
            primaryAction: action(for: blockers.first, source: target),
            secondaryAction: action(for: blockers.dropFirst().first, source: target)
        )
    }

    private static func action(for blocker: SourceBlocker?, source: TrackingSource) -> TrackingAction? {
        guard let blocker else { return nil }
        switch blocker {
        case .needsPermission:
            return .allowPermission(source: source)
        case .permissionDenied:
            return .openPrivacySettings(source: source)
        case .needsConnection:
            return .connectDevice(source: source)
        case .needsCalibration:
            return .calibrate(source: source)
        }
    }

    private static func unresolvedReadiness(for source: TrackingSource) -> SourceReadiness {
        SourceReadiness(
            source: source,
            permissionState: .denied,
            connectionState: .disconnected,
            calibrationState: .notCalibrated,
            blockers: [.permissionDenied]
        )
    }
}

extension TrackingSource {
    var other: TrackingSource {
        self == .camera ? .airpods : .camera
    }
}
