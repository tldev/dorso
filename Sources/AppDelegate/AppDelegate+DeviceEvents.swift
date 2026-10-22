import AppKit
import AVFoundation

extension AppDelegate {
    // MARK: - Camera Hot-Plug

    func handleCameraConnected(_ device: AVCaptureDevice) async {
        guard activeTrackingSource == .camera || trackingMode == .automatic else { return }

        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = loadProfile(forKey: configKey)

        await applyCameraConnectedTransition(
            hasMatchingProfile: profile?.cameraID == device.uniqueID,
            matchingProfile: profile
        )
    }

    func handleCameraDisconnected(_ device: AVCaptureDevice) async {
        guard activeTrackingSource == .camera || trackingMode == .automatic else { return }

        let disconnectedCameraIsSelected = device.uniqueID == selectedCameraID
        let fallbackCamera = cameraDetector.getAvailableCameras().first
        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = loadProfile(forKey: configKey)
        let fallbackHasMatchingProfile = fallbackCamera != nil && profile?.cameraID == fallbackCamera?.uniqueID

        await applyCameraDisconnectedTransition(
            disconnectedCameraIsSelected: disconnectedCameraIsSelected,
            hasFallbackCamera: fallbackCamera != nil,
            fallbackHasMatchingProfile: fallbackHasMatchingProfile,
            fallbackCamera: fallbackCamera,
            fallbackProfile: profile
        )
    }

    func applyCameraConnectedTransition(
        hasMatchingProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await sendTrackingAction(
            .cameraConnected(
                hasMatchingProfile: hasMatchingProfile,
                matchingProfile: matchingProfile
            )
        )
    }

    func applyCameraDisconnectedTransition(
        disconnectedCameraIsSelected: Bool,
        hasFallbackCamera: Bool,
        fallbackHasMatchingProfile: Bool,
        fallbackCamera: AVCaptureDevice?,
        fallbackProfile: ProfileData?
    ) async {
        await sendTrackingAction(
            .cameraDisconnected(
                disconnectedCameraIsSelected: disconnectedCameraIsSelected,
                hasFallbackCamera: hasFallbackCamera,
                fallbackHasMatchingProfile: fallbackHasMatchingProfile,
                fallbackCameraID: fallbackCamera?.uniqueID,
                fallbackProfile: fallbackProfile
            )
        )
    }

    func applyCameraSelectionTransition() async {
        await sendTrackingAction(.cameraSelectionChanged)
    }

    // MARK: - Screen Lock

    func handleScreenLocked() async {
        await sendTrackingAction(.screenLocked)
    }

    func handleScreenUnlocked() async {
        // The power source may have changed while the lid was closed or the
        // screen locked; refresh so the unlock transition sees the true state.
        await sendTrackingAction(.powerSourceChanged(isOnBattery: powerSourceObserver.isOnBattery))
        await sendTrackingAction(.screenUnlocked)
    }

    // MARK: - Power Source

    func handlePowerSourceChanged(_ isOnBattery: Bool) async {
        await sendTrackingAction(.powerSourceChanged(isOnBattery: isOnBattery))
    }

    // MARK: - Display Configuration

    func handleDisplayConfigurationChange(rebuildOverlays: Bool = true) async {
        if rebuildOverlays {
            rebuildOverlayWindows()
            onDesksChanged?()
        }

        guard state != .disabled else { return }

        let cameraIDs = availableCameraIDs()
        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = loadProfile(forKey: configKey)
        let hasMatchingProfileCamera = profile.map { cameraIDs.contains($0.cameraID) } ?? false
        let selectedCameraMatchesProfile = profile.map { profile in
            selectedCameraID == profile.cameraID
        } ?? false

        // Switching cameras is what normally applies a profile's calibration,
        // but one camera can serve several display setups
        if let profile, hasMatchingProfileCamera, selectedCameraMatchesProfile {
            applyCameraCalibration(from: profile)
        }

        await applyDisplayConfigurationTransition(
            pauseOnTheGoEnabled: pauseOnTheGo,
            isLaptopOnlyConfiguration: DisplayMonitor.isLaptopOnlyConfiguration(),
            hasAnyCamera: !cameraIDs.isEmpty,
            hasMatchingProfileCamera: hasMatchingProfileCamera,
            selectedCameraMatchesProfile: selectedCameraMatchesProfile,
            matchingProfile: profile
        )
    }

    // MARK: - Desks

    func desksForMenu() -> (desks: [(id: String, name: String)], activeID: String?) {
        // Automatic mode can switch to the camera at any time
        guard activeTrackingSource == .camera || trackingMode == .automatic else { return ([], nil) }
        let key = DisplayMonitor.getCurrentConfigKey()
        let desks = deskStore.desks(forKey: key).map { (id: $0.id, name: $0.name) }
        return (desks, deskStore.activeDesk(forKey: key)?.id)
    }

    func selectDesk(id: String) async {
        let key = DisplayMonitor.getCurrentConfigKey()
        // Samples being taken belong to the desk active when calibration started
        guard state != .calibrating else {
            onDesksChanged?()
            return
        }
        guard deskStore.activeDesk(forKey: key)?.id != id,
              deskStore.selectDesk(id: id, forKey: key) != nil else { return }
        await applyActiveDesk(forKey: key)
    }

    func deleteDesk(id: String) async {
        let key = DisplayMonitor.getCurrentConfigKey()
        guard state != .calibrating else { return }
        let wasActive = deskStore.activeDesk(forKey: key)?.id == id
        guard deskStore.deleteDesk(id: id, forKey: key), wasActive else { return }
        await applyActiveDesk(forKey: key)
    }

    private func applyActiveDesk(forKey key: String) async {
        defer { onDesksChanged?() }
        lineUpActiveDesk(forKey: key)
        guard state != .disabled else { return }
        await handleDisplayConfigurationChange(rebuildOverlays: false)
    }

    /// The display transition leaves the camera alone in several states
    /// (disabled, battery and on-the-go pauses, AirPods active), so point it
    /// at the active desk directly.
    func lineUpActiveDesk(forKey key: String) {
        if let profile = loadProfile(forKey: key), availableCameraIDs().contains(profile.cameraID) {
            if selectedCameraID != profile.cameraID {
                cameraDetector.selectedCameraID = profile.cameraID
                // No-op unless the session is running
                cameraDetector.switchCamera(to: profile.cameraID)
            }
            applyCameraCalibration(from: profile)
        } else {
            cameraCalibration = nil
        }
        if trackingMode == .automatic {
            updateSourceReadiness()
        }
    }

    func availableCameraIDs() -> [String] {
        availableCameraIDsOverride?() ?? cameraDetector.getAvailableCameras().map(\.uniqueID)
    }

    func applyDisplayConfigurationTransition(
        pauseOnTheGoEnabled: Bool,
        isLaptopOnlyConfiguration: Bool,
        hasAnyCamera: Bool,
        hasMatchingProfileCamera: Bool,
        selectedCameraMatchesProfile: Bool,
        matchingProfile: ProfileData?
    ) async {
        await sendTrackingAction(
            .displayConfigurationChanged(
                pauseOnTheGoEnabled: pauseOnTheGoEnabled,
                isLaptopOnlyConfiguration: isLaptopOnlyConfiguration,
                hasAnyCamera: hasAnyCamera,
                hasMatchingProfileCamera: hasMatchingProfileCamera,
                selectedCameraMatchesProfile: selectedCameraMatchesProfile,
                matchingProfile: matchingProfile
            )
        )
    }
}
