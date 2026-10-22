import ComposableArchitecture
import Foundation

extension TrackingFeature {
    func reduceMonitoring(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .postureReadingReceived(let reading, let isMarketingMode):
            return postureReadingReceived(&state, reading, isMarketingMode: isMarketingMode)
        case .awayStateChanged(let isAway, let isMarketingMode):
            return awayStateChanged(&state, isAway, isMarketingMode: isMarketingMode)
        case .initialSetupEvaluated(
            let isMarketingMode, let hasProfile, let profileAvailable, let hasAirPods, let profile):
            let result = PostureEngine.stateWhenInitialSetupRuns(
                isMarketingMode: isMarketingMode,
                trackingSource: state.activeSource,
                hasCameraProfile: hasProfile,
                profileCameraAvailable: profileAvailable,
                hasValidAirPodsCalibration: hasAirPods
            )
            return initialSetupEffects(result, cameraProfile: profile)
        case .startMonitoringRequested(let isMarketingMode, let source, let isCalibrated, let isConnected):
            state.manualSource = source
            state.activeSource = source
            state.lastPostureReadingTime = nil
            let result = PostureEngine.stateWhenMonitoringStarts(
                isMarketingMode: isMarketingMode,
                trackingSource: source,
                isCalibrated: isCalibrated,
                isConnected: isConnected
            )
            state.appState = result.newState
            return result.shouldBeginMonitoringSession ? perform(.beginMonitoringSession) : .none
        case .timedPauseRequested(let until):
            guard state.appState != .disabled, state.appState != .calibrating else { return .none }
            state.timedPauseEnd = until
            return perform(.scheduleTimedPauseEnd(until))
        case .timedPauseDeadlineReached(let deadline):
            guard state.timedPauseEnd == deadline else { return .none }
            return endTimedPause(&state)
        case .timedPauseEnded:
            guard state.timedPauseEnd != nil else { return .none }
            return endTimedPause(&state)
        default:
            return .none
        }
    }

    private func postureReadingReceived(
        _ state: inout State,
        _ reading: PostureReading,
        isMarketingMode: Bool
    ) -> Effect<Action> {
        guard state.effectiveAppState == .monitoring else { return .none }

        if isMarketingMode {
            state.monitoringState.isCurrentlySlouching = false
            state.monitoringState.postureWarningIntensity = 0
            state.monitoringState.consecutiveBadFrames = 0
            return perform(.syncUI, .updateBlur)
        }

        let actualElapsed: TimeInterval?
        if let last = state.lastPostureReadingTime {
            let raw = reading.timestamp.timeIntervalSince(last)
            actualElapsed = min(max(0, raw), 2.0)
        } else {
            actualElapsed = nil
        }
        state.lastPostureReadingTime = reading.timestamp

        let result = PostureEngine.processReading(
            reading,
            state: state.monitoringState,
            config: state.postureConfig,
            currentTime: reading.timestamp,
            frameInterval: actualElapsed ?? 0
        )
        state.monitoringState = result.newState

        var intents: [EffectIntent] = []
        for effect in result.effects {
            switch effect {
            case .trackAnalytics(let interval, let isSlouching):
                if actualElapsed != nil {
                    intents.append(.trackAnalytics(interval: interval, isSlouching: isSlouching))
                }
            case .recordSlouchEvent:
                intents.append(.recordSlouchEvent)
            case .updateUI:
                intents.append(.syncUI)
            case .updateBlur:
                intents.append(.updateBlur)
            }
        }
        return perform(intents)
    }

    private func awayStateChanged(_ state: inout State, _ isAway: Bool, isMarketingMode: Bool) -> Effect<Action> {
        guard state.effectiveAppState == .monitoring, !isMarketingMode else { return .none }

        let result = PostureEngine.processAwayChange(
            isAway: isAway,
            state: state.monitoringState
        )
        state.monitoringState = result.newState

        guard result.shouldUpdateUI else { return .none }
        return perform(.syncUI, .updateBlur)
    }

    private func initialSetupEffects(_ result: InitialSetupTransitionResult, cameraProfile: ProfileData?) -> Effect<
        Action
    > {
        var intents: [EffectIntent] = []
        if result.shouldApplyStartupCameraProfile {
            intents.append(.applyStartupCameraProfile(cameraProfile))
        }
        if result.shouldStartMonitoring {
            intents.append(.startMonitoring)
        }
        if result.shouldShowOnboarding {
            intents.append(.showOnboarding)
        }
        return perform(intents)
    }

    // MARK: - Timed Pause

    private func endTimedPause(_ state: inout State) -> Effect<Action> {
        state.timedPauseEnd = nil
        // The detector was stopped for the pause; resume into whatever
        // state the transitions underneath have settled on.
        var intents: [EffectIntent] = [.cancelTimedPauseEnd]
        if PostureEngine.shouldDetectorRun(for: state.appState, trackingSource: state.activeSource) {
            intents.append(.beginMonitoringSession)
        }
        return perform(intents)
    }
}
