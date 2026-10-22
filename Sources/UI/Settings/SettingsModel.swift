import Combine
import Foundation

/// Live app state for the Settings window. It observes the tracking store
/// and desk storage, so Settings stays current with changes made from the
/// menu bar, calibration, hot-plug, or a display change.
@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var tracking: TrackingFeature.State
    @Published private(set) var desks: [Desk] = []
    @Published private(set) var activeDeskID = ""

    private weak var appDelegate: AppDelegate?
    private var cancellables = Set<AnyCancellable>()

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        tracking = appDelegate.trackingStore.withState { $0 }
        reloadDesks()

        appDelegate.trackingStore.publisher
            .sink { [weak self] state in self?.tracking = state }
            .store(in: &cancellables)
        appDelegate.deskStore.changes
            .merge(with: appDelegate.displayChanges)
            .sink { [weak self] in self?.reloadDesks() }
            .store(in: &cancellables)
    }

    func reloadDesks() {
        guard let appDelegate else { return }
        let key = DisplayMonitor.getCurrentConfigKey()
        desks = appDelegate.deskStore.desks(forKey: key)
        activeDeskID = appDelegate.deskStore.activeDesk(forKey: key)?.id ?? ""
    }
}
