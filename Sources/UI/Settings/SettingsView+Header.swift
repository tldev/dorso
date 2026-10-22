import AppKit
import SwiftUI

extension SettingsView {
    // Compact header
    var header: some View {
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
        .padding(.bottom, 12)
    }
}
