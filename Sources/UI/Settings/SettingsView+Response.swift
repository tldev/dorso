import AppKit
import SwiftUI

extension SettingsView {
    var responseCard: some View {
        // Posture response card: profile management in the header,
        // warning style + tuning sliders below
        SettingsCard(
            icon: "slider.horizontal.3", title: L("settings.section.response"),
            helpText: L("settings.profile.help")
        ) {
            HStack(spacing: 4) {
                Picker("", selection: $selectedSettingsProfileID) {
                    ForEach(settingsProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: selectedSettingsProfileID) { newValue in
                    handleProfileSelectionChange(newValue)
                }

                Button(action: {
                    newProfileName = ""
                    showingNewProfilePrompt = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.brandCyan)
                        .frame(width: 24, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.brandCyan.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.brandCyan.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(L("settings.profile.new"))

                // Rename button - the Default profile keeps its name
                CompactIconButton(
                    systemName: "pencil",
                    help: L("settings.profile.renameTitle"),
                    isEnabled: canRenameCurrentProfile
                ) {
                    renameProfileName =
                        settingsProfiles.first(where: { $0.id == selectedSettingsProfileID })?.name ?? ""
                    showingRenameProfilePrompt = true
                }

                // Delete button - only enabled for non-Default profiles when more than one exists
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(canDeleteCurrentProfile ? .red.opacity(0.8) : .secondary.opacity(0.4))
                        .frame(width: 24, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    canDeleteCurrentProfile
                                        ? Color.red.opacity(0.08) : Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    canDeleteCurrentProfile
                                        ? Color.red.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canDeleteCurrentProfile)
                .help(L("settings.profile.deleteTitle"))
            }
        } content: {
            VStack(spacing: 6) {

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

                    // Color only applies to the drawn warning styles, so the
                    // swatch would be dead weight next to Blur/None
                    if warningMode.usesWarningOverlay {
                        InlineColorPicker(color: $warningColor)
                            .onChange(of: warningColor) { newValue in
                                let nsColor = NSColor(newValue)
                                settingsProfileManager.updateActiveProfile(warningColor: nsColor)
                                appDelegate.updateWarningColor(nsColor)
                            }
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
        }
    }

    func syncProfileSettings() {
        intensity = appDelegate.activeIntensity
        deadZone = appDelegate.activeDeadZone
        intensitySlider = Double(Self.closestIndex(for: Double(appDelegate.activeIntensity), in: intensityValues))
        deadZoneSlider = Double(Self.closestIndex(for: Double(appDelegate.activeDeadZone), in: deadZoneValues))
        warningMode = appDelegate.activeWarningMode
        warningColor = Color(appDelegate.activeWarningColor)
        warningOnsetDelay = appDelegate.activeWarningOnsetDelay
        detectionModeSlider = Double(detectionModes.firstIndex(of: appDelegate.activeDetectionMode) ?? 0)
    }

    func handleProfileSelectionChange(_ newValue: String) {
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

    func nextDefaultProfileName() -> String {
        let existingNames = Set(settingsProfiles.map { $0.name })
        var index = 1
        while existingNames.contains("Profile \(index)") {
            index += 1
        }
        return "Profile \(index)"
    }
}
