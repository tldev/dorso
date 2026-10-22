import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Settings View

@MainActor
struct SettingsView: View {
    let appDelegate: AppDelegate
    let settingsProfileManager: SettingsProfileManager

    // Local state that syncs with AppDelegate - initialized from appDelegate in init()
    @State var intensity: Double
    @State var deadZone: Double
    @State var intensitySlider: Double
    @State var deadZoneSlider: Double
    @State var blurWhenAway: Bool
    @State var showInDock: Bool
    @State var pauseOnTheGo: Bool
    @State var pauseOnBattery: Bool
    @State var useCompatibilityMode: Bool
    @State var useFullScreenOverlay: Bool
    @State var selectedCameraID: String
    @State var availableCameras: [(id: String, name: String)]
    @State var warningMode: WarningMode
    @State var warningColor: Color
    @State var warningOnsetDelay: Double
    @State var launchAtLogin: Bool
    @State var appAppearance: AppAppearance
    #if !APP_STORE
        @State var autoCheckForUpdates: Bool
    #endif
    @State var toggleShortcutEnabled: Bool
    @State var toggleShortcut: KeyboardShortcut
    @State var detectionModeSlider: Double
    @State var trackingSource: TrackingSource
    @State var trackingModeSelection: TrackingMode
    @State var preferredSource: TrackingSource
    @State var airPodsAvailable: Bool
    @State var airPodsConnected: Bool
    @State var cameraCalibrated: Bool
    @State var airPodsCalibrated: Bool
    @State var activeSource: TrackingSource
    @State var settingsProfiles: [SettingsProfile]
    @State var selectedSettingsProfileID: String
    @State var lastSelectedSettingsProfileID: String
    @State var isApplyingProfileSelection = false
    @State var showingNewProfilePrompt = false
    @State var showingDeleteConfirmation = false
    @State var newProfileName = ""
    @State var showingRenameProfilePrompt = false
    @State var renameProfileName = ""
    @State var desks: [Desk]
    @State var activeDeskID: String
    @State var showingRenameDeskPrompt = false
    @State var renameDeskName = ""
    @State var showingDeleteDeskConfirmation = false

    var canDeleteCurrentProfile: Bool {
        settingsProfileManager.canDeleteProfile(id: selectedSettingsProfileID)
    }

    var canRenameCurrentProfile: Bool {
        settingsProfileManager.canRenameProfile(id: selectedSettingsProfileID)
    }

    let detectionModes: [DetectionMode] = [.responsive, .balanced, .performance]

    let intensityValues: [Double] = [0.08, 0.15, 0.35, 0.65, 1.2]
    var intensityLabels: [String] {
        [
            L("settings.intensity.gentle"), L("settings.intensity.easy"), L("settings.intensity.medium"),
            L("settings.intensity.firm"), L("settings.intensity.aggressive"),
        ]
    }

    let deadZoneValues: [Double] = [0.0, 0.08, 0.15, 0.25, 0.40]
    var deadZoneLabels: [String] {
        [
            L("settings.deadZone.strict"), L("settings.deadZone.tight"), L("settings.deadZone.medium"),
            L("settings.deadZone.relaxed"), L("settings.deadZone.loose"),
        ]
    }

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
        _intensitySlider = State(
            initialValue: Double(Self.closestIndex(for: Double(profileIntensity), in: intensityValues)))
        _deadZoneSlider = State(
            initialValue: Double(Self.closestIndex(for: Double(profileDeadZone), in: deadZoneValues)))
        _blurWhenAway = State(initialValue: appDelegate.blurWhenAway)
        _showInDock = State(initialValue: appDelegate.showInDock)
        _pauseOnTheGo = State(initialValue: appDelegate.pauseOnTheGo)
        _pauseOnBattery = State(initialValue: appDelegate.pauseOnBattery)
        _useCompatibilityMode = State(initialValue: appDelegate.useCompatibilityMode)
        _useFullScreenOverlay = State(initialValue: appDelegate.useFullScreenOverlay)
        _selectedCameraID = State(initialValue: appDelegate.selectedCameraID ?? cameras.first?.uniqueID ?? "")
        _availableCameras = State(initialValue: cameraList)
        _warningMode = State(initialValue: profileWarningMode)
        _warningColor = State(initialValue: Color(profileWarningColor))
        _warningOnsetDelay = State(initialValue: profileWarningOnsetDelay)
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        _appAppearance = State(initialValue: appDelegate.appAppearance)
        #if !APP_STORE
            _autoCheckForUpdates = State(
                initialValue: appDelegate.updaterManager?.automaticallyChecksForUpdates ?? false)
        #endif
        _toggleShortcutEnabled = State(initialValue: appDelegate.toggleShortcutEnabled)
        _toggleShortcut = State(initialValue: appDelegate.toggleShortcut)
        _detectionModeSlider = State(initialValue: Double(detectionModes.firstIndex(of: profileDetectionMode) ?? 0))
        _trackingSource = State(initialValue: appDelegate.trackingSource)
        _trackingModeSelection = State(initialValue: appDelegate.trackingStore.withState { $0.trackingMode })
        _preferredSource = State(initialValue: appDelegate.trackingStore.withState { $0.preferredSource })
        _airPodsAvailable = State(initialValue: appDelegate.airPodsDetector.isAvailable)
        let needsAirPods =
            appDelegate.trackingStore.withState { $0.trackingMode } == .automatic
            || appDelegate.trackingSource == .airpods
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
        let deskKey = DisplayMonitor.getCurrentConfigKey()
        _desks = State(initialValue: appDelegate.deskStore.desks(forKey: deskKey))
        _activeDeskID = State(initialValue: appDelegate.deskStore.activeDesk(forKey: deskKey)?.id ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 10) {
                trackingCard
                responseCard
                behaviorCard
            }
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
                // Profiles are loaded in init, so there is always an active one
                guard let source = settingsProfileManager.activeProfile else { return }
                let profile = settingsProfileManager.createProfile(named: profileName, copying: source)
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
        .alert(L("settings.profile.renameTitle"), isPresented: $showingRenameProfilePrompt) {
            TextField(L("settings.profile.namePlaceholder"), text: $renameProfileName)
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("common.rename")) {
                if settingsProfileManager.renameProfile(id: selectedSettingsProfileID, to: renameProfileName) {
                    settingsProfiles = settingsProfileManager.settingsProfiles
                }
            }
        }
        .alert(L("desk.renameTitle"), isPresented: $showingRenameDeskPrompt) {
            TextField(L("desk.namePlaceholder"), text: $renameDeskName)
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("common.rename")) {
                appDelegate.deskStore.renameDesk(
                    id: activeDeskID, to: renameDeskName, forKey: DisplayMonitor.getCurrentConfigKey())
                reloadDesks()
            }
        }
        .alert(L("desk.deleteTitle"), isPresented: $showingDeleteDeskConfirmation) {
            Button(L("common.cancel"), role: .cancel) {}
            Button(L("settings.profile.delete"), role: .destructive) {
                let deskID = activeDeskID
                Task { @MainActor in
                    await appDelegate.deleteDesk(id: deskID)
                    reloadDesks()
                }
            }
        } message: {
            Text(L("desk.deleteMessage"))
        }
        .onAppear {
            // The window is reused
            reloadDesks()
            appDelegate.onCalibrationComplete = {
                reloadDesks()
                cameraCalibrated = appDelegate.cameraCalibration?.isValid ?? false
                airPodsCalibrated = appDelegate.airPodsCalibration?.isValid ?? false
                airPodsConnected = appDelegate.airPodsDetector.isBluetoothConnected
                activeSource = appDelegate.activeTrackingSource
            }
            appDelegate.onActiveSourceChanged = {
                activeSource = appDelegate.activeTrackingSource
            }
            appDelegate.onDesksChanged = {
                reloadDesks()
                cameraCalibrated = appDelegate.cameraCalibration?.isValid ?? false
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

    static func closestIndex(for value: Double, in values: [Double]) -> Int {
        values.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset ?? 0
    }
}
