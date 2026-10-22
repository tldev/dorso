import AppKit
import XCTest
@testable import DorsoCore

/// Exercises MenuBarManager's update paths without a window server by
/// building the menu via makeMenu() instead of setup().
@MainActor
final class MenuBarManagerHeadlessTests: XCTestCase {
    private enum ItemIndex {
        static let status = 0
        static let enabled = 2
        static let resume = 3
        static let pause = 4
        static let recalibrate = 5
    }

    func testUpdatesBeforeMenuExistsAreSafeNoOps() {
        let manager = MenuBarManager()
        manager.updateStatus(text: "ignored", icon: .good)
        manager.updateEnabledState(false)
        manager.updateRecalibrateEnabled(false)
        manager.updatePauseState(canPause: false, isTimedPause: true)
        manager.updateShortcut(enabled: true, shortcut: .defaultShortcut)
    }

    func testUpdateStatusSetsStatusMenuItemTitle() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()

        manager.updateStatus(text: "Monitoring posture", icon: .good)

        XCTAssertEqual(menu.items[ItemIndex.status].title, "Monitoring posture")
    }

    func testUpdateEnabledStateTogglesMenuItemState() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()

        manager.updateEnabledState(false)
        XCTAssertEqual(menu.items[ItemIndex.enabled].state, .off)

        manager.updateEnabledState(true)
        XCTAssertEqual(menu.items[ItemIndex.enabled].state, .on)
    }

    func testUpdateRecalibrateEnabledTogglesItem() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()

        manager.updateRecalibrateEnabled(false)
        XCTAssertFalse(menu.items[ItemIndex.recalibrate].isEnabled)

        manager.updateRecalibrateEnabled(true)
        XCTAssertTrue(menu.items[ItemIndex.recalibrate].isEnabled)
    }

    func testPauseSubmenuOffersEachDuration() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()

        let durations = menu.items[ItemIndex.pause].submenu?.items.compactMap { $0.representedObject as? TimeInterval }
        XCTAssertEqual(durations, MenuBarManager.pauseDurations)
    }

    func testPauseMenuInvokesCallbackWithDuration() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()
        var received: TimeInterval?
        manager.onPause = { received = $0 }

        let submenu = menu.items[ItemIndex.pause].submenu!
        submenu.performActionForItem(at: 1)

        XCTAssertEqual(received, MenuBarManager.pauseDurations[1])
    }

    func testUpdatePauseStateTogglesPauseAndResumeItems() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()
        XCTAssertTrue(menu.items[ItemIndex.resume].isHidden)

        manager.updatePauseState(canPause: true, isTimedPause: true)
        XCTAssertTrue(menu.items[ItemIndex.pause].isEnabled)
        XCTAssertFalse(menu.items[ItemIndex.resume].isHidden)

        manager.updatePauseState(canPause: false, isTimedPause: false)
        XCTAssertFalse(menu.items[ItemIndex.pause].isEnabled)
        XCTAssertTrue(menu.items[ItemIndex.resume].isHidden)
    }

    func testUpdateShortcutAppliesAndClearsKeyEquivalent() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()
        let shortcut = KeyboardShortcut.defaultShortcut

        manager.updateShortcut(enabled: true, shortcut: shortcut)
        XCTAssertEqual(menu.items[ItemIndex.enabled].keyEquivalent, shortcut.keyCharacter)
        XCTAssertEqual(menu.items[ItemIndex.enabled].keyEquivalentModifierMask, shortcut.modifiers)

        manager.updateShortcut(enabled: false, shortcut: shortcut)
        XCTAssertEqual(menu.items[ItemIndex.enabled].keyEquivalent, "")
        XCTAssertEqual(menu.items[ItemIndex.enabled].keyEquivalentModifierMask, [])
    }

    func testEveryMenuBarIconResolvesToAnImage() {
        for icon in MenuBarIcon.allCases {
            XCTAssertNotNil(icon.image, "No image for \(icon)")
        }
    }

    func testEveryMenuBarIconTypeMapsToMatchingMenuBarIcon() {
        XCTAssertEqual(MenuBarIconType.good.menuBarIcon, .good)
        XCTAssertEqual(MenuBarIconType.bad.menuBarIcon, .bad)
        XCTAssertEqual(MenuBarIconType.away.menuBarIcon, .away)
        XCTAssertEqual(MenuBarIconType.paused.menuBarIcon, .paused)
        XCTAssertEqual(MenuBarIconType.calibrating.menuBarIcon, .calibrating)
    }
}
