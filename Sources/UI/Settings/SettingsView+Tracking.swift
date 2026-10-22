import AppKit
import SwiftUI

extension SettingsView {
    var trackingCard: some View {
        // Tracking card: mode picker in the header, source + device below
        SettingsCard(icon: "scope", title: L("settings.tracking"), helpText: L("settings.tracking.help")) {
            CompactModePicker(selection: $trackingModeSelection)
                .frame(width: 170)
                .onChange(of: trackingModeSelection) { newValue in
                    Task { @MainActor in
                        await appDelegate.setTrackingMode(newValue)
                        activeSource = appDelegate.activeTrackingSource
                    }
                }
        } content: {
            VStack(spacing: 6) {

                if trackingModeSelection == .manual {
                    // Manual mode: source picker + device row for selected source
                    HStack(spacing: 8) {
                        Text(L("settings.source"))
                            .font(.system(size: 11))

                        Spacer()

                        CompactTrackingSourcePicker(
                            selection: $trackingSource,
                            airPodsAvailable: airPodsAvailable
                        )
                        .frame(width: 170)
                        .onChange(of: trackingSource) { newValue in
                            if newValue != appDelegate.trackingSource {
                                Task { @MainActor in
                                    await appDelegate.switchTrackingSource(to: newValue)
                                }
                            }
                        }
                    }
                    .frame(height: 26)

                    DeviceStatusRow(
                        source: trackingSource,
                        isCalibrated: trackingSource == .camera ? cameraCalibrated : airPodsCalibrated,
                        isConnected: trackingSource == .camera ? !availableCameras.isEmpty : airPodsConnected,
                        isPreferred: false,
                        isActive: appDelegate.state.isActive,
                        cameraDropdown: trackingSource == .camera && !availableCameras.isEmpty
                            ? AnyView(
                                Picker("", selection: $selectedCameraID) {
                                    ForEach(availableCameras, id: \.id) { camera in
                                        Text(camera.name).tag(camera.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(minWidth: 130, maxWidth: 220)
                                .onChange(of: selectedCameraID) { newValue in
                                    if newValue != appDelegate.selectedCameraID {
                                        Task { @MainActor in
                                            await appDelegate.selectCamera(newValue)
                                        }
                                    }
                                }
                            ) : nil,
                        onCalibrate: {
                            appDelegate.startCalibration()
                        }
                    )

                    if trackingSource == .camera {
                        deskRow
                    }
                } else {
                    // Automatic mode layout
                    VStack(spacing: 6) {
                        // Preferred source picker
                        HStack(spacing: 8) {
                            Text(L("settings.preferred"))
                                .font(.system(size: 11))

                            Spacer()

                            CompactTrackingSourcePicker(
                                selection: $preferredSource,
                                airPodsAvailable: true
                            )
                            .frame(width: 170)
                            .onChange(of: preferredSource) { newValue in
                                Task { @MainActor in
                                    await appDelegate.setPreferredSource(newValue)
                                    activeSource = appDelegate.activeTrackingSource
                                }
                            }
                        }
                        .frame(height: 26)

                        // Device status rows
                        DeviceStatusRow(
                            source: .camera,
                            isCalibrated: cameraCalibrated,
                            isConnected: !availableCameras.isEmpty,
                            isPreferred: preferredSource == .camera,
                            isActive: activeSource == .camera && appDelegate.state.isActive,
                            cameraDropdown: availableCameras.isEmpty
                                ? nil
                                : AnyView(
                                    Picker("", selection: $selectedCameraID) {
                                        ForEach(availableCameras, id: \.id) { camera in
                                            Text(camera.name).tag(camera.id)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(minWidth: 130, maxWidth: 220)
                                    .onChange(of: selectedCameraID) { newValue in
                                        if newValue != appDelegate.selectedCameraID {
                                            Task { @MainActor in
                                                await appDelegate.selectCamera(newValue)
                                            }
                                        }
                                    }
                                ),
                            onCalibrate: {
                                appDelegate.startCalibration(for: .camera)
                            }
                        )

                        deskRow

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
        }
    }

    @ViewBuilder
    var deskRow: some View {
        if desks.count >= 2 {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Text(L("settings.desk"))
                        .font(.system(size: 11))
                    HelpButton(text: L("settings.desk.help"))
                }

                Spacer()

                Picker("", selection: $activeDeskID) {
                    ForEach(desks) { desk in
                        Text(desk.name).tag(desk.id)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .onChange(of: activeDeskID) { newValue in
                    Task { @MainActor in
                        await appDelegate.selectDesk(id: newValue)
                    }
                }

                CompactIconButton(systemName: "pencil", help: L("desk.renameTitle")) {
                    renameDeskName = desks.first(where: { $0.id == activeDeskID })?.name ?? ""
                    showingRenameDeskPrompt = true
                }

                CompactIconButton(systemName: "trash", help: L("desk.deleteTitle"), isDestructive: true) {
                    showingDeleteDeskConfirmation = true
                }
            }
            .frame(height: 26)
        }
    }

    func reloadDesks() {
        let key = DisplayMonitor.getCurrentConfigKey()
        desks = appDelegate.deskStore.desks(forKey: key)
        activeDeskID = appDelegate.deskStore.activeDesk(forKey: key)?.id ?? ""
    }
}
