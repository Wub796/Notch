import AppKit

/// Borderless, transparent, click-through panel for the Face ID overlay.
///
/// Ported from Glance (`NotchOverlay/NotchWindow.swift`, MIT © Jonathan Zhou).
/// Created once and never resized: every expansion and collapse is SwiftUI
/// animating content inside this fixed window. Nothing may call `setFrame` or
/// `setContentSize` on it — only `setFrameOrigin`, to move it between displays.
final class FaceIDOverlayWindow: NSPanel {
    /// Whether the panel may become key.
    ///
    /// Tracked separately from `ignoresMouseEvents`, which the window controller
    /// flips as the cursor moves over and away from the visible panel: tying key
    /// status to that would mean the panel stops being able to take focus whenever
    /// the pointer happened to sit outside it.
    var acceptsKey = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        // Above the menu bar, and above anything the app itself draws — at the lock
        // screen this is what puts it over the login window's own chrome.
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Decorative by default: clicks pass through until a failed attempt is
        // waiting to be hovered for a retry.
        ignoresMouseEvents = true
    }

    /// Must become key while interactive, or the hover-to-retry gesture never
    /// receives the event. Never becomes main, so it can't take over as the app's
    /// primary window.
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

/// Owns the overlay window's lifecycle: creation, positioning, show and hide, and
/// the SkyLight lock-screen delegation. Knows nothing about face recognition,
/// animation phases, or video playback — `FaceIDOverlayController` drives this.
///
/// Ported from Glance (`NotchOverlay/NotchWindowController.swift`, MIT © Jonathan
/// Zhou).
@MainActor
final class FaceIDOverlayWindowController {
    private var window: FaceIDOverlayWindow?
    private var isSkyLightDelegated = false

    /// What the overlay controller asked for through `setInteractive(_:)`.
    private var wantsInteractive = false
    /// The visible panel's frame inside the window, in the hosting view's top-down
    /// coordinates — reported by `FaceIDOverlayView`.
    private var interactiveContentRect: CGRect?
    /// Re-checks the cursor while `wantsInteractive`; see `updateMousePassthrough()`.
    private var cursorPollTimer: Timer?

    /// Slack around the visible panel before clicks pass through, so a click on the
    /// very edge of the shape — or mid hover-bump — doesn't miss it.
    private static let interactiveRectOutset: CGFloat = 6

    /// The SwiftUI content to host, set once by the overlay controller.
    var contentView: NSView? {
        didSet { window?.contentView = contentView }
    }

    /// Fired on display changes so the overlay controller can re-read
    /// `currentGeometry` — plugging in a notched display changes the panel's shape,
    /// not just its width.
    var onScreenParametersChanged: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Creates the window if needed, positions it, and orders it front. While the
    /// screen is actually locked, also delegates it into the elevated SkyLight
    /// space — see `FaceIDSkyLight`.
    func show() {
        let window = windowIfNeeded()
        reposition(window)
        window.orderFrontRegardless()

        if LockMonitor.isScreenActuallyLocked(), let skyLight = FaceIDSkyLight.shared {
            skyLight.delegate(window)
            isSkyLightDelegated = true
        }
        updateCursorPolling()
    }

    /// Forces layout and composite now rather than waiting for the next display
    /// cycle. Used so the first frame of a state is rendered before the state that
    /// animates away from it is applied.
    func displaySynchronously() {
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    func hide() {
        guard let window else { return }
        // Un-delegated first: a window left in the elevated space would keep
        // floating above everything after the screen unlocks.
        if isSkyLightDelegated, let skyLight = FaceIDSkyLight.shared {
            skyLight.undelegate(window)
            isSkyLightDelegated = false
        }
        window.orderOut(nil)
        updateCursorPolling()
    }

    /// `key: true` additionally makes the panel key, which is only needed when
    /// something on it has to receive keystrokes.
    func setInteractive(_ interactive: Bool, key: Bool = false) {
        wantsInteractive = interactive
        window?.acceptsKey = interactive
        updateCursorPolling()
        guard interactive, key, let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Forwarded from `FaceIDOverlayView` every time the visible panel's frame
    /// changes.
    func setInteractiveContentRect(_ rect: CGRect?) {
        interactiveContentRect = rect
        updateMousePassthrough()
    }

    var currentGeometry: FaceIDGeometry {
        FaceIDGeometry.preferredScreen().map(FaceIDGeometry.forScreen) ?? FaceIDGeometry.forMainScreen()
    }

    // MARK: - Click-through outside the visible panel

    /// The window's frame is sized for the largest thing it ever shows, plus its
    /// shadow margin, and `ignoresMouseEvents` applies to that whole frame —
    /// macOS decides which window gets a click from its frame, not from what is
    /// drawn, so a transparent margin still swallows clicks. Instead of leaving the
    /// flag off for as long as the overlay is interactive, it is only off while the
    /// cursor is actually over the panel.
    private func updateMousePassthrough() {
        guard let window else { return }
        guard wantsInteractive else {
            window.ignoresMouseEvents = true
            return
        }
        // The lock screen keeps the original whole-window behaviour: nothing there
        // sits under the notch to click on, and hover-to-retry must not regress.
        guard !isSkyLightDelegated, let rect = interactiveContentRect, let hostView = window.contentView else {
            window.ignoresMouseEvents = false
            return
        }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = hostView.convert(windowPoint, from: nil)
        // `rect` is top-down, from SwiftUI; normalise the AppKit point to match.
        let topDown = CGPoint(
            x: local.x,
            y: hostView.isFlipped ? local.y : hostView.bounds.height - local.y
        )
        let isOverPanel = rect
            .insetBy(dx: -Self.interactiveRectOutset, dy: -Self.interactiveRectOutset)
            .contains(topDown)
        if window.ignoresMouseEvents == isOverPanel {
            window.ignoresMouseEvents = !isOverPanel
        }
    }

    /// Polls rather than using mouse-moved events: a window that ignores mouse
    /// events receives none, and a global event monitor doesn't fire for movement
    /// over this app's own windows.
    private func updateCursorPolling() {
        let shouldPoll = wantsInteractive && (window?.isVisible ?? false)
        if shouldPoll, cursorPollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMousePassthrough() }
            }
            RunLoop.main.add(timer, forMode: .common)
            cursorPollTimer = timer
        } else if !shouldPoll {
            cursorPollTimer?.invalidate()
            cursorPollTimer = nil
        }
        updateMousePassthrough()
    }

    private func windowIfNeeded() -> FaceIDOverlayWindow {
        if let window { return window }
        // Never resized afterwards, so a style change mid-session keeps whatever
        // margin the window was created with.
        let size = FaceIDGeometry.windowSize(for: currentGeometry.style)
        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let newWindow = FaceIDOverlayWindow(contentRect: rect)
        newWindow.contentView = contentView
        window = newWindow
        return newWindow
    }

    private func reposition(_ window: FaceIDOverlayWindow) {
        guard let screen = FaceIDGeometry.preferredScreen() else { return }
        let screenFrame = screen.frame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height
        ))
    }

    @objc private func screenParametersChanged() {
        onScreenParametersChanged?()
        guard let window, window.isVisible else { return }
        reposition(window)
    }
}
