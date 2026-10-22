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
        static let desk = 5
        static let recalibrate = 6
    }

    func testUpdatesBeforeMenuExistsAreSafeNoOps() {
        let manager = MenuBarManager()
        manager.updateStatus(text: "ignored", icon: .good)
        manager.updateEnabledState(false)
        manager.updateRecalibrateEnabled(false)
        manager.updatePauseState(canPause: false, isTimedPause: true)
        manager.updateDeskEnabled(false)
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

    func testDeskMenuHiddenWithFewerThanTwoDesks() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()
        manager.desksProvider = { ([(id: "a", name: "Home")], "a") }

        manager.refreshDesks()

        XCTAssertTrue(menu.items[ItemIndex.desk].isHidden)
    }

    func testDeskMenuListsDesksWithActiveChecked() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()
        manager.desksProvider = { ([(id: "a", name: "Home"), (id: "b", name: "Uni")], "b") }

        manager.refreshDesks()

        XCTAssertFalse(menu.items[ItemIndex.desk].isHidden)
        let items = menu.items[ItemIndex.desk].submenu!.items
        XCTAssertEqual(items.prefix(2).map(\.title), ["Home", "Uni"])
        XCTAssertEqual(items.prefix(2).map(\.state), [.off, .on])
        XCTAssertEqual(items.last?.title, L("menu.manageDesks"))
    }

    func testOpeningMenuRefreshesDesks() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()
        manager.desksProvider = { ([(id: "a", name: "Home"), (id: "b", name: "Uni")], "a") }

        manager.menuNeedsUpdate(menu)

        XCTAssertFalse(menu.items[ItemIndex.desk].isHidden)
    }

    func testSelectingDeskInvokesCallbackWithID() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()
        manager.desksProvider = { ([(id: "a", name: "Home"), (id: "b", name: "Uni")], "a") }
        manager.refreshDesks()
        var selected: String?
        manager.onSelectDesk = { selected = $0 }

        menu.items[ItemIndex.desk].submenu!.performActionForItem(at: 1)

        XCTAssertEqual(selected, "b")
    }

    func testDeskMenuDisabledWhileCalibrating() {
        let manager = MenuBarManager()
        let menu = manager.makeMenu()

        manager.updateDeskEnabled(false)
        XCTAssertFalse(menu.items[ItemIndex.desk].isEnabled)

        manager.updateDeskEnabled(true)
        XCTAssertTrue(menu.items[ItemIndex.desk].isEnabled)
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
