import AppKit
import SwiftUI
import AVFoundation

// MARK: - Onboarding Window Controller

class OnboardingWindowController: NSObject, NSWindowDelegate {
    var window: NSWindow?
    var onComplete: ((TrackingSource, String?) -> Void)?

    private var cameraDetector: CameraPostureDetector?
    private var airPodsDetector: AirPodsPostureDetector?

    func show(
        cameraDetector: CameraPostureDetector,
        airPodsDetector: AirPodsPostureDetector,
        onComplete: @escaping (TrackingSource, String?) -> Void
    ) {
        self.cameraDetector = cameraDetector
        self.airPodsDetector = airPodsDetector
        self.onComplete = onComplete

        let onboardingView = OnboardingView(
            cameraDetector: cameraDetector,
            airPodsDetector: airPodsDetector,
            onComplete: { [weak self] source, cameraID in
                // Clear the controller's onComplete BEFORE closing to prevent
                // windowWillClose from calling it again with .camera default
                self?.onComplete = nil
                self?.window?.close()
                onComplete(source, cameraID)
            }
        )

        let hostingController = NSHostingController(rootView: onboardingView)
        let fittingSize = hostingController.sizeThatFits(in: CGSize(width: 500, height: 600))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Posturr"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // If closed without selection, default to camera
        if let onComplete = onComplete {
            onComplete(.camera, cameraDetector?.selectedCameraID)
            self.onComplete = nil
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    let cameraDetector: CameraPostureDetector
    let airPodsDetector: AirPodsPostureDetector
    let onComplete: (TrackingSource, String?) -> Void

    @State private var selectedSource: TrackingSource = .camera
    @State private var selectedCameraID: String = ""
    @State private var availableCameras: [(id: String, name: String)] = []
    @State private var pairedAirPods: [PairedAirPods] = []

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                }

                Text("Welcome to Posturr")
                    .font(.system(size: 24, weight: .semibold))

                Text("Choose how you want to track your posture")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            // Tracking method selection
            VStack(spacing: 12) {
                TrackingOptionCard(
                    source: .camera,
                    isSelected: selectedSource == .camera,
                    isAvailable: true,
                    statusText: nil
                ) {
                    selectedSource = .camera
                }

                TrackingOptionCard(
                    source: .airpods,
                    isSelected: selectedSource == .airpods,
                    isAvailable: airPodsDetector.isAvailable,
                    statusText: airPodsDetector.isAvailable ? nil : airPodsDetector.unavailableReason,
                    statusIsPositive: false
                ) {
                    if airPodsDetector.isAvailable {
                        selectedSource = .airpods
                    }
                }
            }

            // Camera selection (only when camera is selected)
            if selectedSource == .camera && !availableCameras.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Camera")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedCameraID) {
                        ForEach(availableCameras, id: \.id) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 4)
            }

            // Paired AirPods list (when AirPods is selected)
            if selectedSource == .airpods && !pairedAirPods.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paired AirPods")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    VStack(spacing: 6) {
                        ForEach(pairedAirPods, id: \.name) { airpods in
                            HStack {
                                Image(systemName: "airpodspro")
                                    .font(.system(size: 14))
                                    .foregroundColor(airpods.isCompatible ? .brandCyan : .secondary)
                                    .frame(width: 24)

                                Text(airpods.name)
                                    .font(.system(size: 13))

                                Spacer()

                                Text(airpods.compatibilityText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(airpods.isCompatible ? .green : .orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(airpods.isCompatible ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                    )
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            // Continue button
            Button(action: {
                let cameraID = selectedSource == .camera ? selectedCameraID : nil
                onComplete(selectedSource, cameraID)
            }) {
                HStack {
                    Text("Continue")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.brandCyan)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loadCameras()
        }
        .onChange(of: selectedSource) { newSource in
            if newSource == .airpods && pairedAirPods.isEmpty {
                loadPairedAirPods()
            }
        }
    }

    private func loadCameras() {
        let cameras = cameraDetector.getAvailableCameras()
        availableCameras = cameras.map { (id: $0.uniqueID, name: $0.localizedName) }
        if let firstCamera = availableCameras.first {
            selectedCameraID = cameraDetector.selectedCameraID ?? firstCamera.id
        }
    }

    private func loadPairedAirPods() {
        pairedAirPods = airPodsDetector.getPairedAirPods()
    }
}

// MARK: - Tracking Option Card

struct TrackingOptionCard: View {
    let source: TrackingSource
    let isSelected: Bool
    let isAvailable: Bool
    let statusText: String?
    var statusIsPositive: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Icon
                Image(systemName: source.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .brandCyan : (isAvailable ? .primary : .secondary.opacity(0.5)))
                    .frame(width: 40)

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(source.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isAvailable ? .primary : .secondary.opacity(0.5))

                        if !isAvailable {
                            Text("Unavailable")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                )
                        }
                    }

                    Text(source.description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let status = statusText {
                        HStack(spacing: 4) {
                            Image(systemName: statusIsPositive ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                            Text(status)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(statusIsPositive ? .green : .orange)
                    }
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.brandCyan)
                } else {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.brandCyan : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }
}
