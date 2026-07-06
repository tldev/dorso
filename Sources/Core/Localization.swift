import Foundation

private var localizationBundle: Bundle {
    // In an app bundle, .lproj files live in Contents/Resources/ (Bundle.main).
    // SwiftPM's Bundle.module only works when the .build directory exists (dev/test).
    if Bundle.main.bundlePath.hasSuffix(".app") {
        return Bundle.main
    }
    return Bundle.module
}

private func localizedString(_ key: String) -> String {
    let value = NSLocalizedString(key, bundle: localizationBundle, comment: "")
    #if DEBUG
    if value == key {
        NSLog("Missing localization for key: %@", key)
    }
    #endif
    return value
}

public func L(_ key: String) -> String {
    localizedString(key)
}

public func L(_ key: String, _ args: CVarArg...) -> String {
    let format = localizedString(key)
    return String(format: format, locale: Locale.current, arguments: args)
}
