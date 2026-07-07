import AppKit

extension NSWindow {
    /// The screen the user is interacting with: the one containing the mouse
    /// pointer (they just clicked the menu bar there). Falls back to the
    /// window's screen, then the main screen.
    private var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// True when the frame sits entirely inside some screen's visible area
    /// (menu bar and Dock excluded). A restored frame that fails this test
    /// would render partially cut off and should be re-centered instead.
    var isFullyOnScreen: Bool {
        NSScreen.screens.contains { $0.visibleFrame.contains(frame) }
    }

    /// Centers on the screen containing the mouse pointer. `center()` uses
    /// whichever screen the (possibly never-shown) window is nominally on,
    /// which on multi-display setups is often not where the user is looking.
    func centerOnActiveScreen() {
        guard let visible = activeScreen?.visibleFrame else {
            center()
            return
        }
        setFrameOrigin(NSPoint(
            x: visible.midX - frame.width / 2,
            // Match center()'s placement: somewhat above the vertical middle.
            y: visible.minY + (visible.height - frame.height) * 2 / 3
        ))
    }

    /// Moves the window the minimum distance needed to sit fully inside the
    /// visible area of the screen it mostly occupies. If the window is
    /// larger than that area, the title bar stays reachable.
    func constrainToVisibleScreenArea() {
        guard !isFullyOnScreen else { return }

        let target = NSScreen.screens.max(by: { overlapArea(with: $0) < overlapArea(with: $1) })
        guard let visible = (overlapArea(with: target) > 0 ? target : activeScreen)?.visibleFrame else { return }

        var origin = frame.origin
        origin.x = frame.width >= visible.width
            ? visible.minX
            : min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = frame.height >= visible.height
            ? visible.maxY - frame.height
            : min(max(origin.y, visible.minY), visible.maxY - frame.height)
        setFrameOrigin(origin)
    }

    private func overlapArea(with screen: NSScreen?) -> CGFloat {
        guard let screen else { return 0 }
        let overlap = screen.visibleFrame.intersection(frame)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
