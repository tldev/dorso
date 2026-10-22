import AppKit
import SwiftUI

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

// MARK: - Compact Segmented Picker

/// Generic brand-styled segmented control for small option sets.
struct CompactSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button(action: { selection = option.value }) {
                    Text(option.label)
                        .font(.system(size: 10, weight: selection == option.value ? .semibold : .regular))
                        .foregroundColor(selection == option.value ? .onBrandCyan : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(selection == option.value ? Color.brandCyan : Color.clear)
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

// MARK: - Compact Mode Picker

struct CompactModePicker: View {
    @Binding var selection: TrackingMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach([TrackingMode.manual, .automatic], id: \.self) { mode in
                Button(action: { selection = mode }) {
                    Text(mode == .manual ? L("settings.mode.manual") : L("settings.mode.automatic"))
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

// MARK: - Device Status Row

struct DeviceStatusRow: View {
    let source: TrackingSource
    let isCalibrated: Bool
    let isConnected: Bool
    let isPreferred: Bool
    var isActive: Bool = false
    var cameraDropdown: AnyView? = nil
    let onCalibrate: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Device icon and name
            Image(systemName: source.icon)
                .font(.system(size: 10))
                .foregroundColor(isPreferred ? .brandCyan : .secondary)
                .frame(width: 14)

            Text(source.displayName)
                .font(.system(size: 11, weight: isPreferred ? .medium : .regular))
                .frame(width: 55, alignment: .leading)

            // Calibration status: icon-only when the camera picker is there
            // to give the row context (the dropdown needs the width), icon +
            // label on rows that would otherwise be unexplained glyphs
            let showsDropdown = source == .camera && cameraDropdown != nil
            HStack(spacing: 3) {
                Image(systemName: isCalibrated ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isCalibrated ? .green : .orange)
                if !showsDropdown {
                    Text(isCalibrated ? L("settings.calibrated") : L("settings.notCalibrated"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 2)
            .frame(minWidth: 18, minHeight: 22)
            .contentShape(Rectangle())
            .help(isCalibrated ? L("settings.calibrated") : L("settings.notCalibrated"))

            if source == .camera, let dropdown = cameraDropdown {
                dropdown
            } else if source == .airpods {
                // Connection status
                HStack(spacing: 3) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(isConnected ? L("settings.connected") : L("settings.notConnected"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 2)
                .frame(minHeight: 22)
                .contentShape(Rectangle())
                .help(isConnected ? L("settings.connected") : L("settings.notConnected"))
            }

            Spacer(minLength: 0)

            if isActive {
                Text(L("settings.active"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.brandCyan)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.brandCyan.opacity(0.12)))
                    .fixedSize()
            }

            // Calibrate button
            Button(action: onCalibrate) {
                Text(L("settings.recalibrate"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.brandCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.brandCyan.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.brandCyan.opacity(0.3), lineWidth: 1)
                    )
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
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
                    .foregroundColor(
                        selection == source ? .onBrandCyan : (isDisabled ? .secondary.opacity(0.5) : .primary)
                    )
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
