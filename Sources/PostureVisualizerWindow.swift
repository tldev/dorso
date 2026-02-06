import SwiftUI
import AppKit

// MARK: - Live Data Model

@MainActor
final class PostureVisualizerModel: ObservableObject {
    static let shared = PostureVisualizerModel()

    @Published var appState: AppState = .disabled
    @Published var isCurrentlySlouching: Bool = false
    @Published var isCurrentlyAway: Bool = false
    @Published var severity: Double = 0
    @Published var warningIntensity: CGFloat = 0
    @Published var consecutiveBadFrames: Int = 0
    @Published var consecutiveGoodFrames: Int = 0
    @Published var trackingSource: TrackingSource = .camera

    func update(from monitoringState: PostureMonitoringState, appState: AppState, trackingSource: TrackingSource, severity: Double) {
        self.appState = appState
        self.isCurrentlySlouching = monitoringState.isCurrentlySlouching
        self.isCurrentlyAway = monitoringState.isCurrentlyAway
        self.warningIntensity = monitoringState.postureWarningIntensity
        self.consecutiveBadFrames = monitoringState.consecutiveBadFrames
        self.consecutiveGoodFrames = monitoringState.consecutiveGoodFrames
        self.trackingSource = trackingSource
        self.severity = severity
    }
}

// MARK: - Window Controller

@MainActor
class PostureVisualizerWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PostureVisualizerView()
        let hostingController = NSHostingController(rootView: view)
        let fittingSize = hostingController.sizeThatFits(in: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("visualizer.title")
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor.windowBackgroundColor

        window.setFrameAutosaveName("PostureVisualizerWindow")
        if !window.setFrameUsingName("PostureVisualizerWindow") {
            window.center()
        }

        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Handled by AppDelegate if needed
    }
}

// MARK: - Visualizer View

struct PostureVisualizerView: View {
    @ObservedObject var model = PostureVisualizerModel.shared

    private var statusLabel: String {
        switch model.appState {
        case .disabled:
            return L("visualizer.status.disabled")
        case .calibrating:
            return L("visualizer.status.calibrating")
        case .monitoring:
            if model.isCurrentlyAway {
                return L("visualizer.status.away")
            } else if model.isCurrentlySlouching {
                return L("visualizer.status.slouching")
            } else {
                return L("visualizer.status.good")
            }
        case .paused:
            return L("visualizer.status.paused")
        }
    }

    private var statusColor: Color {
        switch model.appState {
        case .monitoring:
            if model.isCurrentlyAway { return .secondary }
            if model.isCurrentlySlouching { return .orange }
            return .brandCyan
        default:
            return .secondary
        }
    }

    private var isActive: Bool {
        model.appState == .monitoring && !model.isCurrentlyAway
    }

    var body: some View {
        VStack(spacing: 16) {
            // Posture ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)

                // Severity arc (shows how bad posture is)
                if isActive {
                    Circle()
                        .trim(from: 0, to: 1.0 - model.severity)
                        .stroke(
                            statusColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: model.severity)
                }

                // Center figure
                VStack(spacing: 4) {
                    Image(systemName: figureSymbol)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(statusColor)
                        .rotationEffect(figureRotation)
                        .animation(.easeInOut(duration: 0.3), value: model.isCurrentlySlouching)

                    Text(statusLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(statusColor)
                }
            }
            .frame(width: 140, height: 140)

            // Warning intensity bar
            if isActive {
                VStack(spacing: 4) {
                    HStack {
                        Text(L("visualizer.warningLevel"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(intensityLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(intensityColor)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))

                            RoundedRectangle(cornerRadius: 3)
                                .fill(intensityBarGradient)
                                .frame(width: max(0, geo.size.width * model.warningIntensity))
                                .animation(.easeOut(duration: 0.15), value: model.warningIntensity)
                        }
                    }
                    .frame(height: 6)
                }
            }

            // Live stats
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    StatPill(
                        icon: "arrow.up.heart",
                        label: L("visualizer.goodFrames"),
                        value: "\(model.consecutiveGoodFrames)",
                        color: .brandCyan
                    )
                    StatPill(
                        icon: "arrow.down.heart",
                        label: L("visualizer.badFrames"),
                        value: "\(model.consecutiveBadFrames)",
                        color: .orange
                    )
                }

                HStack(spacing: 12) {
                    StatPill(
                        icon: model.trackingSource.icon,
                        label: L("visualizer.source"),
                        value: model.trackingSource.displayName,
                        color: .secondary
                    )
                    StatPill(
                        icon: "gauge.medium",
                        label: L("visualizer.severity"),
                        value: String(format: "%.0f%%", model.severity * 100),
                        color: severityStatColor
                    )
                }
            }
        }
        .padding(20)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Computed Helpers

    private var figureSymbol: String {
        switch model.appState {
        case .monitoring:
            if model.isCurrentlyAway { return "figure.walk" }
            if model.isCurrentlySlouching { return "figure.fall" }
            return "figure.stand"
        case .calibrating:
            return "figure.stand"
        default:
            return "pause.circle"
        }
    }

    private var figureRotation: Angle {
        if model.isCurrentlySlouching {
            return .degrees(min(model.severity * 15, 12))
        }
        return .degrees(0)
    }

    private var intensityLabel: String {
        if model.warningIntensity <= 0 {
            return L("visualizer.intensity.none")
        }
        return String(format: "%.0f%%", model.warningIntensity * 100)
    }

    private var intensityColor: Color {
        if model.warningIntensity <= 0 { return .secondary }
        if model.warningIntensity < 0.5 { return .orange }
        return .red
    }

    private var intensityBarGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var severityStatColor: Color {
        if model.severity <= 0 { return .brandCyan }
        if model.severity < 0.5 { return .orange }
        return .red
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
