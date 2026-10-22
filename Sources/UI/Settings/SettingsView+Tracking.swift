import AppKit
import SwiftUI

extension SettingsView {
    var trackingCard: some View {
        // Tracking card: mode picker in the header, source + device below
        SettingsCard(icon: "scope", title: L("settings.tracking"), helpText: L("settings.tracking.help")) {
            CompactModePicker(selection: trackingModeBinding)
                .frame(width: 170)
        } content: {
            VStack(spacing: 6) {

                if trackingModeSelection == .manual {
                    // Manual mode: source picker + device row for selected source
                    HStack(spacing: 8) {
                        Text(L("settings.source"))
                            .font(.system(size: 11))

                        Spacer()

                        CompactTrackingSourcePicker(
                            selection: trackingSourceBinding,
                            airPodsAvailable: airPodsAvailable
                        )
                        .frame(width: 170)
                    }
                    .frame(height: 26)

                    DeviceStatusRow(
                        source: trackingSource,
                        isCalibrated: trackingSource == .camera ? cameraCalibrated : airPodsCalibrated,
                        isConnected: trackingSource == .camera ? !availableCameras.isEmpty : airPodsConnected,
                        isPreferred: false,
                        isActive: isTrackingActive,
                        cameraDropdown: trackingSource == .camera && !availableCameras.isEmpty
                            ? AnyView(
                                Picker("", selection: selectedCameraBinding) {
                                    ForEach(availableCameras, id: \.id) { camera in
                                        Text(camera.name).tag(camera.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(minWidth: 130, maxWidth: 220)
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
                                selection: preferredSourceBinding,
                                airPodsAvailable: true
                            )
                            .frame(width: 170)
                        }
                        .frame(height: 26)

                        // Device status rows
                        DeviceStatusRow(
                            source: .camera,
                            isCalibrated: cameraCalibrated,
                            isConnected: !availableCameras.isEmpty,
                            isPreferred: preferredSource == .camera,
                            isActive: activeSource == .camera && isTrackingActive,
                            cameraDropdown: availableCameras.isEmpty
                                ? nil
                                : AnyView(
                                    Picker("", selection: selectedCameraBinding) {
                                        ForEach(availableCameras, id: \.id) { camera in
                                            Text(camera.name).tag(camera.id)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(minWidth: 130, maxWidth: 220)
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
                            isActive: activeSource == .airpods && isTrackingActive,
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

                Picker("", selection: activeDeskBinding) {
                    ForEach(desks) { desk in
                        Text(desk.name).tag(desk.id)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

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
}
