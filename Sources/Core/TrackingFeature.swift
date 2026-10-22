import ComposableArchitecture
import Foundation

enum TrackingMode: String, Equatable, Codable {
    case manual
    case automatic
}

struct TrackingSourceReadiness: Equatable {
    var permissionGranted: Bool = false
    var connected: Bool = false
    var calibrated: Bool = false
    var available: Bool = false
}

struct TrackingFeature: Reducer {
    @Dependency(\.trackingRuntime) var trackingRuntime

    func perform(_ intents: [EffectIntent]) -> Effect<Action> {
        guard !intents.isEmpty else { return .none }
        return .run { _ in
            for intent in intents {
                await trackingRuntime.perform(intent)
            }
        }
    }

    func perform(_ intents: EffectIntent...) -> Effect<Action> {
        perform(intents)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            let previousAppState = state.effectiveAppState
            let effect = handle(action, into: &state)
            return finish(&state, from: previousAppState, effect: effect)
        }
    }

    /// Bookkeeping every transition needs, applied after the action's handler
    private func finish(_ state: inout State, from previousAppState: AppState, effect: Effect<Action>) -> Effect<Action>
    {
        var effect = effect
        // Disabling or recalibrating is a deliberate user action that
        // supersedes a timed pause.
        if state.timedPauseEnd != nil, state.appState == .disabled || state.appState == .calibrating {
            state.timedPauseEnd = nil
            effect = .merge(effect, perform(.cancelTimedPauseEnd))
        }
        if previousAppState.isActive, !state.effectiveAppState.isActive {
            state.monitoringState.reset()
            state.lastPostureReadingTime = nil
        }
        return effect
    }
}

/// Executes the side effects requested by the reducer. The reducer describes
/// every effect as a `TrackingFeature.EffectIntent`; the app installs a single
/// closure that performs them (see `AppDelegate.performTrackingEffect`).
struct TrackingRuntimeClient {
    var perform: @Sendable (TrackingFeature.EffectIntent) async -> Void
}

extension TrackingRuntimeClient {
    static let unimplemented = Self(perform: { _ in })
}

private enum TrackingRuntimeClientKey: DependencyKey {
    static let liveValue = TrackingRuntimeClient.unimplemented
    static let testValue = TrackingRuntimeClient.unimplemented
}

extension DependencyValues {
    var trackingRuntime: TrackingRuntimeClient {
        get { self[TrackingRuntimeClientKey.self] }
        set { self[TrackingRuntimeClientKey.self] = newValue }
    }
}
