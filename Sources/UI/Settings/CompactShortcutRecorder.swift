import AppKit
import SwiftUI

// MARK: - Compact Shortcut Recorder

struct CompactShortcutRecorder: View {
    @Binding var shortcut: KeyboardShortcut
    @Binding var isEnabled: Bool
    var onShortcutChange: () -> Void

    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            BrandSwitch(isOn: $isEnabled)
                .frame(width: 32, alignment: .leading)
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
            let hasModifier =
                modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option)
                || modifiers.contains(.shift)

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
