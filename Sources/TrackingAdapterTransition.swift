import Foundation

/// Adapter-level state commit rules for deferred reducer transitions.
struct TrackingAdapterTransition {
    /// Resolve which app state should be committed after executing reducer effect intents.
    static func committedAppState(
        currentStateAfterEffects: AppState,
        reducerState: AppState,
        effectIntents: [TrackingFeature.EffectIntent]
    ) -> AppState {
        guard shouldCommitReducerState(effectIntents: effectIntents) else {
            return currentStateAfterEffects
        }
        return reducerState
    }

    /// Reducer state is not committed when monitoring restart was requested,
    /// because runtime `startMonitoring()` determines the final state.
    static func shouldCommitReducerState(
        effectIntents: [TrackingFeature.EffectIntent]
    ) -> Bool {
        !effectIntents.contains { intent in
            if case .startMonitoring = intent {
                return true
            }
            return false
        }
    }
}
