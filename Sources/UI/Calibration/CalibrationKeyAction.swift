import AppKit

enum CalibrationKeyAction: Equatable {
    case cancel
    case capture
    case toggleNewDesk
    case selectDesk(index: Int)
    case calibrateNewDesk
    case recalibrateCurrentDesk
    case moveFocus(by: Int)
    case activateFocused

    /// kVK_ANSI_1...9, so number keys work on layouts like AZERTY
    private static let numberRowKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// Keys typed into other apps only reach Space and Escape.
    static func forKey(_ press: CalibrationKeyPress, isChoosingDesk: Bool, deskCount: Int) -> CalibrationKeyAction? {
        if press.keyCode == 53 { return .cancel }  // Escape
        guard press.modifiers.intersection([.command, .option, .control]).isEmpty else { return nil }
        if isChoosingDesk {
            return press.isFromDorso ? pickerAction(for: press, deskCount: deskCount) : nil
        }
        guard !press.isRepeat else { return nil }
        if press.keyCode == 49 { return .capture }  // Space
        if letter(for: press) == "n", deskCount > 0, press.isFromDorso { return .toggleNewDesk }
        return nil
    }

    private static func pickerAction(for press: CalibrationKeyPress, deskCount: Int) -> CalibrationKeyAction? {
        // Arrows may repeat
        if press.keyCode == 126 { return .moveFocus(by: -1) }  // Up arrow
        if press.keyCode == 125 { return .moveFocus(by: 1) }  // Down arrow
        guard !press.isRepeat else { return nil }
        if press.keyCode == 36 || press.keyCode == 76 { return .activateFocused }  // Return, keypad Enter

        let key = letter(for: press)
        let number = Int(key) ?? numberRowKeyCodes.firstIndex(of: press.keyCode).map { $0 + 1 }
        if let number, number >= 1, number <= min(deskCount, 9) {
            return .selectDesk(index: number - 1)
        }
        if key == "n" { return .calibrateNewDesk }
        if key == "r" { return .recalibrateCurrentDesk }
        return nil
    }

    /// Physical N and R for non-Latin layouts
    private static func letter(for press: CalibrationKeyPress) -> String {
        let key = press.characters?.lowercased() ?? ""
        guard !key.allSatisfy(\.isASCII) else { return key }
        if press.keyCode == 45 { return "n" }
        if press.keyCode == 15 { return "r" }
        return key
    }
}

struct CalibrationKeyPress {
    var keyCode: UInt16
    var characters: String?
    var modifiers: NSEvent.ModifierFlags = []
    var isRepeat = false
    /// False for keys the global monitor saw typed into other apps
    var isFromDorso = true
}

/// `key` is empty for desks past the ninth.
struct DeskPickerRow: Equatable {
    let key: String
    let title: String
    let action: CalibrationKeyAction
    var isCurrent = false
    var isSecondary = false
}
