import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Settings View

@MainActor
struct SettingsView: View {
    let appDelegate: AppDelegate
    let settingsProfileManager: SettingsProfileManager

    // Local state that syncs with AppDelegate - initialized from appDelegate in init()
    @State private var intensity: Double
    @State private var deadZone: Double
    @State private var intensitySlider: Double
    @State private var deadZoneSlider: Double
    @State private var blurWhenAway: Bool
    @State private var showInDock: Bool
    @State private var pauseOnTheGo: Bool
    @State private var useCompatibilityMode: Bool
    @State private var useFullScreenOverlay: Bool
    @State private var selectedCameraID: String
    @State private var availableCameras: [(id: String, name: String)]
    @State private var warningMode: WarningMode
    @State private var warningColor: Color
    @State private var warningOnsetDelay: Double
    @State private var launchAtLogin: Bool
    @State private var toggleShortcutEnabled: Bool
    @State private var toggleShortcut: KeyboardShortcut
    @State private var detectionModeSlider: Double
    @State private var trackingSource: TrackingSource
    @State private var trackingModeSelection: TrackingMode
    @State private var preferredSource: TrackingSource
    @State private var airPodsAvailable: Bool
    @State private var airPodsConnected: Bool
    @State private var cameraCalibrated: Bool
    @State private var airPodsCalibrated: Bool
    @State private var activeSource: TrackingSource
    @State private var settingsProfiles: [SettingsProfile]
    @State private var selectedSettingsProfileID: String
    @State private var lastSelectedSettingsProfileID: String
    @State private var isApplyingProfileSelection = false
    @State private var showingNewProfilePrompt = false
    @State private var showingDeleteConfirmation = false
    @State private var newProfileName = ""

    var canDeleteCurrentProfile: Bool {
        settingsProfileManager.canDeleteProfile(id: selectedSettingsProfileID)
    }

    let detectionModes: [DetectionMode] = [.responsive, .balanced, .performance]

    let intensityValues: [Double] = [0.08, 0.15, 0.35, 0.65, 1.2]
    var intensityLabels: [String] { [L("settings.intensity.gentle"), L("settings.intensity.easy"), L("settings.intensity.medium"), L("settings.intensity.firm"), L("settings.intensity.aggressive")] }

    let deadZoneValues: [Double] = [0.0, 0.08, 0.15, 0.25, 0.40]
    var deadZoneLabels: [String] { [L("settings.deadZone.strict"), L("settings.deadZone.tight"), L("settings.deadZone.medium"), L("settings.deadZone.relaxed"), L("settings.deadZone.loose")] }

    init(appDelegate: AppDelegate) {
        self.init(appDelegate: appDelegate, settingsProfileManager: appDelegate.settingsProfileManager)
    }

    init(appDelegate: AppDelegate, settingsProfileManager: SettingsProfileManager) {
        self.appDelegate = appDelegate
        self.settingsProfileManager = settingsProfileManager

        // Initialize all state from appDelegate synchronously to ensure correct sizing
        let cameras = appDelegate.cameraDetector.getAvailableCameras()
        let cameraList = cameras.map { (id: $0.uniqueID, name: $0.localizedName) }

        let profileIntensity = appDelegate.activeIntensity
        let profileDeadZone = appDelegate.activeDeadZone
        let profileWarningMode = appDelegate.activeWarningMode
        let profileWarningColor = appDelegate.activeWarningColor
        let profileWarningOnsetDelay = appDelegate.activeWarningOnsetDelay
        let profileDetectionMode = appDelegate.activeDetectionMode

        _intensity = State(initialValue: profileIntensity)
        _deadZone = State(initialValue: profileDeadZone)
        _intensitySlider = State(initialValue: Double(Self.closestIndex(for: Double(profileIntensity), in: intensityValues)))
        _deadZoneSlider = State(initialValue: Double(Self.closestIndex(for: Double(profileDeadZone), in: deadZoneValues)))
        _blurWhenAway = State(initialValue: appDelegate.blurWhenAway)
        _showInDock = State(initialValue: appDelegate.showInDock)
        _pauseOnTheGo = State(initialValue: appDelegate.pauseOnTheGo)
        _useCompatibilityMode = State(initialValue: appDelegate.useCompatibilityMode)
        _useFullScreenOverlay = State(initialValue: appDelegate.useFullScreenOverlay)
        _selectedCameraID = State(initialValue: appDelegate.selectedCameraID ?? cameras.first?.uniqueID ?? "")
        _availableCameras = State(initialValue: cameraList)
        _warningMode = State(initialValue: profileWarningMode)
        _warningColor = State(initialValue: Color(profileWarningColor))
        _warningOnsetDelay = State(initialValue: profileWarningOnsetDelay)
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        _toggleShortcutEnabled = State(initialValue: appDelegate.toggleShortcutEnabled)
        _toggleShortcut = State(initialValue: appDelegate.toggleShortcut)
        _detectionModeSlider = State(initialValue: Double(detectionModes.firstIndex(of: profileDetectionMode) ?? 0))
        _trackingSource = State(initialValue: appDelegate.trackingSource)
        _trackingModeSelection = State(initialValue: appDelegate.trackingStore.withState { $0.trackingMode })
        _preferredSource = State(initialValue: appDelegate.trackingStore.withState { $0.preferredSource })
        _airPodsAvailable = State(initialValue: appDelegate.airPodsDetector.isAvailable)
        let needsAirPods = appDelegate.trackingStore.withState { $0.trackingMode } == .automatic ||
                           appDelegate.trackingSource == .airpods
        _airPodsConnected = State(initialValue: needsAirPods ? appDelegate.airPodsDetector.isBluetoothConnected : false)
        _cameraCalibrated = State(initialValue: appDelegate.cameraCalibration?.isValid ?? false)
        _airPodsCalibrated = State(initialValue: appDelegate.airPodsCalibration?.isValid ?? false)
        _activeSource = State(initialValue: appDelegate.activeTrackingSource)
        settingsProfileManager.ensureProfilesLoaded()
        let snapshot = settingsProfileManager.profilesState()
        let profiles = snapshot.profiles
        let initialProfileID = snapshot.selectedID ?? profiles.first?.id ?? ""
        _settingsProfiles = State(initialValue: profiles)
        _selectedSettingsProfileID = State(initialValue: initialProfileID)
        _lastSelectedSettingsProfileID = State(initialValue: initialProfileID)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact Header
            HStack(spacing: 8) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 28, height: 28)
                }
                Text("Dorso")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                // Social links
                HStack(spacing: 4) {
                    Link(destination: URL(string: "https://github.com/tldev/dorso")!) {
                        GitHubIcon(color: Color.secondary.opacity(0.6))
                            .frame(width: 14, height: 14)
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .help(L("settings.viewOnGitHub"))

                    Link(destination: URL(string: "https://discord.gg/6Ufy2SnXDW")!) {
                        DiscordIcon(color: Color.secondary.opacity(0.6))
                            .frame(width: 14, height: 14)
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .help(L("settings.joinDiscord"))
                }

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("v\(version)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                }
            }
            .padding(.bottom, 10)

            SubtleDivider()

            // Tracking section (not part of profile)
            VStack(spacing: 6) {
                // Mode row
                HStack(spacing: 8) {
                    Text(L("settings.tracking"))
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 82, alignment: .leading)

                    CompactModePicker(selection: $trackingModeSelection)
                        .frame(width: 150)

                    HelpButton(text: L("settings.tracking.help"))
                        .onChange(of: trackingModeSelection) { newValue in
                            Task { @MainActor in
                                await appDelegate.setTrackingMode(newValue)
                                activeSource = appDelegate.activeTrackingSource
                            }
                        }

                    Spacer()
                }
                .frame(height: 26)

                if trackingModeSelection == .manual {
                    // Manual mode: source picker + device row for selected source
                    HStack(spacing: 8) {
                        Text("")
                            .frame(width: 82)

                        CompactTrackingSourcePicker(
                            selection: $trackingSource,
                            airPodsAvailable: airPodsAvailable
                        )
                        .frame(width: 150)
                        .onChange(of: trackingSource) { newValue in
                            if newValue != appDelegate.trackingSource {
                                Task { @MainActor in
                                    await appDelegate.switchTrackingSource(to: newValue)
                                }
                            }
                        }

                        Spacer()
                    }
                    .frame(height: 26)

                    DeviceStatusRow(
                        source: trackingSource,
                        isCalibrated: trackingSource == .camera ? cameraCalibrated : airPodsCalibrated,
                        isConnected: trackingSource == .camera ? !availableCameras.isEmpty : airPodsConnected,
                        isPreferred: false,
                        isActive: appDelegate.state.isActive,
                        cameraDropdown: trackingSource == .camera && !availableCameras.isEmpty ? AnyView(
                            Picker("", selection: $selectedCameraID) {
                                ForEach(availableCameras, id: \.id) { camera in
                                    Text(camera.name).tag(camera.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 140)
                            .onChange(of: selectedCameraID) { newValue in
                                if newValue != appDelegate.selectedCameraID {
                                    appDelegate.selectedCameraID = newValue
                                    appDelegate.saveSettings()
                                    appDelegate.restartCamera()
                                }
                            }
                        ) : nil,
                        onCalibrate: {
                            appDelegate.startCalibration()
                        }
                    )
                } else {
                    // Automatic mode layout
                    VStack(spacing: 6) {
                        // Preferred source picker
                        HStack(spacing: 8) {
                            Text(L("settings.preferred"))
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 82, alignment: .leading)

                            CompactTrackingSourcePicker(
                                selection: $preferredSource,
                                airPodsAvailable: true
                            )
                            .frame(width: 150)
                            .onChange(of: preferredSource) { newValue in
                                Task { @MainActor in
                                    await appDelegate.setPreferredSource(newValue)
                                    activeSource = appDelegate.activeTrackingSource
                                }
                            }

                            Spacer()
                        }
                        .frame(height: 26)

                        // Device status rows
                        DeviceStatusRow(
                            source: .camera,
                            isCalibrated: cameraCalibrated,
                            isConnected: !availableCameras.isEmpty,
                            isPreferred: preferredSource == .camera,
                            isActive: activeSource == .camera && appDelegate.state.isActive,
                            cameraDropdown: availableCameras.isEmpty ? nil : AnyView(
                                Picker("", selection: $selectedCameraID) {
                                    ForEach(availableCameras, id: \.id) { camera in
                                        Text(camera.name).tag(camera.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 140)
                                .onChange(of: selectedCameraID) { newValue in
                                    if newValue != appDelegate.selectedCameraID {
                                        appDelegate.selectedCameraID = newValue
                                        appDelegate.saveSettings()
                                        appDelegate.restartCamera()
                                    }
                                }
                            ),
                            onCalibrate: {
                                appDelegate.startCalibration(for: .camera)
                            }
                        )

                        DeviceStatusRow(
                            source: .airpods,
                            isCalibrated: airPodsCalibrated,
                            isConnected: airPodsConnected,
                            isPreferred: preferredSource == .airpods,
                            isActive: activeSource == .airpods && appDelegate.state.isActive,
                            onCalibrate: {
                                appDelegate.startCalibration(for: .airpods)
                            }
                        )

                        // Warning banner when preferred device not calibrated
                        if (preferredSource == .camera && !cameraCalibrated)
                            || (preferredSource == .airpods && !airPodsCalibrated)
                        {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                                Text(L("settings.preferredNeedsCalibration"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.orange.opacity(0.08))
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 10)

            // Profile Section Card
            VStack(spacing: 6) {
                // Profile header row - aligned with Warning row below
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Text(L("settings.profile"))
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 82, alignment: .leading)
                        HelpButton(text: L("settings.profile.help"))
                    }

                    HStack(spacing: 4) {
                        Picker("", selection: $selectedSettingsProfileID) {
                            ForEach(settingsProfiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        .padding(.horizontal, -4)
                        .onChange(of: selectedSettingsProfileID) { newValue in
                            handleProfileSelectionChange(newValue)
                        }

                        Button(action: {
                            newProfileName = ""
                            showingNewProfilePrompt = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(L("settings.profile.new"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.onBrandCyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.brandCyan)
                            )
                        }
                        .buttonStyle(.plain)

                        // Delete button - only enabled for non-Default profiles when more than one exists
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(canDeleteCurrentProfile ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(canDeleteCurrentProfile ? Color.red : Color.secondary.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canDeleteCurrentProfile)
                    }

                    Spacer()
                }
                .frame(height: 26)

                // Warning row
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Text(L("settings.warning"))
                            .font(.system(size: 11))
                            .frame(width: 82, alignment: .leading)
                        HelpButton(text: L("settings.warning.help"))
                    }

                    CompactWarningStylePicker(selection: $warningMode)
                        .frame(maxWidth: .infinity)
                        .onChange(of: warningMode) { newValue in
                            settingsProfileManager.updateActiveProfile(warningMode: newValue)
                            appDelegate.switchWarningMode()
                        }

                    InlineColorPicker(color: $warningColor)
                        .onChange(of: warningColor) { newValue in
                            let nsColor = NSColor(newValue)
                            settingsProfileManager.updateActiveProfile(warningColor: nsColor)
                            appDelegate.updateWarningColor(nsColor)
                        }
                }
                .frame(height: 26)

                // Sliders
                CompactSlider(
                    title: L("settings.deadZone"),
                    helpText: L("settings.deadZone.help"),
                    value: $deadZoneSlider,
                    range: 0...4,
                    step: 1,
                    valueLabel: deadZoneLabels[Int(deadZoneSlider)]
                )
                .onChange(of: deadZoneSlider) { newValue in
                    let index = Int(newValue)
                    deadZone = deadZoneValues[index]
                    settingsProfileManager.updateActiveProfile(deadZone: deadZone)
                    appDelegate.applyActiveSettingsProfile()
                }

                CompactSlider(
                    title: L("settings.intensity"),
                    helpText: L("settings.intensity.help"),
                    value: $intensitySlider,
                    range: 0...4,
                    step: 1,
                    valueLabel: intensityLabels[Int(intensitySlider)]
                )
                .onChange(of: intensitySlider) { newValue in
                    let index = Int(newValue)
                    intensity = intensityValues[index]
                    settingsProfileManager.updateActiveProfile(intensity: intensity)
                    appDelegate.applyActiveSettingsProfile()
                }

                CompactSlider(
                    title: L("settings.delay"),
                    helpText: L("settings.delay.help"),
                    value: $warningOnsetDelay,
                    range: 0...30,
                    step: 1,
                    valueLabel: "\(Int(warningOnsetDelay))s"
                )
                .onChange(of: warningOnsetDelay) { newValue in
                    settingsProfileManager.updateActiveProfile(warningOnsetDelay: newValue)
                    appDelegate.applyActiveSettingsProfile()
                }

                CompactSlider(
                    title: L("settings.detection"),
                    helpText: L("settings.detection.help"),
                    value: $detectionModeSlider,
                    range: 0...2,
                    step: 1,
                    valueLabel: detectionModes[Int(detectionModeSlider)].displayName
                )
                .onChange(of: detectionModeSlider) { newValue in
                    let index = Int(newValue)
                    settingsProfileManager.updateActiveProfile(detectionMode: detectionModes[index])
                    appDelegate.applyActiveSettingsProfile()
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            SubtleDivider()
                .padding(.top, 6)

            // Behavior Section - 2 column grid with fixed widths
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    CompactToggle(
                        title: L("settings.launchAtLogin"),
                        helpText: L("settings.launchAtLogin.help"),
                        isOn: $launchAtLogin
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                    CompactToggle(
                        title: L("settings.showInDock"),
                        helpText: L("settings.showInDock.help"),
                        isOn: $showInDock
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: showInDock) { newValue in
                        appDelegate.showInDock = newValue
                        appDelegate.saveSettings()
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        DispatchQueue.main.async {
                            appDelegate.settingsWindowController.window?.makeKeyAndOrderFront(nil)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }

                HStack(spacing: 0) {
                    CompactToggle(
                        title: L("settings.blurWhenAway"),
                        helpText: trackingSource == .airpods
                            ? L("settings.blurWhenAway.help.airpods")
                            : L("settings.blurWhenAway.help.camera"),
                        isOn: $blurWhenAway,
                        isDisabled: trackingSource == .airpods
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: blurWhenAway) { newValue in
                        appDelegate.blurWhenAway = newValue
                        appDelegate.saveSettings()
                    }

                    CompactToggle(
                        title: L("settings.pauseOnTheGo"),
                        helpText: L("settings.pauseOnTheGo.help"),
                        isOn: $pauseOnTheGo
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: pauseOnTheGo) { newValue in
                        Task { @MainActor in
                            await appDelegate.setPauseOnTheGoEnabled(newValue)
                        }
                    }
                }

                HStack(spacing: 0) {
                    CompactToggle(
                        title: L("settings.fullScreenOverlay"),
                        helpText: L("settings.fullScreenOverlay.help"),
                        isOn: $useFullScreenOverlay
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: useFullScreenOverlay) { newValue in
                        appDelegate.useFullScreenOverlay = newValue
                        appDelegate.saveSettings()
                        appDelegate.rebuildOverlayWindows()
                    }

                    Spacer()
                        .frame(maxWidth: .infinity)
                }

                // Shortcut row
                HStack(spacing: 0) {
                    CompactShortcutRecorder(
                        shortcut: $toggleShortcut,
                        isEnabled: $toggleShortcutEnabled,
                        onShortcutChange: {
                            appDelegate.toggleShortcutEnabled = toggleShortcutEnabled
                            appDelegate.toggleShortcut = toggleShortcut
                            appDelegate.saveSettings()
                            appDelegate.updateGlobalKeyMonitor()
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    #if !APP_STORE
                    CompactToggle(
                        title: L("settings.compatibilityMode"),
                        helpText: L("settings.compatibilityMode.help"),
                        isOn: $useCompatibilityMode
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: useCompatibilityMode) { newValue in
                        appDelegate.useCompatibilityMode = newValue
                        appDelegate.saveSettings()
                        appDelegate.currentBlurRadius = 0
                        for blurView in appDelegate.blurViews {
                            blurView.alphaValue = 0
                        }
                    }
                    #else
                    Spacer()
                        .frame(maxWidth: .infinity)
                    #endif
                }
            }
            .padding(.vertical, 10)
        }
        .padding(16)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .alert(L("settings.profile.newTitle"), isPresented: $showingNewProfilePrompt) {
            TextField(L("settings.profile.namePlaceholder"), text: $newProfileName)
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("settings.profile.create")) {
                let trimmedName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                let profileName = trimmedName.isEmpty ? nextDefaultProfileName() : trimmedName
                let profile = settingsProfileManager.createProfile(
                    named: profileName,
                    warningMode: appDelegate.activeWarningMode,
                    warningColor: appDelegate.activeWarningColor,
                    deadZone: appDelegate.activeDeadZone,
                    intensity: appDelegate.activeIntensity,
                    warningOnsetDelay: appDelegate.activeWarningOnsetDelay,
                    detectionMode: appDelegate.activeDetectionMode
                )
                settingsProfiles = settingsProfileManager.settingsProfiles
                selectedSettingsProfileID = profile.id
                lastSelectedSettingsProfileID = profile.id
                syncProfileSettings()
            }
        } message: {
            Text(L("settings.profile.namePrompt"))
        }
        .alert(L("settings.profile.deleteTitle"), isPresented: $showingDeleteConfirmation) {
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("settings.profile.delete"), role: .destructive) {
                if settingsProfileManager.deleteProfile(id: selectedSettingsProfileID) {
                    settingsProfiles = settingsProfileManager.settingsProfiles
                    if let newID = settingsProfileManager.currentSettingsProfileID {
                        selectedSettingsProfileID = newID
                        lastSelectedSettingsProfileID = newID
                    }
                    appDelegate.applyActiveSettingsProfile()
                    syncProfileSettings()
                }
            }
        } message: {
            Text(L("settings.profile.deleteMessage"))
        }
        .onAppear {
            appDelegate.onCalibrationComplete = {
                cameraCalibrated = appDelegate.cameraCalibration?.isValid ?? false
                airPodsCalibrated = appDelegate.airPodsCalibration?.isValid ?? false
                airPodsConnected = appDelegate.airPodsDetector.isBluetoothConnected
                activeSource = appDelegate.activeTrackingSource
            }
            appDelegate.onActiveSourceChanged = {
                activeSource = appDelegate.activeTrackingSource
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if trackingModeSelection == .automatic || trackingSource == .airpods {
                airPodsConnected = appDelegate.airPodsDetector.isBluetoothConnected
            }
        }
        // Cleanup happens in SettingsWindowController.windowWillClose
        // (not onDisappear, which fires when calibration window covers this view)
    }

    private func syncProfileSettings() {
        intensity = appDelegate.activeIntensity
        deadZone = appDelegate.activeDeadZone
        intensitySlider = Double(Self.closestIndex(for: Double(appDelegate.activeIntensity), in: intensityValues))
        deadZoneSlider = Double(Self.closestIndex(for: Double(appDelegate.activeDeadZone), in: deadZoneValues))
        warningMode = appDelegate.activeWarningMode
        warningColor = Color(appDelegate.activeWarningColor)
        warningOnsetDelay = appDelegate.activeWarningOnsetDelay
        detectionModeSlider = Double(detectionModes.firstIndex(of: appDelegate.activeDetectionMode) ?? 0)
    }

    private static func closestIndex(for value: Double, in values: [Double]) -> Int {
        values.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset ?? 0
    }

    private func handleProfileSelectionChange(_ newValue: String) {
        guard !isApplyingProfileSelection else { return }
        guard newValue != lastSelectedSettingsProfileID else { return }
        isApplyingProfileSelection = true
        defer { isApplyingProfileSelection = false }
        let previousSelection = lastSelectedSettingsProfileID
        if let profile = settingsProfileManager.selectProfile(id: newValue) {
            appDelegate.applyActiveSettingsProfile()
            settingsProfiles = settingsProfileManager.settingsProfiles
            selectedSettingsProfileID = profile.id
            lastSelectedSettingsProfileID = profile.id
        } else {
            selectedSettingsProfileID = previousSelection
        }
        syncProfileSettings()
    }

    private func nextDefaultProfileName() -> String {
        let existingNames = Set(settingsProfiles.map { $0.name })
        var index = 1
        while existingNames.contains("Profile \(index)") {
            index += 1
        }
        return "Profile \(index)"
    }
}

