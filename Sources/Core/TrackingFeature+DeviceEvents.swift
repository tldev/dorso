import ComposableArchitecture
import Foundation

extension TrackingFeature {
    func reduceDeviceEvents(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .airPodsConnectionChanged(let isConnected):
            return airPodsConnectionChanged(&state, isConnected)
        case .cameraConnected(let matchingProfile):
            return cameraConnected(&state, matchingProfile: matchingProfile)
        case .cameraDisconnected(let cameraID, let fallbackCameraID, let profile):
            return cameraDisconnected(&state, cameraID: cameraID, fallbackCameraID: fallbackCameraID, profile: profile)
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
        case .displayConfigurationChanged(let laptopOnly, let anyCamera, let matching, let profile):
            let context = DisplayConfigurationContext(
                pauseOnTheGoEnabled: state.pauseOnTheGoEnabled,
                isLaptopOnlyConfiguration: laptopOnly,
                hasAnyCamera: anyCamera,
                hasMatchingProfileCamera: matching,
                selectedCameraMatchesProfile: profile != nil && profile?.cameraID == state.selectedCameraID
            )
            return displayConfigurationChanged(&state, context, matchingProfile: profile)
        case .cameraSelectionChanged(let cameraID):
            state.selectedCameraID = cameraID
            state.appState = PostureEngine.stateWhenCameraSelectionChanges(
                currentState: state.appState,
                trackingSource: state.activeSource
            )
            return state.activeSource == .camera ? perform(.switchCamera(to: cameraID)) : .none
        case .deskProfileApplied(let profile, let isCameraAvailable):
            guard let profile, isCameraAvailable else {
                state.setCameraCalibration(nil)
                return .none
            }
            let cameraChanged = state.applyCameraProfile(profile)
            return cameraChanged ? perform(.switchCamera(to: profile.cameraID)) : .none
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

    private func cameraConnected(_ state: inout State, matchingProfile: ProfileData?) -> Effect<Action> {
        state.cameraReadiness.connected = true
        if state.trackingMode == .automatic, state.appState != .disabled {
            // The display setup's camera is back, so automatic mode can use it
            var switchEffect: Effect<Action> = .none
            if let matchingProfile, state.applyCameraProfile(matchingProfile) {
                switchEffect = perform(.switchCamera(to: matchingProfile.cameraID))
            }
            return .merge(switchEffect, resolveAutomaticSource(&state))
        }
        let previousState = state.appState
        let result = PostureEngine.stateWhenCameraConnects(
            currentState: state.appState,
            trackingSource: state.activeSource,
            hasMatchingProfileForConnectedCamera: matchingProfile != nil
        )
        state.appState = result.newState

        if result.shouldSelectAndStartMonitoring, let matchingProfile {
            state.applyCameraProfile(matchingProfile)
            return perform(.switchCamera(to: matchingProfile.cameraID), .startMonitoring)
        }

        if result.newState == previousState {
            return perform(.syncUI)
        }
        return .none
    }

    private func cameraDisconnected(
        _ state: inout State,
        cameraID: String,
        fallbackCameraID: String?,
        profile: ProfileData?
    ) -> Effect<Action> {
        let isSelected = cameraID == state.selectedCameraID
        if isSelected {
            state.cameraReadiness.connected = fallbackCameraID != nil
        }
        if state.trackingMode == .automatic, state.appState != .disabled {
            return resolveAutomaticSource(&state)
        }
        let fallbackMatchesProfile = fallbackCameraID != nil && profile?.cameraID == fallbackCameraID
        let result = PostureEngine.stateWhenCameraDisconnects(
            currentState: state.appState,
            trackingSource: state.activeSource,
            disconnectedCameraIsSelected: isSelected,
            hasFallbackCamera: fallbackCameraID != nil,
            fallbackMatchesProfile: fallbackMatchesProfile
        )
        state.appState = result.newState

        switch result.action {
        case .none:
            return .none
        case .syncUIOnly:
            return perform(.syncUI)
        case .switchToFallback(let startMonitoring):
            guard let fallbackCameraID else { return .none }
            state.selectedCameraID = fallbackCameraID
            if let profile, fallbackMatchesProfile {
                state.setCameraCalibration(CameraCalibrationData(profile: profile))
            }
            var intents: [EffectIntent] = [.switchCamera(to: fallbackCameraID)]
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
        if let matchingProfile, context.hasMatchingProfileCamera {
            if result.shouldSwitchToProfileCamera {
                state.applyCameraProfile(matchingProfile)
                intents.append(.switchCamera(to: matchingProfile.cameraID))
            } else if context.selectedCameraMatchesProfile {
                // The same camera can serve several display setups, so load
                // this setup's calibration even without switching
                state.setCameraCalibration(CameraCalibrationData(profile: matchingProfile))
            }
        }
        if result.shouldStartMonitoring {
            intents.append(.startMonitoring)
        }
        return perform(intents)
    }
}
