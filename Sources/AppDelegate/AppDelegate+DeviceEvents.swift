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
        await sendTrackingAction(.screenUnlocked)
    }

    // MARK: - Display Configuration

    func handleDisplayConfigurationChange() async {
        rebuildOverlayWindows()

        guard state != .disabled else { return }

        let cameras = cameraDetector.getAvailableCameras()
        let configKey = DisplayMonitor.getCurrentConfigKey()
        let profile = loadProfile(forKey: configKey)
        let hasMatchingProfileCamera = profile.map { profile in
            cameras.contains(where: { $0.uniqueID == profile.cameraID })
        } ?? false
        let selectedCameraMatchesProfile = profile.map { profile in
            selectedCameraID == profile.cameraID
        } ?? false

        await applyDisplayConfigurationTransition(
            pauseOnTheGoEnabled: pauseOnTheGo,
            isLaptopOnlyConfiguration: DisplayMonitor.isLaptopOnlyConfiguration(),
            hasAnyCamera: !cameras.isEmpty,
            hasMatchingProfileCamera: hasMatchingProfileCamera,
            selectedCameraMatchesProfile: selectedCameraMatchesProfile,
            matchingProfile: profile
        )
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
