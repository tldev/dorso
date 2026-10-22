import AVFoundation
import AppKit

extension AppDelegate {
    // MARK: - Observers Setup

    func setupObservers() {
        // Display configuration changes
        displayMonitor.onDisplayConfigurationChange = { [weak self] in
            Task { @MainActor in
                await self?.handleDisplayConfigurationChange()
            }
        }
        displayMonitor.startMonitoring()

        // Camera hot-plug
        cameraObserver.onCameraConnected = { [weak self] device in
            Task { @MainActor in
                await self?.handleCameraConnected(device)
            }
        }
        cameraObserver.onCameraDisconnected = { [weak self] device in
            Task { @MainActor in
                await self?.handleCameraDisconnected(device)
            }
        }
        cameraObserver.startObserving()

        // Screen lock/unlock
        screenLockObserver.onScreenLocked = { [weak self] in
            Task { @MainActor in
                await self?.handleScreenLocked()
            }
        }
        screenLockObserver.onScreenUnlocked = { [weak self] in
            Task { @MainActor in
                await self?.handleScreenUnlocked()
            }
        }
        screenLockObserver.startObserving()

        // AC/battery power source
        powerSourceObserver.onPowerSourceChanged = { [weak self] isOnBattery in
            Task { @MainActor in
                await self?.handlePowerSourceChanged(isOnBattery)
            }
        }
        powerSourceObserver.startObserving()

        // Global hotkey
        hotkeyManager.configure(
            enabled: toggleShortcutEnabled,
            shortcut: toggleShortcut,
            onToggle: { [weak self] in
                Task { @MainActor in
                    await self?.toggleEnabled()
                }
            }
        )
    }

    // MARK: - Camera Hot-Plug

    func handleCameraConnected(_ device: AVCaptureDevice) async {
        guard activeTrackingSource == .camera || trackingMode == .automatic else { return }

        let profile = loadProfile(forKey: DisplayMonitor.getCurrentConfigKey())
        await sendTrackingAction(
            .cameraConnected(matchingProfile: profile?.cameraID == device.uniqueID ? profile : nil))
    }

    func handleCameraDisconnected(_ device: AVCaptureDevice) async {
        guard activeTrackingSource == .camera || trackingMode == .automatic else { return }

        await sendTrackingAction(
            .cameraDisconnected(
                cameraID: device.uniqueID,
                fallbackCameraID: availableCameraIDs().first,
                profile: loadProfile(forKey: DisplayMonitor.getCurrentConfigKey())
            )
        )
    }

    /// Selects a camera from Settings. A camera change needs recalibration
    /// only while it is the active source.
    func selectCamera(_ cameraID: String) async {
        if activeTrackingSource == .camera {
            await sendTrackingAction(.cameraSelectionChanged(cameraID))
        } else {
            selectedCameraID = cameraID
        }
        saveSettings()
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
            displayChanges.send()
        }

        guard state != .disabled else { return }

        let cameraIDs = availableCameraIDs()
        let profile = loadProfile(forKey: DisplayMonitor.getCurrentConfigKey())
        await sendTrackingAction(
            .displayConfigurationChanged(
                isLaptopOnlyConfiguration: DisplayMonitor.isLaptopOnlyConfiguration(),
                hasAnyCamera: !cameraIDs.isEmpty,
                hasMatchingProfileCamera: profile.map { cameraIDs.contains($0.cameraID) } ?? false,
                matchingProfile: profile
            )
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
        guard state != .calibrating else { return }
        guard deskStore.activeDesk(forKey: key)?.id != id,
            deskStore.selectDesk(id: id, forKey: key) != nil
        else { return }
        await applyActiveDesk(forKey: key)
    }

    func deleteDesk(id: String) async {
        let key = DisplayMonitor.getCurrentConfigKey()
        guard state != .calibrating else { return }
        let wasActive = deskStore.activeDesk(forKey: key)?.id == id
        guard deskStore.deleteDesk(id: id, forKey: key), wasActive else { return }
        await applyActiveDesk(forKey: key)
    }

    /// Loads the active desk's calibration; the reducer decides whether
    /// tracking restarts with it.
    func applyActiveDesk(forKey key: String) async {
        let profile = loadProfile(forKey: key)
        let isCameraAvailable = profile.map { availableCameraIDs().contains($0.cameraID) } ?? false
        if trackingMode == .automatic {
            updateSourceReadiness()
        }
        await sendTrackingAction(.deskProfileApplied(profile, isCameraAvailable: isCameraAvailable))
    }

    func availableCameraIDs() -> [String] {
        availableCameraIDsOverride?() ?? cameraDetector.getAvailableCameras().map(\.uniqueID)
    }
}
