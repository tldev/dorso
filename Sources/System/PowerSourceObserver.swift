import Foundation
import IOKit.ps

/// Observes AC/battery power source changes via IOKit power sources
final class PowerSourceObserver {

    private var runLoopSource: CFRunLoopSource?
    private var lastKnownIsOnBattery: Bool?

    /// Fired on actual AC<->battery transitions. IOKit also notifies for
    /// battery capacity ticks; those are deduplicated in `evaluatePowerSource`.
    var onPowerSourceChanged: ((_ isOnBattery: Bool) -> Void)?

    /// Reads the current power source; replaceable so tests can simulate
    /// transitions without real power events.
    var currentPowerSourceProvider: () -> Bool = PowerSourceObserver.systemIsOnBattery

    var isObserving: Bool {
        runLoopSource != nil
    }

    /// Whether the Mac is currently drawing from its battery.
    var isOnBattery: Bool {
        currentPowerSourceProvider()
    }

    // MARK: - Public API

    func startObserving() {
        guard !isObserving else { return }

        lastKnownIsOnBattery = isOnBattery

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let observer = Unmanaged<PowerSourceObserver>.fromOpaque(context).takeUnretainedValue()
            observer.evaluatePowerSource()
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func stopObserving() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
        lastKnownIsOnBattery = nil
    }

    /// Re-reads the power source and fires the callback only on a real change.
    func evaluatePowerSource() {
        let isOnBattery = self.isOnBattery
        guard isOnBattery != lastKnownIsOnBattery else { return }
        lastKnownIsOnBattery = isOnBattery
        onPowerSourceChanged?(isOnBattery)
    }

    private static func systemIsOnBattery() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        guard let snapshot,
            let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        else {
            return false
        }
        return sourceType == kIOPMBatteryPowerKey
    }

    deinit {
        stopObserving()
    }
}
