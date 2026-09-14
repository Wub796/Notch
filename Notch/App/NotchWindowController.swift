import AppKit
import SwiftUI

/// Owns the NotchPanel, dynamically sizes it to fit the active UI mode, and pins
/// it to the top-center of the target screen so clicks outside the notch pass
/// directly through to underlying applications.
final class NotchWindowController: NSWindowController {
    private let state: NotchState
    private weak var trackedScreen: NSScreen?
    private var spaceObserver: NSObjectProtocol?
    private var mouseMoveGlobalMonitor: Any?
    private var mouseMoveLocalMonitor: Any?
    private var cursorTrackingTimer: Timer?
    private var collapseResizeWork: DispatchWorkItem?

    init(state: NotchState, screen: NSScreen) {
        self.state = state
        self.trackedScreen = screen

        let geometry = NotchGeometry(screen: screen)
        state.notchSize = geometry.notchSize

        // Open at the closed notch's size. `syncWindowSize()` below keeps it
        // matched to whatever is being drawn from then on — the window used to
        // be built once at the largest slab the sliders allow and never
        // resized, which left a screen-wide interactive window sitting above
        // everything else. See `syncWindowSize`.
        let region = NotchInteractiveRegion.size(for: state)
        let width = max(region.width + NotchSizing.shadowPadding * 2, geometry.notchSize.width)
        let height = region.height + NotchSizing.shadowPadding * 2

        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        let panel = NotchPanel(contentRect: frame, state: state)
        let hostingView = NotchHostingView(
            rootView: NotchContainerView(state: state),
            state: state
        )
        hostingView.autoresizingMask = [.width, .height]
        // The window is sized by hand, to the slab; the hosting view must not
        // also push its content's intrinsic size back onto the window
        // mid-animation.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        super.init(window: panel)

        setupModeChangeObserver()
        setupSpaceObserver()
        setupMouseTracking()
        syncWindowSize()
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        // Release the state's hook on this controller. A replaced controller
        // (a display change rebuilds one) otherwise stays reachable through it
        // until the next one happens to overwrite the same slot.
        state.onModeChange = nil
        state.onWillExpand = nil
        collapseResizeWork?.cancel()
        collapseResizeWork = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        if let mouseMoveGlobalMonitor {
            NSEvent.removeMonitor(mouseMoveGlobalMonitor)
            self.mouseMoveGlobalMonitor = nil
        }
        if let mouseMoveLocalMonitor {
            NSEvent.removeMonitor(mouseMoveLocalMonitor)
            self.mouseMoveLocalMonitor = nil
        }
        cursorTrackingTimer?.invalidate()
        cursorTrackingTimer = nil
    }

    // MARK: - Window Anchoring

    private func setupModeChangeObserver() {
        // Grow first, synchronously, so the opening spring never draws into
        // the closed notch's window. Never shrinks here: a window still large
        // from a previous open is shrunk by `apply` once things settle.
        state.onWillExpand = { [weak self] in
            guard let self, let panel = self.window, let screen = self.trackedScreen else { return }
            self.collapseResizeWork?.cancel()
            self.collapseResizeWork = nil
            let target = self.expandedWindowSize()
            self.setWindowFrame(
                CGSize(
                    width: max(target.width, panel.frame.width),
                    height: max(target.height, panel.frame.height)
                ),
                on: screen
            )
        }
        state.onModeChange = { [weak self] mode in
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.window else { return }
                if mode == .expanded {
                    panel.ignoresMouseEvents = false
                    panel.orderFrontRegardless()
                } else {
                    self.updateIgnoreMouseEvents()
                }
                self.syncWindowSize()
                self.syncCursorTracking()
            }
        }
    }

    // MARK: - Window sizing

    /// Keeps the panel window only as large as the thing it is currently
    /// drawing.
    ///
    /// This matters far more than it looks. `hitTest` returning nil does *not*
    /// pass a click through to what is underneath — only `ignoresMouseEvents`
    /// does. So for every moment the panel is not ignoring the mouse, its
    /// whole window swallows clicks, and the window was built once at the
    /// largest size the sliders allow: ~1492x578, which is 98% of the screen's
    /// width and well over half its height. Any window that big, interactive,
    /// and pinned above everything else is a dead zone over most of the upper
    /// display — and `updateIgnoreMouseEvents` turns interactivity on whenever
    /// a mouse button is held anywhere, which is every click and every drag.
    ///
    /// Sizing the window to the notch bounds the damage to the notch.
    private func syncWindowSize() {
        guard let screen = trackedScreen else { return }
        let target = state.mode == .expanded
            ? expandedWindowSize()
            : collapsedWindowSize()
        apply(windowSize: target, on: screen)
    }

    /// Applies a new window size, growing at once and shrinking only after the
    /// close/resize animation has had time to finish — the slab animates
    /// *inside* the window, so shrinking early clips it mid-flight.
    private func apply(windowSize size: CGSize, on screen: NSScreen) {
        guard let panel = window else { return }
        collapseResizeWork?.cancel()
        collapseResizeWork = nil

        let grows = size.width > panel.frame.width || size.height > panel.frame.height
        guard !grows else {
            setWindowFrame(size, on: screen)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let screen = self.trackedScreen else { return }
            // Re-derive: the mode may have changed again while waiting.
            let current = self.state.mode == .expanded
                ? self.expandedWindowSize()
                : self.collapsedWindowSize()
            self.setWindowFrame(current, on: screen)
        }
        collapseResizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    private func setWindowFrame(_ size: CGSize, on screen: NSScreen) {
        guard let panel = window else { return }
        let frame = NSRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: (screen.frame.maxY - size.height).rounded(),
            width: size.width.rounded(),
            height: size.height.rounded()
        )
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
    }

    /// The open slab plus its shadow margin, capped to the screen.
    private func expandedWindowSize() -> CGSize {
        let width = min(
            state.expandedSize.width + NotchSizing.shadowPadding * 2,
            trackedScreen?.frame.width ?? state.expandedSize.width
        )
        return CGSize(
            width: width,
            height: state.expandedTotalHeight + NotchSizing.shadowPadding * 2
        )
    }

    /// The closed pill, its hover probe, whatever activity is dropped beneath
    /// it, and the slack the interactive region adds — plus the shadow margin.
    private func collapsedWindowSize() -> CGSize {
        let region = NotchInteractiveRegion.size(for: state)
        return CGSize(
            width: region.width + NotchSizing.shadowPadding * 2,
            height: region.height + NotchSizing.shadowPadding * 2
        )
    }

    private func setupSpaceObserver() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reanchorToTrackedScreen()
        }
    }

    func reanchorToTrackedScreen() {
        guard let panel = window, let screen = trackedScreen else { return }
        // Anchor against the window's *current* size — it is resized to match
        // what the notch is drawing, so a fixed size would misplace it.
        let size = panel.frame.size
        let newOrigin = NSPoint(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: (screen.frame.maxY - size.height).rounded()
        )
        guard abs(panel.frame.origin.x - newOrigin.x) > 0.5
            || abs(panel.frame.origin.y - newOrigin.y) > 0.5
        else { return }
        panel.setFrameOrigin(newOrigin)
    }

    // MARK: - Pointer-Driven Click-Through (ignoresMouseEvents)

    private func setupMouseTracking() {
        let update: (NSEvent) -> Void = { [weak self] _ in
            self?.updateIgnoreMouseEvents()
        }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp,
        ]
        mouseMoveGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: update
        )
        mouseMoveLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mask
        ) { [weak self] event in
            self?.updateIgnoreMouseEvents()
            return event
        }
        updateIgnoreMouseEvents()

        // A global monitor does not receive mouse-moved events when the user
        // has disabled mouse-move reporting or when another app owns the
        // event stream. Keep the notch responsive by checking the cursor at a
        // low-cost cadence while it is collapsed; this also prevents a stale
        // `ignoresMouseEvents` value from making the hover probe unreachable.
        syncCursorTracking()
    }

    /// The cursor poll exists only to catch the collapsed notch's hover when
    /// AppKit does not deliver a move event. While the panel is open the
    /// pointer is already inside it and SwiftUI owns hover, so the poll is
    /// pure overhead — and it is not cheap overhead: every tick recomputes
    /// `expandedSize`, which walks the whole per-tab sizing path. Run it while
    /// collapsed, stop it while expanded.
    private func syncCursorTracking() {
        let wantsTracking = state.mode != .expanded
        guard wantsTracking != (cursorTrackingTimer != nil) else { return }

        guard wantsTracking else {
            cursorTrackingTimer?.invalidate()
            cursorTrackingTimer = nil
            return
        }
        // A tight cadence so a cursor flicking up under the notch is still
        // sampled inside the probe — a fast crossing can clear the collapsed
        // target between two slow polls.
        cursorTrackingTimer = Timer.scheduledRepeating(every: 0.05) { [weak self] in
            self?.updateIgnoreMouseEvents()
        }
    }

    func updateIgnoreMouseEvents() {
        guard let panel = window, let screen = trackedScreen else { return }

        // The same test in both modes. Exempting the expanded state meant the
        // whole window took the mouse while the notch was open — and the
        // window is nearly as wide as the screen and ~537pt tall, so opening
        // the notch made the top half of the display dead again. Worse, an
        // outside click could not dismiss it: `hitTest` dropped the click, and
        // AppDelegate's *global* monitor never sees events delivered to this
        // app. `interactiveScreenRect` already returns the slab when expanded,
        // which is exactly the region that should take the mouse.
        let activeRect = interactiveScreenRect(on: screen)
        let pointerInside = activeRect.contains(NSEvent.mouseLocation)

        // While a button is held anywhere, stay interactive: a file dragged
        // from Finder arrives as a dragging session rather than as mouse-moved
        // events, and a window that ignores the mouse is not a drop target.
        let dragging = NSEvent.pressedMouseButtons != 0
        let shouldIgnore = !pointerInside && !dragging

        let didChangeHitTesting = panel.ignoresMouseEvents != shouldIgnore
        if didChangeHitTesting {
            panel.ignoresMouseEvents = shouldIgnore
        }

        // If the cursor is inside the hover probe, keep the state machine fed
        // even when AppKit does not deliver an onHover transition (e.g. the
        // panel only just stopped ignoring events). Scoped to the probe rect,
        // never the wider interactive area: the notch must not peek just
        // because the cursor is near it.
        let probeRect = probeScreenRect(on: screen)
        if probeRect.contains(NSEvent.mouseLocation), state.mode == .collapsed, !state.isHovering {
            state.hoverChanged(true)
        }

        guard didChangeHitTesting else { return }

        // The panel stops receiving events the moment it starts ignoring them,
        // so SwiftUI never sees the pointer leave. Say so directly, or the
        // notch stays open behind a pointer that is long gone.
        if shouldIgnore, state.isHovering {
            state.hoverChanged(false)
        }
    }

    /// The hover probe's screen rect: centered on the slab and anchored to the
    /// top of the screen, exactly where the SwiftUI probe view in
    /// NotchContainerView is drawn. Used to keep the state machine fed while
    /// the cursor rests on the notch.
    private func probeScreenRect(on screen: NSScreen) -> NSRect {
        let probe = state.hoverProbeSize
        return NSRect(
            x: screen.frame.midX - probe.width / 2,
            y: screen.frame.maxY - probe.height,
            width: probe.width,
            height: probe.height
        )
    }

    private func interactiveScreenRect(on screen: NSScreen) -> NSRect {
        let size = NotchInteractiveRegion.size(for: state)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NotchWindowController does not support NSCoding")
    }

    /// Orders the panel in. `orderFrontRegardless` rather than `orderFront`
    /// so it reappears after lock-screen transitions; the panel is
    /// nonactivating, so this does not steal focus from the login UI.
    func showPanel() {
        window?.orderFrontRegardless()
    }
}

/// The panel's interactive region — the area that takes the mouse instead of
/// letting it through to whatever is underneath.
///
/// One definition, used both by `ignoresMouseEvents` (which decides whether
/// the window accepts events at all) and by `NotchHostingView.hitTest` (which
/// decides where inside the window they land). Keeping them in step is the
/// whole point: a hitTest region larger than the ignore region is a band that
/// can never be reached, and a smaller one is a dead strip inside a window
/// that has already claimed the mouse.
enum NotchInteractiveRegion {
    /// Slack around the collapsed pill, so crossing into the notch is
    /// forgiving without making the whole menu bar interactive.
    private static let collapsedSlack = CGSize(width: 24, height: 20)

    static func size(for state: NotchState) -> CGSize {
        if state.mode == .expanded {
            return CGSize(
                width: state.expandedSize.width + NotchSizing.shadowPadding * 2,
                // The expanded *total* (which includes the band the
                // volume/brightness HUD drops into) rather than the bare fitted
                // size, so the dropped bar and its drag handle stay inside.
                height: state.expandedTotalHeight + NotchSizing.shadowPadding
            )
        }
        let probe = state.hoverProbeSize
        let collapsed = state.collapsedSize
        return CGSize(
            width: max(probe.width, collapsed.width) + collapsedSlack.width,
            height: max(probe.height, collapsed.height) + collapsedSlack.height
        )
    }
}

/// Delivers the first click straight to SwiftUI and restricts hit testing
/// strictly to the active notch bounds so transparent areas never block
/// underlying application windows, menu items, or browser tabs.
final class NotchHostingView: NSHostingView<NotchContainerView> {
    private let state: NotchState

    init(rootView: NotchContainerView, state: NotchState) {
        self.state = state
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: NotchContainerView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview != nil ? convert(point, from: superview) : point
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // The same region the panel uses to decide whether to take the mouse
        // at all. These were two separate expressions that disagreed by 4pt on
        // the collapsed width, so the band between them accepted a hit the
        // panel had already decided to ignore.
        let size = NotchInteractiveRegion.size(for: state)
        let width = size.width
        let height = size.height

        let minX = bounds.midX - width / 2
        let maxX = bounds.midX + width / 2

        // NSHostingView on macOS is flipped (isFlipped == true): top is y=0, bottom is y=bounds.height
        let minY: CGFloat
        let maxY: CGFloat
        if isFlipped {
            minY = 0
            maxY = height
        } else {
            minY = bounds.maxY - height
            maxY = bounds.maxY
        }

        if localPoint.x >= minX && localPoint.x <= maxX && localPoint.y >= minY && localPoint.y <= maxY {
            return super.hitTest(point)
        }

        return nil
    }
}
