import ComposableArchitecture
import Foundation

extension TrackingFeature {
    func reduceDeviceEvents(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .airPodsConnectionChanged(let isConnected):
            return airPodsConnectionChanged(&state, isConnected)
        case .cameraConnected(let hasMatchingProfile, let matchingProfile):
            return cameraConnected(&state, hasMatchingProfile: hasMatchingProfile, matchingProfile: matchingProfile)
        case .cameraDisconnected(let isSelected, let hasFallback, let fallbackMatches, let fallbackID, let profile):
            if isSelected {
                state.cameraReadiness.connected = hasFallback
            }
            if state.trackingMode == .automatic, state.appState != .disabled {
                return resolveAutomaticSource(&state)
            }
            let result = PostureEngine.stateWhenCameraDisconnects(
                currentState: state.appState,
                trackingSource: state.activeSource,
                disconnectedCameraIsSelected: isSelected,
                hasFallbackCamera: hasFallback,
                fallbackMatchesProfile: fallbackMatches
            )
            state.appState = result.newState
            return cameraDisconnectedEffects(result.action, fallbackCameraID: fallbackID, fallbackProfile: profile)
        case .screenLocked:
            let result = PostureEngine.stateWhenScreenLocks(
                currentState: state.appState,
                trackingSource: state.activeSource,
                stateBeforeLock: state.stateBeforeLock
            )
            state.appState = result.newState
            state.stateBeforeLock = result.stateBeforeLock
            return .none
        case .screenUnlocked:
            return screenUnlocked(&state)
        case .powerSourceChanged(let isOnBattery):
            return powerSourceChanged(&state, isOnBattery: isOnBattery)
        case .setPauseOnBatteryEnabled(let isEnabled):
            return setPauseOnBatteryEnabled(&state, isEnabled)
        case .displayConfigurationChanged(
            let onTheGo, let laptopOnly, let anyCamera, let matching, let selected, let profile):
            let context = DisplayConfigurationContext(
                pauseOnTheGoEnabled: onTheGo,
                isLaptopOnlyConfiguration: laptopOnly,
                hasAnyCamera: anyCamera,
                hasMatchingProfileCamera: matching,
                selectedCameraMatchesProfile: selected
            )
            return displayConfigurationChanged(&state, context, matchingProfile: profile)
        case .cameraSelectionChanged:
            state.appState = PostureEngine.stateWhenCameraSelectionChanges(
                currentState: state.appState,
                trackingSource: state.activeSource
            )
            return state.activeSource == .camera ? perform(.switchCamera(.selectedCamera)) : .none
        default:
            return .none
        }
    }

    private func airPodsConnectionChanged(_ state: inout State, _ isConnected: Bool) -> Effect<Action> {
        state.airPodsReadiness.connected = isConnected
        if state.trackingMode == .automatic, state.appState != .disabled {
            return resolveAutomaticSource(&state)
        }
        let result = PostureEngine.stateWhenAirPodsConnectionChanges(
            currentState: state.appState,
            trackingSource: state.activeSource,
            isConnected: isConnected
        )
        state.appState = result.newState
        if result.shouldRestartMonitoring {
            return perform(.startMonitoring)
        }
        return .none
    }

    private func cameraConnected(
        _ state: inout State,
        hasMatchingProfile: Bool,
        matchingProfile: ProfileData?
    ) -> Effect<Action> {
        state.cameraReadiness.connected = true
        if hasMatchingProfile {
            state.cameraReadiness.calibrated = true
        }
        if state.trackingMode == .automatic, state.appState != .disabled {
            return resolveAutomaticSource(&state)
        }
        let previousState = state.appState
        let result = PostureEngine.stateWhenCameraConnects(
            currentState: state.appState,
            trackingSource: state.activeSource,
            hasMatchingProfileForConnectedCamera: hasMatchingProfile
        )
        state.appState = result.newState

        if result.shouldSelectAndStartMonitoring {
            return perform(.switchCamera(.matchingProfile(matchingProfile)), .startMonitoring)
        }

        if result.newState == previousState {
            return perform(.syncUI)
        }
        return .none
    }

    private func cameraDisconnectedEffects(
        _ action: CameraDisconnectedAction,
        fallbackCameraID: String?,
        fallbackProfile: ProfileData?
    ) -> Effect<Action> {
        switch action {
        case .none:
            return .none
        case .syncUIOnly:
            return perform(.syncUI)
        case .switchToFallback(let startMonitoring):
            var intents: [EffectIntent] = [
                .switchCamera(.fallback(cameraID: fallbackCameraID, profile: fallbackProfile))
            ]
            if startMonitoring {
                intents.append(.startMonitoring)
            }
            return perform(intents)
        }
    }

    private func screenUnlocked(_ state: inout State) -> Effect<Action> {
        let result = PostureEngine.stateWhenScreenUnlocks(
            currentState: state.appState,
            stateBeforeLock: state.stateBeforeLock,
            pauseOnBatteryEnabled: state.pauseOnBatteryEnabled,
            isOnBattery: state.isOnBattery
        )
        state.appState = result.newState
        state.stateBeforeLock = result.stateBeforeLock
        if result.shouldRestartMonitoring {
            return perform(.startMonitoring)
        }
        return .none
    }

    private func powerSourceChanged(_ state: inout State, isOnBattery: Bool) -> Effect<Action> {
        state.isOnBattery = isOnBattery
        let result = PostureEngine.stateWhenPowerSourceChanges(
            currentState: state.appState,
            isOnBattery: isOnBattery,
            pauseOnBatteryEnabled: state.pauseOnBatteryEnabled
        )
        state.appState = result.newState
        if result.shouldRestartMonitoring {
            return perform(.startMonitoring)
        }
        return .none
    }

    private func setPauseOnBatteryEnabled(_ state: inout State, _ isEnabled: Bool) -> Effect<Action> {
        state.pauseOnBatteryEnabled = isEnabled
        let result = PostureEngine.stateWhenPauseOnBatterySettingChanges(
            currentState: state.appState,
            isEnabled: isEnabled,
            isOnBattery: state.isOnBattery
        )
        state.appState = result.newState
        if result.shouldRestartMonitoring {
            return perform(.startMonitoring)
        }
        return .none
    }

    private func displayConfigurationChanged(
        _ state: inout State,
        _ context: DisplayConfigurationContext,
        matchingProfile: ProfileData?
    ) -> Effect<Action> {
        let result = PostureEngine.stateWhenDisplayConfigurationChanges(
            currentState: state.appState,
            trackingSource: state.activeSource,
            context: context
        )
        state.appState = result.newState

        var intents: [EffectIntent] = []
        if result.shouldSwitchToProfileCamera {
            intents.append(.switchCamera(.matchingProfile(matchingProfile)))
        }
        if result.shouldStartMonitoring {
            intents.append(.startMonitoring)
        }
        return perform(intents)
    }
}
