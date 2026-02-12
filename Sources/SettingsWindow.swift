import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Brand Colors

extension Color {
    static let brandCyan = Color(red: 0.31, green: 0.82, blue: 0.77)      // #4fd1c5
    static let brandNavy = Color(red: 0.10, green: 0.15, blue: 0.27)      // #1a2744
    static let sectionBackground = Color(NSColor.controlBackgroundColor).opacity(0.5)

    // Dynamic color for text on brandCyan backgrounds - adapts to light/dark mode
    static let onBrandCyan = Color(NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.10, green: 0.15, blue: 0.27, alpha: 1.0)  // brandNavy in dark
            : NSColor.white                                             // white in light
    })
}

// MARK: - Compact Slider

struct CompactSlider: View {
    let title: String
    let helpText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueLabel: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 11))
                    .frame(width: 82, alignment: .leading)
                HelpButton(text: helpText)
            }

            Slider(value: $value, in: range, step: step)
                .tint(.brandCyan)
                .frame(maxWidth: .infinity)

            Text(valueLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.brandCyan)
                .frame(width: 70, alignment: .trailing)
        }
        .frame(height: 22)
    }
}

// MARK: - Compact Toggle

struct CompactToggle: View {
    let title: String
    let helpText: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(.brandCyan)
                .labelsHidden()
                .scaleEffect(0.65)
                .frame(width: 32)
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.5 : 1.0)

            Text(title)
                .font(.system(size: 11))
                .lineLimit(1)
                .opacity(isDisabled ? 0.5 : 1.0)

            HelpButton(text: helpText)

            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisabled { isOn.toggle() }
        }
    }
}

// MARK: - Compact Warning Style Picker

struct CompactWarningStylePicker: View {
    @Binding var selection: WarningMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach([WarningMode.blur, .glow, .border, .solid, .none], id: \.self) { mode in
                Button(action: { selection = mode }) {
                    Text(mode.shortName)
                        .font(.system(size: 10, weight: selection == mode ? .semibold : .regular))
                        .foregroundColor(selection == mode ? .onBrandCyan : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(selection == mode ? Color.brandCyan : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Inline Color Picker

struct InlineColorPicker: View {
    @Binding var color: Color
    @State private var showPopover = false
    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1
    @State private var hexText: String = ""

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                // Color wheel
                ColorWheelView(hue: $hue, saturation: $saturation)
                    .frame(width: 180, height: 180)
                    .onChange(of: hue) { _ in updateColorFromHSB() }
                    .onChange(of: saturation) { _ in updateColorFromHSB() }

                // Brightness slider
                HStack(spacing: 8) {
                    Image(systemName: "sun.min")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    BrightnessSliderView(brightness: $brightness, hue: hue, saturation: saturation)
                        .frame(height: 16)
                        .onChange(of: brightness) { _ in updateColorFromHSB() }

                    Image(systemName: "sun.max")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Hex input
                HStack(spacing: 6) {
                    Text("#")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextField("", text: $hexText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .textFieldStyle(.plain)
                        .frame(width: 70)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .onSubmit { updateColorFromHex() }

                    // Color preview
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 32, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                }
            }
            .padding(16)
            .frame(width: 212)
            .onAppear { syncFromColor() }
        }
        .onAppear { syncFromColor() }
    }

    private func syncFromColor() {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        hue = Double(nsColor.hueComponent)
        saturation = Double(nsColor.saturationComponent)
        brightness = Double(nsColor.brightnessComponent)
        updateHexText()
    }

    private func updateColorFromHSB() {
        color = Color(hue: hue, saturation: saturation, brightness: brightness)
        updateHexText()
    }

    private func updateHexText() {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        hexText = String(format: "%02X%02X%02X", r, g, b)
    }

    private func updateColorFromHex() {
        let hex = hexText.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0

        color = Color(red: r, green: g, blue: b)
        syncFromColor()
    }
}

struct ColorWheelView: View {
    @Binding var hue: Double
    @Binding var saturation: Double

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2

            ZStack {
                // Color wheel background
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(hue: 0.0, saturation: 1, brightness: 1),
                                Color(hue: 0.1, saturation: 1, brightness: 1),
                                Color(hue: 0.2, saturation: 1, brightness: 1),
                                Color(hue: 0.3, saturation: 1, brightness: 1),
                                Color(hue: 0.4, saturation: 1, brightness: 1),
                                Color(hue: 0.5, saturation: 1, brightness: 1),
                                Color(hue: 0.6, saturation: 1, brightness: 1),
                                Color(hue: 0.7, saturation: 1, brightness: 1),
                                Color(hue: 0.8, saturation: 1, brightness: 1),
                                Color(hue: 0.9, saturation: 1, brightness: 1),
                                Color(hue: 1.0, saturation: 1, brightness: 1),
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: size, height: size)

                // White to transparent radial gradient for saturation
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [.white, .white.opacity(0)]),
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                    .frame(width: size, height: size)

                // Selection indicator
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color(hue: hue, saturation: saturation, brightness: 1)))
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .position(
                        x: center.x + cos(hue * 2 * .pi) * (radius - 10) * saturation,
                        y: center.y + sin(hue * 2 * .pi) * (radius - 10) * saturation
                    )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y

                        // Calculate hue from angle (atan2 gives angle from positive x-axis)
                        var angle = atan2(dy, dx)
                        if angle < 0 { angle += 2 * .pi }
                        hue = angle / (2 * .pi)

                        // Calculate saturation from distance
                        let distance = sqrt(dx * dx + dy * dy)
                        saturation = min(1, max(0, distance / (radius - 10)))
                    }
            )
        }
    }
}

struct BrightnessSliderView: View {
    @Binding var brightness: Double
    let hue: Double
    let saturation: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Gradient track
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .black,
                                Color(hue: hue, saturation: saturation, brightness: 1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 12)

                // Thumb
                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .position(
                        x: 8 + (geometry.size.width - 16) * brightness,
                        y: geometry.size.height / 2
                    )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newValue = (value.location.x - 8) / (geometry.size.width - 16)
                        brightness = min(1, max(0, newValue))
                    }
            )
        }
    }
}

// MARK: - Compact Tracking Source Picker

struct CompactTrackingSourcePicker: View {
    @Binding var selection: TrackingSource
    let airPodsAvailable: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TrackingSource.allCases) { source in
                let isDisabled = source == .airpods && !airPodsAvailable
                Button(action: {
                    if !isDisabled { selection = source }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: source.icon)
                            .font(.system(size: 9))
                        Text(source.displayName)
                            .font(.system(size: 10, weight: selection == source ? .semibold : .regular))
                    }
                    .foregroundColor(selection == source ? .onBrandCyan : (isDisabled ? .secondary.opacity(0.5) : .primary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(selection == source ? Color.brandCyan : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Subtle Divider

struct SubtleDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

extension WarningMode {
    var displayName: String {
        switch self {
        case .blur: return L("warningMode.blur")
        case .glow: return L("warningMode.glow")
        case .border: return L("warningMode.border")
        case .solid: return L("warningMode.solid")
        case .none: return L("warningMode.none")
        }
    }

    var shortName: String { displayName }
}

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
    @State private var airPodsAvailable: Bool
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
        _airPodsAvailable = State(initialValue: appDelegate.airPodsDetector.isAvailable)
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
                Text("Posturr")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                // Social links
                HStack(spacing: 4) {
                    Link(destination: URL(string: "https://github.com/tldev/posturr")!) {
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

            // Tracking row (not part of profile)
            HStack(spacing: 8) {
                Text(L("settings.tracking"))
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 82, alignment: .leading)

                CompactTrackingSourcePicker(
                    selection: $trackingSource,
                    airPodsAvailable: airPodsAvailable
                )
                .frame(width: 130)
                .onChange(of: trackingSource) { newValue in
                    if newValue != appDelegate.trackingSource {
                        appDelegate.switchTrackingSource(to: newValue)
                    }
                }

                if trackingSource == .camera {
                    if availableCameras.isEmpty {
                        Text(L("settings.noCameras"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Picker("", selection: $selectedCameraID) {
                            ForEach(availableCameras, id: \.id) { camera in
                                Text(camera.name).tag(camera.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .onChange(of: selectedCameraID) { newValue in
                            if newValue != appDelegate.selectedCameraID {
                                appDelegate.selectedCameraID = newValue
                                appDelegate.saveSettings()
                                appDelegate.restartCamera()
                            }
                        }
                    }
                } else {
                    // AirPods status
                    HStack(spacing: 4) {
                        Image(systemName: airPodsAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundColor(airPodsAvailable ? .green : .secondary)
                            .font(.system(size: 10))
                        Text(airPodsAvailable ? L("settings.connected") : L("settings.notConnected"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // Recalibrate button
                Button(action: { appDelegate.startCalibration() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L("settings.recalibrate"))
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
            }
            .frame(height: 26)
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
                            appDelegate.switchWarningMode(to: newValue)
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
                        appDelegate.pauseOnTheGo = newValue
                        appDelegate.saveSettings()
                        if !newValue && appDelegate.state == .paused(.onTheGo) {
                            appDelegate.state = .monitoring
                        }
                    }
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

// MARK: - Social Icons (Official SVG paths from Simple Icons)

struct GitHubIcon: View {
    var color: Color = .secondary

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let scale = min(geometry.size.width, geometry.size.height) / 24

                // Official GitHub Octocat path
                path.move(to: CGPoint(x: 12 * scale, y: 0.297 * scale))
                path.addCurve(to: CGPoint(x: 0 * scale, y: 12.297 * scale),
                              control1: CGPoint(x: 5.37 * scale, y: 0.297 * scale),
                              control2: CGPoint(x: 0 * scale, y: 5.67 * scale))
                path.addCurve(to: CGPoint(x: 8.205 * scale, y: 23.682 * scale),
                              control1: CGPoint(x: 0 * scale, y: 17.6 * scale),
                              control2: CGPoint(x: 3.438 * scale, y: 22.097 * scale))
                path.addCurve(to: CGPoint(x: 9.025 * scale, y: 23.105 * scale),
                              control1: CGPoint(x: 8.805 * scale, y: 23.795 * scale),
                              control2: CGPoint(x: 9.025 * scale, y: 23.424 * scale))
                path.addCurve(to: CGPoint(x: 9.01 * scale, y: 21.065 * scale),
                              control1: CGPoint(x: 9.025 * scale, y: 22.82 * scale),
                              control2: CGPoint(x: 9.01 * scale, y: 22.145 * scale))
                path.addCurve(to: CGPoint(x: 4.968 * scale, y: 19.455 * scale),
                              control1: CGPoint(x: 5.672 * scale, y: 21.789 * scale),
                              control2: CGPoint(x: 4.968 * scale, y: 19.455 * scale))
                path.addCurve(to: CGPoint(x: 3.633 * scale, y: 17.7 * scale),
                              control1: CGPoint(x: 4.422 * scale, y: 18.07 * scale),
                              control2: CGPoint(x: 3.633 * scale, y: 17.7 * scale))
                path.addCurve(to: CGPoint(x: 3.717 * scale, y: 16.971 * scale),
                              control1: CGPoint(x: 2.546 * scale, y: 16.956 * scale),
                              control2: CGPoint(x: 3.717 * scale, y: 16.971 * scale))
                path.addCurve(to: CGPoint(x: 5.555 * scale, y: 18.207 * scale),
                              control1: CGPoint(x: 4.922 * scale, y: 17.055 * scale),
                              control2: CGPoint(x: 5.555 * scale, y: 18.207 * scale))
                path.addCurve(to: CGPoint(x: 9.05 * scale, y: 19.205 * scale),
                              control1: CGPoint(x: 6.625 * scale, y: 20.042 * scale),
                              control2: CGPoint(x: 8.364 * scale, y: 19.512 * scale))
                path.addCurve(to: CGPoint(x: 9.81 * scale, y: 17.6 * scale),
                              control1: CGPoint(x: 9.158 * scale, y: 18.429 * scale),
                              control2: CGPoint(x: 9.467 * scale, y: 17.9 * scale))
                path.addCurve(to: CGPoint(x: 4.344 * scale, y: 11.67 * scale),
                              control1: CGPoint(x: 7.145 * scale, y: 17.3 * scale),
                              control2: CGPoint(x: 4.344 * scale, y: 16.332 * scale))
                path.addCurve(to: CGPoint(x: 5.579 * scale, y: 8.45 * scale),
                              control1: CGPoint(x: 4.344 * scale, y: 10.36 * scale),
                              control2: CGPoint(x: 4.809 * scale, y: 9.14 * scale))
                path.addCurve(to: CGPoint(x: 5.684 * scale, y: 5.274 * scale),
                              control1: CGPoint(x: 5.444 * scale, y: 8.147 * scale),
                              control2: CGPoint(x: 5.039 * scale, y: 6.797 * scale))
                path.addCurve(to: CGPoint(x: 8.984 * scale, y: 6.504 * scale),
                              control1: CGPoint(x: 5.684 * scale, y: 5.274 * scale),
                              control2: CGPoint(x: 6.689 * scale, y: 4.952 * scale))
                path.addCurve(to: CGPoint(x: 12 * scale, y: 6.099 * scale),
                              control1: CGPoint(x: 9.944 * scale, y: 6.237 * scale),
                              control2: CGPoint(x: 10.964 * scale, y: 6.093 * scale))
                path.addCurve(to: CGPoint(x: 15 * scale, y: 6.504 * scale),
                              control1: CGPoint(x: 13.02 * scale, y: 6.105 * scale),
                              control2: CGPoint(x: 14.04 * scale, y: 6.237 * scale))
                path.addCurve(to: CGPoint(x: 18.285 * scale, y: 5.274 * scale),
                              control1: CGPoint(x: 17.28 * scale, y: 4.952 * scale),
                              control2: CGPoint(x: 18.285 * scale, y: 5.274 * scale))
                path.addCurve(to: CGPoint(x: 18.405 * scale, y: 8.45 * scale),
                              control1: CGPoint(x: 18.93 * scale, y: 6.927 * scale),
                              control2: CGPoint(x: 18.645 * scale, y: 8.147 * scale))
                path.addCurve(to: CGPoint(x: 19.635 * scale, y: 11.67 * scale),
                              control1: CGPoint(x: 19.17 * scale, y: 9.29 * scale),
                              control2: CGPoint(x: 19.635 * scale, y: 10.36 * scale))
                path.addCurve(to: CGPoint(x: 14.16 * scale, y: 17.59 * scale),
                              control1: CGPoint(x: 19.635 * scale, y: 16.28 * scale),
                              control2: CGPoint(x: 16.83 * scale, y: 17.29 * scale))
                path.addCurve(to: CGPoint(x: 14.97 * scale, y: 19.81 * scale),
                              control1: CGPoint(x: 14.58 * scale, y: 17.95 * scale),
                              control2: CGPoint(x: 14.97 * scale, y: 18.706 * scale))
                path.addCurve(to: CGPoint(x: 14.955 * scale, y: 23.096 * scale),
                              control1: CGPoint(x: 14.97 * scale, y: 21.416 * scale),
                              control2: CGPoint(x: 14.955 * scale, y: 23.096 * scale))
                path.addCurve(to: CGPoint(x: 15.78 * scale, y: 23.67 * scale),
                              control1: CGPoint(x: 14.955 * scale, y: 23.406 * scale),
                              control2: CGPoint(x: 15.165 * scale, y: 23.783 * scale))
                path.addCurve(to: CGPoint(x: 24 * scale, y: 12.297 * scale),
                              control1: CGPoint(x: 20.565 * scale, y: 22.092 * scale),
                              control2: CGPoint(x: 24 * scale, y: 17.592 * scale))
                path.addCurve(to: CGPoint(x: 12 * scale, y: 0.297 * scale),
                              control1: CGPoint(x: 24 * scale, y: 5.67 * scale),
                              control2: CGPoint(x: 18.63 * scale, y: 0.297 * scale))
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}

struct DiscordIcon: View {
    var color: Color = .secondary

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let scale = min(geometry.size.width, geometry.size.height) / 24

                // Official Discord path
                path.move(to: CGPoint(x: 20.317 * scale, y: 4.3698 * scale))
                path.addCurve(to: CGPoint(x: 15.432 * scale, y: 2.8546 * scale),
                              control1: CGPoint(x: 18.7873 * scale, y: 3.6588 * scale),
                              control2: CGPoint(x: 17.1461 * scale, y: 3.1346 * scale))
                path.addCurve(to: CGPoint(x: 14.8237 * scale, y: 4.1041 * scale),
                              control1: CGPoint(x: 15.3535 * scale, y: 2.8917 * scale),
                              control2: CGPoint(x: 15.0347 * scale, y: 3.4793 * scale))
                path.addCurve(to: CGPoint(x: 9.3369 * scale, y: 4.1041 * scale),
                              control1: CGPoint(x: 12.979 * scale, y: 3.8279 * scale),
                              control2: CGPoint(x: 11.1437 * scale, y: 3.8279 * scale))
                path.addCurve(to: CGPoint(x: 8.7192 * scale, y: 2.8546 * scale),
                              control1: CGPoint(x: 9.1269 * scale, y: 3.4793 * scale),
                              control2: CGPoint(x: 8.7963 * scale, y: 2.8917 * scale))
                path.addCurve(to: CGPoint(x: 3.8341 * scale, y: 4.3698 * scale),
                              control1: CGPoint(x: 7.0042 * scale, y: 3.1346 * scale),
                              control2: CGPoint(x: 5.3643 * scale, y: 3.6588 * scale))
                path.addCurve(to: CGPoint(x: 0.5524 * scale, y: 18.0578 * scale),
                              control1: CGPoint(x: 0.5524 * scale, y: 9.0458 * scale),
                              control2: CGPoint(x: -0.3811 * scale, y: 13.5799 * scale))
                path.addCurve(to: CGPoint(x: 6.6052 * scale, y: 21.0872 * scale),
                              control1: CGPoint(x: 2.6052 * scale, y: 19.5654 * scale),
                              control2: CGPoint(x: 4.5939 * scale, y: 20.51 * scale))
                path.addCurve(to: CGPoint(x: 7.8312 * scale, y: 19.093 * scale),
                              control1: CGPoint(x: 7.0668 * scale, y: 20.4568 * scale),
                              control2: CGPoint(x: 7.4862 * scale, y: 19.7878 * scale))
                path.addCurve(to: CGPoint(x: 5.959 * scale, y: 18.2007 * scale),
                              control1: CGPoint(x: 7.179 * scale, y: 18.8454 * scale),
                              control2: CGPoint(x: 6.5569 * scale, y: 18.5483 * scale))
                path.addCurve(to: CGPoint(x: 6.3308 * scale, y: 17.9093 * scale),
                              control1: CGPoint(x: 6.0848 * scale, y: 18.1064 * scale),
                              control2: CGPoint(x: 6.2108 * scale, y: 18.008 * scale))
                path.addCurve(to: CGPoint(x: 12 * scale, y: 19.7026 * scale),
                              control1: CGPoint(x: 8.2586 * scale, y: 19.7026 * scale),
                              control2: CGPoint(x: 10.1508 * scale, y: 19.7026 * scale))
                path.addCurve(to: CGPoint(x: 17.6692 * scale, y: 17.9093 * scale),
                              control1: CGPoint(x: 13.8492 * scale, y: 19.7026 * scale),
                              control2: CGPoint(x: 15.7414 * scale, y: 19.7026 * scale))
                path.addCurve(to: CGPoint(x: 18.041 * scale, y: 18.2007 * scale),
                              control1: CGPoint(x: 17.7892 * scale, y: 18.008 * scale),
                              control2: CGPoint(x: 17.9152 * scale, y: 18.1064 * scale))
                path.addCurve(to: CGPoint(x: 16.1688 * scale, y: 19.093 * scale),
                              control1: CGPoint(x: 17.4431 * scale, y: 18.5483 * scale),
                              control2: CGPoint(x: 16.821 * scale, y: 18.8454 * scale))
                path.addCurve(to: CGPoint(x: 17.3948 * scale, y: 21.0872 * scale),
                              control1: CGPoint(x: 16.5138 * scale, y: 19.7878 * scale),
                              control2: CGPoint(x: 16.9332 * scale, y: 20.4568 * scale))
                path.addCurve(to: CGPoint(x: 23.4476 * scale, y: 18.0578 * scale),
                              control1: CGPoint(x: 19.4061 * scale, y: 20.51 * scale),
                              control2: CGPoint(x: 21.3948 * scale, y: 19.5654 * scale))
                path.addCurve(to: CGPoint(x: 20.317 * scale, y: 4.3698 * scale),
                              control1: CGPoint(x: 24.3811 * scale, y: 13.5799 * scale),
                              control2: CGPoint(x: 23.4476 * scale, y: 9.0458 * scale))
                path.closeSubpath()

                // Left eye
                path.addEllipse(in: CGRect(x: 5.8631 * scale, y: 10.9122 * scale, width: 4.314 * scale, height: 4.838 * scale))

                // Right eye
                path.addEllipse(in: CGRect(x: 13.8369 * scale, y: 10.9122 * scale, width: 4.314 * scale, height: 4.838 * scale))
            }
            .fill(color, style: FillStyle(eoFill: true))
        }
    }
}

// MARK: - Help Button

struct HelpButton: View {
    let text: String
    @State private var showingHelp = false

    var body: some View {
        Button(action: { showingHelp.toggle() }) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingHelp, arrowEdge: .trailing) {
            Text(text)
                .font(.system(size: 11))
                .padding(10)
                .frame(width: 200)
        }
    }
}

// MARK: - Compact Shortcut Recorder

struct CompactShortcutRecorder: View {
    @Binding var shortcut: KeyboardShortcut
    @Binding var isEnabled: Bool
    var onShortcutChange: () -> Void

    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .tint(.brandCyan)
                .labelsHidden()
                .scaleEffect(0.65)
                .frame(width: 32)
                .onChange(of: isEnabled) { _ in
                    onShortcutChange()
                }

            Text(L("settings.shortcut"))
                .font(.system(size: 11))

            HelpButton(text: L("settings.shortcut.help"))

            Button(action: {
                isRecording.toggle()
                if isRecording {
                    startRecording()
                } else {
                    stopRecording()
                }
            }) {
                Text(isRecording ? L("settings.shortcut.press") : shortcut.displayString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isRecording ? .secondary : (isEnabled ? .primary : .secondary))
                    .lineLimit(1)
                    .frame(width: 60)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isRecording ? Color.brandCyan.opacity(0.15) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isRecording ? Color.brandCyan : Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .frame(height: 22)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if modifierKeyCodes.contains(event.keyCode) {
                return event
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasModifier = modifiers.contains(.command) || modifiers.contains(.control) ||
                             modifiers.contains(.option) || modifiers.contains(.shift)

            if hasModifier {
                shortcut = KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers)
                stopRecording()
                onShortcutChange()
                return nil
            }

            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
