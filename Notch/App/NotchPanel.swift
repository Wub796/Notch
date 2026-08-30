import AppKit

/// Borderless, transparent, non-activating panel that floats above the menu bar.
/// It never becomes the main window and never steals focus from the frontmost app.
final class NotchPanel: NSPanel {
    private weak var state: NotchState?

    init(contentRect: NSRect, state: NotchState? = nil) {
        self.state = state
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool {
        state?.mode == .expanded
    }

    override var canBecomeMain: Bool { false }
}
