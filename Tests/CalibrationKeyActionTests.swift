import AppKit
import XCTest

@testable import DorsoCore

final class CalibrationKeyActionTests: XCTestCase {
    private func action(
        keyCode: UInt16 = 0,
        characters: String? = nil,
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false,
        isFromDorso: Bool = true,
        isChoosingDesk: Bool = false,
        deskCount: Int = 0
    ) -> CalibrationKeyAction? {
        CalibrationKeyAction.forKey(
            CalibrationKeyPress(
                keyCode: keyCode,
                characters: characters,
                modifiers: modifiers,
                isRepeat: isRepeat,
                isFromDorso: isFromDorso
            ),
            isChoosingDesk: isChoosingDesk,
            deskCount: deskCount
        )
    }

    // MARK: - Calibrating

    func testSpaceCapturesFromDorsoAndOtherApps() {
        XCTAssertEqual(action(keyCode: 49, characters: " "), .capture)
        XCTAssertEqual(action(keyCode: 49, characters: " ", isFromDorso: false), .capture)
    }

    func testEscapeAlwaysCancels() {
        XCTAssertEqual(action(keyCode: 53), .cancel)
        XCTAssertEqual(action(keyCode: 53, isFromDorso: false, isChoosingDesk: true, deskCount: 2), .cancel)
    }

    func testNTogglesNewDeskOnlyWhenADeskExists() {
        XCTAssertEqual(action(keyCode: 45, characters: "n", deskCount: 1), .toggleNewDesk)
        XCTAssertNil(action(keyCode: 45, characters: "n", deskCount: 0))
    }

    func testNFromOtherAppsIsIgnored() {
        XCTAssertNil(action(keyCode: 45, characters: "n", isFromDorso: false, deskCount: 1))
    }

    func testKeyRepeatIsIgnored() {
        XCTAssertNil(action(keyCode: 45, characters: "n", isRepeat: true, deskCount: 1))
        XCTAssertNil(action(keyCode: 49, characters: " ", isRepeat: true))
    }

    // MARK: - Desk Picker

    func testDigitsSelectDesks() {
        XCTAssertEqual(action(keyCode: 18, characters: "1", isChoosingDesk: true, deskCount: 2), .selectDesk(index: 0))
        XCTAssertEqual(action(keyCode: 19, characters: "2", isChoosingDesk: true, deskCount: 2), .selectDesk(index: 1))
    }

    func testDigitBeyondDeskCountIsIgnored() {
        XCTAssertNil(action(keyCode: 20, characters: "3", isChoosingDesk: true, deskCount: 2))
    }

    func testNumberRowWorksOnAzerty() {
        // The unshifted 1 and 2 keys type "&" and "é" on AZERTY
        XCTAssertEqual(action(keyCode: 18, characters: "&", isChoosingDesk: true, deskCount: 2), .selectDesk(index: 0))
        XCTAssertEqual(action(keyCode: 19, characters: "é", isChoosingDesk: true, deskCount: 2), .selectDesk(index: 1))
    }

    func testPickerLettersStartCalibration() {
        XCTAssertEqual(action(keyCode: 45, characters: "n", isChoosingDesk: true, deskCount: 2), .calibrateNewDesk)
        XCTAssertEqual(
            action(keyCode: 15, characters: "r", isChoosingDesk: true, deskCount: 2), .recalibrateCurrentDesk)
    }

    func testShortcutChordsAreIgnored() {
        XCTAssertNil(action(keyCode: 15, characters: "r", modifiers: .command, isChoosingDesk: true, deskCount: 2))
        XCTAssertNil(action(keyCode: 45, characters: "n", modifiers: .control, isChoosingDesk: true, deskCount: 2))
        XCTAssertNil(action(keyCode: 18, characters: "1", modifiers: .option, isChoosingDesk: true, deskCount: 2))
    }

    func testShiftedDigitsStillSelectDesks() {
        XCTAssertEqual(
            action(keyCode: 18, characters: "1", modifiers: .shift, isChoosingDesk: true, deskCount: 2),
            .selectDesk(index: 0))
    }

    func testPickerKeysFromOtherAppsAreIgnored() {
        XCTAssertNil(action(keyCode: 19, characters: "2", isFromDorso: false, isChoosingDesk: true, deskCount: 2))
        XCTAssertNil(action(keyCode: 15, characters: "r", isFromDorso: false, isChoosingDesk: true, deskCount: 2))
    }

    func testSpaceDoesNothingOnPicker() {
        XCTAssertNil(action(keyCode: 49, characters: " ", isChoosingDesk: true, deskCount: 2))
    }

    // MARK: - Arrow Navigation

    func testArrowsMoveFocusOnPicker() {
        XCTAssertEqual(action(keyCode: 126, isChoosingDesk: true, deskCount: 2), .moveFocus(by: -1))
        XCTAssertEqual(action(keyCode: 125, isChoosingDesk: true, deskCount: 2), .moveFocus(by: 1))
    }

    func testHeldArrowKeepsMoving() {
        XCTAssertEqual(action(keyCode: 125, isRepeat: true, isChoosingDesk: true, deskCount: 2), .moveFocus(by: 1))
    }

    func testArrowsCarryNumericPadFlagOnSomeKeyboards() {
        XCTAssertEqual(
            action(keyCode: 125, modifiers: [.numericPad, .function], isChoosingDesk: true, deskCount: 2),
            .moveFocus(by: 1))
    }

    func testReturnAndEnterActivateFocusedRow() {
        XCTAssertEqual(action(keyCode: 36, characters: "\r", isChoosingDesk: true, deskCount: 2), .activateFocused)
        XCTAssertEqual(action(keyCode: 76, characters: "\u{3}", isChoosingDesk: true, deskCount: 2), .activateFocused)
    }

    func testHeldReturnDoesNotRepeat() {
        XCTAssertNil(action(keyCode: 36, characters: "\r", isRepeat: true, isChoosingDesk: true, deskCount: 2))
    }

    func testNavigationKeysIgnoredOutsidePickerAndFromOtherApps() {
        XCTAssertNil(action(keyCode: 125))
        XCTAssertNil(action(keyCode: 36, characters: "\r"))
        XCTAssertNil(action(keyCode: 125, isFromDorso: false, isChoosingDesk: true, deskCount: 2))
        XCTAssertNil(action(keyCode: 36, characters: "\r", isFromDorso: false, isChoosingDesk: true, deskCount: 2))
    }

    @MainActor
    func testFocusStopsAtFirstAndLastRows() {
        XCTAssertEqual(CalibrationWindowController.movedFocus(from: 0, by: -1, rowCount: 4), 0)
        XCTAssertEqual(CalibrationWindowController.movedFocus(from: 3, by: 1, rowCount: 4), 3)
        XCTAssertEqual(CalibrationWindowController.movedFocus(from: 1, by: 1, rowCount: 4), 2)
        XCTAssertEqual(CalibrationWindowController.movedFocus(from: 0, by: 1, rowCount: 0), 0)
    }

    func testNAndRWorkOnNonLatinLayouts() {
        // On a Russian layout the N and R keys type "т" and "к"
        XCTAssertEqual(action(keyCode: 45, characters: "т", deskCount: 1), .toggleNewDesk)
        XCTAssertEqual(action(keyCode: 45, characters: "т", isChoosingDesk: true, deskCount: 2), .calibrateNewDesk)
        XCTAssertEqual(
            action(keyCode: 15, characters: "к", isChoosingDesk: true, deskCount: 2), .recalibrateCurrentDesk)
    }
}
