#if !APP_STORE
import AppKit
import Sparkle

// MARK: - Updater Manager

/// Owns the Sparkle auto-updater for direct-distribution (GitHub) builds.
/// App Store builds compile this out entirely; the App Store delivers
/// updates for those installs.
@MainActor
final class UpdaterManager: NSObject {
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Whether Sparkle checks for updates in the background. Persisted by
    /// Sparkle itself; setting it explicitly also suppresses Sparkle's
    /// first-run permission prompt.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

// MARK: - Gentle Reminders

extension UpdaterManager: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Sparkle shows scheduled update alerts without activating the app;
        // for a menu bar app that leaves the alert buried behind other
        // windows. Bring the app forward so the alert is actually seen.
        guard !state.userInitiated else { return }
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
#endif
