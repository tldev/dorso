import Foundation

/// Pure state container for posture monitoring - no side effects, fully testable
struct PostureMonitoringState: Equatable {
    var consecutiveBadFrames: Int = 0
    var consecutiveGoodFrames: Int = 0
    var isCurrentlySlouching: Bool = false
    var isCurrentlyAway: Bool = false
    var badPostureStartTime: Date? = nil
    var postureWarningIntensity: CGFloat = 0

    mutating func reset() {
        consecutiveBadFrames = 0
        consecutiveGoodFrames = 0
        isCurrentlySlouching = false
        isCurrentlyAway = false
        badPostureStartTime = nil
        postureWarningIntensity = 0
    }
}

/// Configuration for posture detection thresholds
struct PostureConfig: Equatable {
    var frameThreshold: Int = 8
    var goodFrameThreshold: Int = 5
    var warningOnsetDelay: TimeInterval = 0
    var intensity: CGFloat = 1.0
}

/// Side effects that the engine requests but doesn't execute
enum PostureEngineEffect: Equatable {
    case updateUI
    case updateBlur
    case recordSlouchEvent
    case trackAnalytics(interval: TimeInterval, isSlouching: Bool)
}

/// Pure logic engine for posture monitoring - no side effects
struct PostureEngine {

    // MARK: - Automatic Source Resolution

    /// Resolves which source should be active in automatic mode.
    /// "Ready" means calibrated AND connected.
    static func resolveActiveSource(
        preferred: TrackingSource,
        currentActive: TrackingSource,
        currentState: AppState,
        preferredReadiness: TrackingSourceReadiness,
        fallbackReadiness: TrackingSourceReadiness,
        autoReturn: Bool
    ) -> SourceResolutionResult {
        let preferredReady = preferredReadiness.calibrated && preferredReadiness.connected
        let fallbackReady = fallbackReadiness.calibrated && fallbackReadiness.connected

        // Preferred is ready — use it
        if preferredReady {
            let shouldStart = currentActive != preferred || !currentState.isActive
            return SourceResolutionResult(
                activeSource: preferred,
                newState: .monitoring,
                shouldStartMonitoring: shouldStart
            )
        }

        // Preferred not ready, fallback is ready — use fallback
        if fallbackReady {
            let shouldStart = currentActive != preferred.other || !currentState.isActive
            return SourceResolutionResult(
                activeSource: preferred.other,
                newState: .monitoring,
                shouldStartMonitoring: shouldStart
            )
        }

        // Preferred connected but not calibrated, fallback not ready
        if preferredReadiness.connected && !preferredReadiness.calibrated {
            return SourceResolutionResult(
                activeSource: nil,
                newState: .paused(.noProfile),
                shouldStartMonitoring: false
            )
        }

        // Neither ready — pause with preferred's unavail reason
        return SourceResolutionResult(
            activeSource: nil,
            newState: unavailableState(for: preferred),
            shouldStartMonitoring: false
        )
    }

    // MARK: - Posture Reading Processing

    /// Process a posture reading and return new state + requested effects
    static func processReading(
        _ reading: PostureReading,
        state: PostureMonitoringState,
        config: PostureConfig,
        currentTime: Date = Date(),
        frameInterval: TimeInterval = 0.1
    ) -> PostureReadingResult {
        var newState = state
        var effects: [PostureEngineEffect] = []

        // Always track analytics
        effects.append(.trackAnalytics(interval: frameInterval, isSlouching: state.isCurrentlySlouching))

        if reading.isBadPosture {
            newState.consecutiveBadFrames += 1
            newState.consecutiveGoodFrames = 0

            if newState.consecutiveBadFrames >= config.frameThreshold {
                // Start tracking when bad posture began
                if newState.badPostureStartTime == nil {
                    newState.badPostureStartTime = currentTime
                }

                // Check onset delay
                let badStartTime = newState.badPostureStartTime ?? currentTime
                let elapsedTime = currentTime.timeIntervalSince(badStartTime)
                let onsetDelay = max(0, config.warningOnsetDelay)
                if elapsedTime >= onsetDelay {
                    // Transition to slouching if not already
                    if !newState.isCurrentlySlouching {
                        newState.isCurrentlySlouching = true
                        effects.append(.recordSlouchEvent)
                        effects.append(.updateUI)
                    }

                    // Calculate warning intensity
                    let rawIntensity = Double(config.intensity)
                    let intensity = rawIntensity > 0 ? rawIntensity : 1.0
                    let clampedSeverity = min(1.0, max(0.0, reading.severity))
                    let adjustedSeverity = pow(clampedSeverity, 1.0 / intensity)
                    newState.postureWarningIntensity = CGFloat(adjustedSeverity)
                }
            }
        } else {
            newState.consecutiveGoodFrames += 1
            newState.consecutiveBadFrames = 0
            newState.badPostureStartTime = nil
            newState.postureWarningIntensity = 0

            // Transition back to good posture
            if newState.consecutiveGoodFrames >= config.goodFrameThreshold && newState.isCurrentlySlouching {
                newState.isCurrentlySlouching = false
                effects.append(.updateUI)
            }
        }

        effects.append(.updateBlur)

        return PostureReadingResult(newState: newState, effects: effects)
    }

    // MARK: - Away State Processing

    /// Process an away state change
    static func processAwayChange(
        isAway: Bool,
        state: PostureMonitoringState
    ) -> AwayChangeResult {
        guard isAway != state.isCurrentlyAway else {
            return AwayChangeResult(newState: state, shouldUpdateUI: false)
        }

        var newState = state
        newState.isCurrentlyAway = isAway

        return AwayChangeResult(newState: newState, shouldUpdateUI: true)
    }

    // MARK: - State Machine Transitions

    /// Determine if a state transition should be allowed
    static func canTransition(from currentState: AppState, to newState: AppState) -> Bool {
        switch (currentState, newState) {
        case (.disabled, .monitoring),
            (.disabled, .paused),
            (.disabled, .calibrating),
            (.monitoring, .disabled),
            (.monitoring, .paused),
            (.monitoring, .calibrating),
            (.paused, .disabled),
            (.paused, .monitoring),
            (.paused, .calibrating),
            (.calibrating, .monitoring),
            (.calibrating, .paused),
            (.calibrating, .disabled):
            return true
        default:
            return currentState != newState
        }
    }

    /// Determine if the detector should be running for a given state
    static func shouldDetectorRun(for state: AppState, trackingSource: TrackingSource) -> Bool {
        switch state {
        case .calibrating, .monitoring:
            return true
        case .paused(let reason):
            // Keep AirPods detector running when paused due to removal
            // so we can detect when they're put back in ears
            if reason == .airPodsRemoved && trackingSource == .airpods {
                return true
            }
            return false
        case .disabled:
            return false
        }
    }

    /// Pause reason used when the current source is unavailable.
    static func unavailabilityPauseReason(for trackingSource: TrackingSource) -> PauseReason {
        switch trackingSource {
        case .camera:
            return .cameraDisconnected
        case .airpods:
            return .airPodsRemoved
        }
    }

    /// Pause state used when the current source is unavailable.
    static func unavailableState(for trackingSource: TrackingSource) -> AppState {
        .paused(unavailabilityPauseReason(for: trackingSource))
    }
}
