import AppKit
import CoreGraphics

/// Monitors display configuration changes (connect/disconnect/arrangement)
final class DisplayMonitor {

    typealias RegisterCallback = (CGDisplayReconfigurationCallBack, UnsafeMutableRawPointer?) -> CGError
    typealias RemoveCallback = (CGDisplayReconfigurationCallBack, UnsafeMutableRawPointer?) -> CGError

    private var debounceTimer: Timer?
    private var callbackRegistered = false
    private var callbackUserInfo: UnsafeMutableRawPointer?

    private let registerCallback: RegisterCallback
    private let removeCallback: RemoveCallback

    var onDisplayConfigurationChange: (() -> Void)?

    // MARK: - Public API

    init(
        registerCallback: @escaping RegisterCallback = CGDisplayRegisterReconfigurationCallback,
        removeCallback: @escaping RemoveCallback = CGDisplayRemoveReconfigurationCallback
    ) {
        self.registerCallback = registerCallback
        self.removeCallback = removeCallback
    }

    func startMonitoring() {
        guard !callbackRegistered else { return }

        callbackUserInfo = Unmanaged.passUnretained(self).toOpaque()
        let result = registerCallback(Self.displayReconfigurationCallback, callbackUserInfo)
        if result == .success {
            callbackRegistered = true
        } else {
            callbackUserInfo = nil
        }
    }

    func stopMonitoring() {
        guard callbackRegistered else { return }

        debounceTimer?.invalidate()
        debounceTimer = nil

        if let callbackUserInfo {
            _ = removeCallback(Self.displayReconfigurationCallback, callbackUserInfo)
        }
        callbackUserInfo = nil
        callbackRegistered = false
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Display Utilities

    /// Returns sorted list of display UUIDs for current configuration
    static func getDisplayUUIDs() -> [String] {
        var uuids: [String] = []

        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }

            if let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber)?.takeRetainedValue() {
                let uuidString = CFUUIDCreateString(nil, uuid) as String
                uuids.append(uuidString)
            }
        }

        return uuids.sorted()
    }

    /// Returns a unique key identifying the current display configuration
    static func getCurrentConfigKey() -> String {
        let displays = getDisplayUUIDs()
        return "displays:\(displays.joined(separator: "+"))"
    }

    /// Checks if running on laptop display only (no external monitors)
    static func isLaptopOnlyConfiguration() -> Bool {
        let screens = NSScreen.screens
        if screens.count != 1 { return false }

        guard let screen = screens.first,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }

        return CGDisplayIsBuiltin(displayID) != 0
    }

    // MARK: - Private

    private static let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        // Ignore begin configuration events
        if flags.contains(.beginConfigurationFlag) {
            return
        }

        monitor.scheduleConfigurationChange()
    }

    private func scheduleConfigurationChange() {
        DispatchQueue.main.async { [weak self] in
            self?.debounceTimer?.invalidate()
            self?.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.onDisplayConfigurationChange?()
            }
        }
    }
}
