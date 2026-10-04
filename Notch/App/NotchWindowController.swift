import AppKit
import Observation
import SwiftUI

/// Owns the NotchPanel, dynamically sizes it to fit the active UI mode, and pins
/// it to the top-center of the target screen so clicks outside the notch pass
/// directly through to underlying applications.
final class NotchWindowController: NSWindowController {
    private let state: NotchState
    private weak var trackedScreen: NSScreen?
    private var trackedDisplayID: CGDirectDisplayID?
    /// Screen query-backed geometry, cached until display parameters change.
    private var trackedNotchCenterX: CGFloat = 0
    private var observesFaceIDOverlayPhase = true
    private var isFaceIDOverlayActive = false
    private var shouldShowPanelAfterFaceID = false
    private var spaceObserver: NSObjectProtocol?
    private var mouseMoveGlobalMonitor: Any?
    private var mouseMoveLocalMonitor: Any?
    private var cursorTrackingTimer: Timer?
    /// The collapsed window size last asked for, so the 60Hz cursor poll does
    /// not re-arm the deferred shrink on every tick. See `updateIgnoreMouseEvents`.
    private var lastCollapsedWindowSize: CGSize?
    private var screenParametersObserver: NSObjectProtocol?
    private var collapseResizeWork: DispatchWorkItem?
    private var pendingCollapseFrame: NSRect?
    private var collapseResizeGeneration: UInt64 = 0
    private var settleGeneration: UInt64 = 0
    /// True only while this controller is applying a frame of its own, so the
    /// window delegate can tell our sizing apart from anything else that moves
    /// or resizes the panel. See `repairFrameIfDrifted`.
    private var isApplyingFrame = false

    init(state: NotchState, screen: NSScreen) {
        self.state = state
        self.trackedScreen = screen
        trackedDisplayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID

        let geometry = NotchGeometry(screen: screen)
        trackedNotchCenterX = geometry.notchCenterX
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
            x: geometry.notchCenterX - width / 2,
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
        panel.delegate = self

        setupModeChangeObserver()
        setupSpaceObserver()
        setupScreenParametersObserver()
        setupMouseTracking()
        syncWindowSize()
        observeFaceIDOverlayPhase()
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        observesFaceIDOverlayPhase = false
        // Release the state's hook on this controller. A replaced controller
        // (a display change rebuilds one) otherwise stays reachable through it
        // until the next one happens to overwrite the same slot.
        state.onModeChange = nil
        state.onWillExpand = nil
        state.onWillShowTab = nil
        cancelPendingShrink()
        settleWork?.cancel()
        settleWork = nil
        settleGeneration &+= 1
        isWindowSettling = false
        window?.delegate = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
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
            self?.growWindow(for: nil)
        }
        state.onWillShowTab = { [weak self] tab in
            self?.growWindow(for: tab)
        }
        state.onModeChange = { [weak self] mode in
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.window else { return }
                if mode == .expanded {
                    panel.ignoresMouseEvents = false
                    self.orderPanelFrontIfAllowed(panel)
                } else {
                    self.updateIgnoreMouseEvents()
                }
                self.syncWindowSize()
                self.syncCursorTracking()
            }
        }
    }

    /// Tracks only active Face ID scan/resolve animations; the armed idle overlay
    /// is `.closed` and should not hide the app's normal notch panel.
    private func observeFaceIDOverlayPhase() {
        guard observesFaceIDOverlayPhase else { return }
        withObservationTracking {
            _ = FaceIDOverlayController.shared.phase
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeFaceIDOverlayPhase()
            }
        }
        setFaceIDOverlayActive(FaceIDOverlayController.shared.phase != .closed)
    }

    private func setFaceIDOverlayActive(_ active: Bool) {
        guard active != isFaceIDOverlayActive else { return }
        isFaceIDOverlayActive = active
        guard let panel = window else { return }

        if active {
            shouldShowPanelAfterFaceID = panel.isVisible
            panel.orderOut(nil)
        } else {
            let shouldShow = shouldShowPanelAfterFaceID
            shouldShowPanelAfterFaceID = false
            if shouldShow {
                panel.orderFrontRegardless()
            }
        }
    }

    /// Defers any request to front the app panel until Face ID finishes resolving.
    private func orderPanelFrontIfAllowed(_ panel: NSWindow) {
        guard !isFaceIDOverlayActive else {
            shouldShowPanelAfterFaceID = true
            panel.orderOut(nil)
            return
        }
        panel.orderFrontRegardless()
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

        // Same target: do not cancel/re-arm an outstanding deferred shrink.
        // The cursor probe runs repeatedly, and doing that at every poll used
        // to keep the open panel around indefinitely.
        let targetFrame = roundedWindowFrame(size, on: screen)
        if panel.frame == targetFrame {
            cancelPendingShrink()
            return
        }
        if pendingCollapseFrame == targetFrame { return }

        let grows = size.width > panel.frame.width || size.height > panel.frame.height
        guard !grows else {
            cancelPendingShrink()
            setWindowFrame(size, on: screen)
            return
        }
        // `onWillExpand` and `onWillShowTab` grow synchronously before the
        // corresponding state mutation; that is intentional, so they must not
        // be vetoed against the old mode's size here.
        guard state.mode == .expanded else {
            let currentTarget = collapsedWindowSize()
            guard abs(currentTarget.width - size.width) <= 0.5,
                  abs(currentTarget.height - size.height) <= 0.5
            else {
                cancelPendingShrink()
                return
            }
            scheduleShrink(to: size, on: screen)
            return
        }
        let currentTarget = expandedWindowSize()
        guard abs(currentTarget.width - size.width) <= 0.5,
              abs(currentTarget.height - size.height) <= 0.5
        else {
            cancelPendingShrink()
            return
        }
        scheduleShrink(to: size, on: screen)
    }

    private func scheduleShrink(to size: CGSize, on screen: NSScreen) {
        let targetFrame = roundedWindowFrame(size, on: screen)
        guard pendingCollapseFrame != targetFrame else { return }
        cancelPendingShrink()
        pendingCollapseFrame = targetFrame
        let settleGeneration = self.settleGeneration
        let workGeneration = collapseResizeGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.collapseResizeGeneration == workGeneration,
                  self.pendingCollapseFrame == targetFrame
            else { return }
            guard let screen = self.trackedScreen else {
                self.cancelPendingShrink()
                return
            }

            let canApplyScheduledShrink = self.settleGeneration == settleGeneration
                && !self.isWindowSettling
            self.pendingCollapseFrame = nil
            self.collapseResizeWork = nil
            // Re-derive: the mode may have changed again while waiting.
            let current = self.state.mode == .expanded
                ? self.expandedWindowSize()
                : self.collapsedWindowSize()
            if canApplyScheduledShrink {
                self.setWindowFrame(current, on: screen)
            } else {
                // A newer frame is still settling, or settled after this work
                // was queued. Re-enter the sizing path so it can grow now or
                // schedule a fresh shrink against the latest settle generation.
                self.apply(windowSize: current, on: screen)
            }
        }
        collapseResizeWork = work
        // The same settle the hover probe waits for before it will open the
        // notch again, so the window can never shrink while the slab is still
        // animating inside it — nor lag behind a notch that has finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchAnimations.closeSettle, execute: work)
    }

    private func cancelPendingShrink() {
        collapseResizeGeneration &+= 1
        collapseResizeWork?.cancel()
        collapseResizeWork = nil
        pendingCollapseFrame = nil
    }

    private func setWindowFrame(_ size: CGSize, on screen: NSScreen) {
        guard let panel = window else { return }
        let frame = roundedWindowFrame(size, on: screen)
        guard panel.frame != frame else { return }
        isApplyingFrame = true
        panel.setFrame(frame, display: true)
        isApplyingFrame = false
        markWindowSettling()
    }

    private func roundedWindowFrame(_ size: CGSize, on screen: NSScreen) -> NSRect {
        NSRect(
            x: (trackedNotchCenterX - size.width / 2).rounded(),
            y: (screen.frame.maxY - size.height).rounded(),
            width: size.width.rounded(),
            height: size.height.rounded()
        )
    }

    /// True from the moment a frame is applied until the size animation it began
    /// has had time to land.
    ///
    /// A window animating between two sizes is *between* two sizes on purpose,
    /// and measuring it against the final target on every resize notification
    /// turns that animation into a loop: the repair re-applies the final frame,
    /// the animation restarts, it lands mid-way again — and each application
    /// marks the window as needing another layout pass while the previous one is
    /// still running. AppKit allows one pass per view in the window and then
    /// raises `NSGenericException`, which is uncaught: the app dies. Growing from
    /// the media page's fitted height to the audio slab's was enough to do it.
    ///
    /// This does not weaken the repair, it defers it: the settle itself re-runs
    /// the check once the animation is over, outside any layout pass, so a frame
    /// the window server moved is still corrected — just not mid-flight.
    private var isWindowSettling = false
    private var settleWork: DispatchWorkItem?

    private func markWindowSettling() {
        settleWork?.cancel()
        settleGeneration &+= 1
        let generation = settleGeneration
        isWindowSettling = true
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.settleGeneration == generation else { return }
            self.settleWork = nil
            self.isWindowSettling = false
            self.repairFrameIfDrifted()
        }
        settleWork = work
        // The same settle the shrink path waits for, because it is the same
        // animation: `closeSettle` is how long a notch size change takes to
        // finish, and the deferred repair above is the only thing that needs it.
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchAnimations.closeSettle, execute: work)
    }

    /// Puts the panel back on the notch after a frame change this controller
    /// did not ask for.
    ///
    /// Every path in here re-centres when it sizes the window, so the anchor
    /// survives on its own — until something outside the controller changes
    /// the frame. A panel at status-bar level, joined to every Space, is moved
    /// and resized by the window server around Space, display and full-screen
    /// transitions, and once that happens nothing here re-derives an origin
    /// until the next resize or a Space change: the notch then sits beside the
    /// hardware cutout and stays there. Watching the window itself closes that
    /// hole, because a frame that moved for *any* reason is repaired the
    /// moment it moves, not only when this code happens to run next.
    private func repairFrameIfDrifted() {
        guard !isApplyingFrame, let panel = window, let screen = trackedScreen else { return }
        // A frame in flight is not a frame that drifted: `isWindowSettling`'s own
        // completion calls this again once the animation has landed.
        guard !isWindowSettling else { return }
        let notchCentre = trackedNotchCenterX
        let offCentre = abs(panel.frame.midX - notchCentre) > 0.5
        let target = state.mode == .expanded ? expandedWindowSize() : collapsedWindowSize()
        let wrongSize = abs(panel.frame.width - target.width) > 0.5
            || abs(panel.frame.height - target.height) > 0.5
        guard offCentre || wrongSize else { return }
        // Re-anchor at whatever size the window currently is first, so a pure
        // move is corrected on the spot instead of after the shrink settle.
        if offCentre {
            setWindowFrame(panel.frame.size, on: screen)
        }
        if wrongSize {
            apply(windowSize: target, on: screen)
        }
    }

    /// Grows the window, synchronously, to hold the open slab for `tab` (the
    /// showing tab when nil). Never shrinks: a window still larger from an
    /// earlier screen is shrunk by `apply` once things settle.
    private func growWindow(for tab: NotchTab?) {
        guard let panel = window, let screen = trackedScreen else { return }
        cancelPendingShrink()
        let target = expandedWindowSize(for: tab)
        setWindowFrame(
            CGSize(
                width: max(target.width, panel.frame.width),
                height: max(target.height, panel.frame.height)
            ),
            on: screen
        )
    }

    /// The open slab plus its shadow margin, capped to the screen — for the
    /// showing tab, or for one about to be shown.
    private func expandedWindowSize(for tab: NotchTab? = nil) -> CGSize {
        let tab = tab ?? state.tab
        let slab = state.expandedSize(for: tab)
        let width = min(
            slab.width + NotchSizing.shadowPadding * 2,
            trackedScreen?.frame.width ?? slab.width
        )
        return CGSize(
            width: width,
            height: state.expandedTotalHeight(for: tab) + NotchSizing.shadowPadding * 2
        )
    }

    /// The closed pill as it is *drawn* — the notch, its wings, the room the
    /// hover grow pads into, and whatever activity is dropped beneath it —
    /// plus the shadow margin.
    ///
    /// Deliberately not the interactive region. That is the notch alone (see
    /// `NotchInteractiveRegion`), and sizing the window to it clipped the
    /// pill: the wings were painted outside the window and the notch read as
    /// the whole black shape, off-centre against the hardware. The window has
    /// to hold what is painted; the interactive region decides only what the
    /// pointer can reach.
    private func collapsedWindowSize() -> CGSize {
        let drawn = state.collapsedSize
        let region = NotchInteractiveRegion.size(for: state)
        return CGSize(
            width: max(drawn.width + state.hoverExpansion * 2, region.width)
                + NotchSizing.shadowPadding * 2,
            height: max(drawn.height, region.height) + NotchSizing.shadowPadding * 2
        )
    }

    private func setupScreenParametersObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Safe-area and auxiliary menu-bar areas can change without the
            // controller being rebuilt. Refresh on the notification itself so
            // the hit target follows a display/resolution change immediately.
            self?.refreshNotchGeometry()
        }
    }

    private func refreshNotchGeometry() {
        guard let screen = trackedScreen else { return }
        let geometry = NotchGeometry(screen: screen)
        trackedNotchCenterX = geometry.notchCenterX
        state.notchSize = geometry.notchSize
        syncWindowSize()
        reanchorToTrackedScreen()
        updateIgnoreMouseEvents()
    }

    /// Reuses the live panel when a wake or display-parameter notification
    /// refers to the same physical display. Tearing down and rebuilding the
    /// hosting view on every wake interrupts SwiftUI's shape animation and
    /// can leave the slab as a flat rectangle until the next state change.
    func refreshIfAttached(to screen: NSScreen) -> Bool {
        guard let trackedDisplayID,
              let requestedID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              trackedDisplayID == requestedID
        else { return false }

        self.trackedScreen = screen
        refreshNotchGeometry()
        return true
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
            x: (trackedNotchCenterX - size.width / 2).rounded(),
            y: (screen.frame.maxY - size.height).rounded()
        )
        guard abs(panel.frame.origin.x - newOrigin.x) > 0.5
            || abs(panel.frame.origin.y - newOrigin.y) > 0.5
        else { return }
        panel.setFrameOrigin(newOrigin)
    }

    // MARK: - Pointer-Driven Click-Through (ignoresMouseEvents)

    private func setupMouseTracking() {
        let update: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            self.updateIgnoreMouseEvents()
            self.handleDirectNotchClick(event)
        }
        // Only the *global* monitor carries the click fallback: it sees presses
        // that were delivered to another application, which is exactly the
        // dropped-click case. Events delivered to this app (a local monitor)
        // already reached the panel's own tap gesture, and opening the notch
        // from a click that landed in the settings window would be wrong.
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
        // low-cost cadence in both modes; this also prevents a stale
        // `ignoresMouseEvents` value from making the hover probe unreachable.
        syncCursorTracking()
    }

    /// Polls the cursor as a fallback when AppKit does not deliver a move
    /// event. Keep this running while expanded too: the expanded hover callback
    /// intentionally ignores SwiftUI's unreliable exit reports during layout,
    /// so the screen-coordinate check below must keep sampling to notice a real
    /// exit even when a global event monitor is unavailable.
    private func syncCursorTracking() {
        guard cursorTrackingTimer == nil else { return }
        // Event monitors handle ordinary movement immediately. A 30Hz poll is
        // only the fallback for systems that do not deliver mouse-moved events;
        // 60Hz needlessly repeated screen-geometry and activity checks while idle.
        cursorTrackingTimer = Timer.scheduledRepeating(every: 1.0 / 30.0) { [weak self] in
            self?.updateIgnoreMouseEvents()
        }
    }

    private func handleDirectNotchClick(_ event: NSEvent) {
        guard event.type == .leftMouseDown,
              state.mode != .expanded,
              let screen = trackedScreen,
              probeScreenRect(on: screen).contains(NSEvent.mouseLocation)
        else { return }
        // A click that reached another application while the cursor was inside
        // the notch: the panel was still ignoring the mouse on the preceding
        // sample, so AppKit handed the press straight past it. Without this the
        // first click on a freshly-reached notch is swallowed. `handleTap`
        // treats this as the same intentional pin-and-open as the panel tap;
        // the region is the same notch rectangle, so this can only ever open the
        // notch from over the notch.
        state.handleTap()
    }

    func updateIgnoreMouseEvents() {
        guard let panel = window, let screen = trackedScreen else { return }

        // Keep the collapsed panel's frame in lockstep with live notch
        // adjustments before deciding whether it can receive the pointer.
        // This runs at the fallback cursor-probe cadence, so
        // a display or size change never leaves a stale dead zone behind.
        if state.mode != .expanded {
            // Only when the target itself moved. The size is compared against
            // the last request rather than the live frame while a shrink waits
            // for the close animation to settle.
            let target = collapsedWindowSize()
            if lastCollapsedWindowSize != target {
                lastCollapsedWindowSize = target
                apply(windowSize: target, on: screen)
            } else if let pendingCollapseFrame,
                      pendingCollapseFrame != roundedWindowFrame(target, on: screen) {
                cancelPendingShrink()
            }
        }

        // Keep the panel interactive only over its active region. In expanded
        // mode this is the slab; while collapsed it is the visible pill and
        // hover target.
        let pointer = NSEvent.mouseLocation
        // The interactive region is always contained within the window frame.
        // Most movement events happen elsewhere on screen, so skip rebuilding
        // the (mode- and content-dependent) exact rect unless the cursor is in
        // the panel's small bounding box. A drag keeps hit-testing enabled.
        let dragging = NSEvent.pressedMouseButtons != 0
        let pointerInside = !dragging && panel.frame.contains(pointer)
            && interactiveScreenRect(on: screen).contains(pointer)

        // While a button is held anywhere, stay interactive: a file dragged
        // from Finder arrives as a dragging session rather than as mouse-moved
        // events, and a window that ignores the mouse is not a drop target.
        let shouldIgnore = !pointerInside && !dragging

        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }

        if state.mode == .expanded {
            if let pendingCollapseFrame,
               pendingCollapseFrame != roundedWindowFrame(expandedWindowSize(), on: screen) {
                cancelPendingShrink()
            }
            // Keep hover latched while the cursor is over the visible expanded
            // slab. The top overshoot band bridges the shared menu-bar clamp;
            // the sides and lower edge still end at the visible slab boundary.
            if activeExpandedHoverRect(on: screen).contains(pointer) {
                if !state.isHovering { state.hoverChanged(true) }
            } else if state.isHovering {
                state.hoverChanged(false)
            }
            return
        }

        // Hover is decided here on both sides of the same rectangle, rather
        // than entered here and left to SwiftUI to exit. Expanded mode exits
        // above; only collapsed hover needs to build the activity probe.
        //
        // Both directions are needed because the panel stops receiving events
        // the moment it starts ignoring them: SwiftUI never sees the pointer
        // leave, so an exit SwiftUI had to report is an exit that never
        // arrives. But the exit used to be tied to that switch — fired only
        // when `ignoresMouseEvents` flipped — and the interactive region is
        // deliberately wider than the probe whenever a dropped row is a drag
        // target (see `NotchInteractiveRegion`). A pointer that left the notch
        // for that row never left the region, so nothing flipped and the hover
        // stayed latched: the notch then peeked, and after the open delay
        // opened itself, under a pointer that was sitting on the HUD bar
        // — which is exactly the row that exists to be dragged without the
        // panel moving. So the exit is tested against the probe itself.
        //
        // One rect, read as it is now: idle it is the entry edge, and hovered
        // it has grown (see `hoverProbeSize`), so the two edges differ and a
        // cursor resting on the pill's boundary cannot blink the peek.
        let probeRect = probeScreenRect(on: screen)
        // Scoped to the probe, never the wider interactive area: the notch
        // must not peek just because the cursor is near it.
        if probeRect.contains(pointer) {
            if !state.isHovering { state.hoverChanged(true) }
        } else if state.isHovering {
            state.hoverChanged(false)
        }
    }

    /// The hover probe's screen rect: centered on the slab and anchored to the
    /// top of the screen, exactly where the SwiftUI probe view in
    /// NotchContainerView is drawn — plus the overshoot band above it.
    ///
    /// It is the closed pill's hover target: the entry edge, and once hovering,
    /// the exit edge as well, because it is grown by the same amount the probe
    /// view is (see `hoverProbeSize`). Both edges read this one rect, so the
    /// growth cannot open a gap between them.
    ///
    /// The band above the top edge is the whole point of the last few lines,
    /// and it costs nothing: the pointer clamped at that edge is exactly the
    /// overshoot the probe used to miss, and the SwiftUI probe view cannot
    /// reach above its own window, so this is the one place the region can be
    /// made to include it. Both paths that latch hover from here — the cursor
    /// poll and the global click monitor — read this rect, which is why a
    /// fast flick up under the notch opens it even though neither AppKit nor
    /// SwiftUI ever delivers that pointer position to the panel.
    private func probeScreenRect(on screen: NSScreen) -> NSRect {
        let probe = state.hoverProbeSize
        return NSRect(
            x: trackedNotchCenterX - probe.width / 2,
            y: screen.frame.maxY - probe.height,
            width: probe.width,
            height: probe.height + NotchSizing.hoverOvershootGrace
        )
    }

    private func interactiveScreenRect(on screen: NSScreen) -> NSRect {
        let size = NotchInteractiveRegion.size(for: state)
        return NSRect(
            x: trackedNotchCenterX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Pointer zone that keeps an expanded panel open. Its sides and lower edge
    /// match the visible slab exactly. The only extension is the same top-edge
    /// overshoot accepted by the collapsed probe: macOS clamps a cursor aimed
    /// at the hardware notch to the screen boundary, just above the drawn slab.
    /// Without matching that allowance here, the panel closes at the clamp,
    /// then the collapsed probe immediately reopens it in an endless loop.
    private func activeExpandedHoverRect(on screen: NSScreen) -> NSRect {
        let slab = state.expandedSize
        let height = state.expandedTotalHeight
        return NSRect(
            x: trackedNotchCenterX - slab.width / 2,
            y: screen.frame.maxY - height,
            width: slab.width,
            height: height + NotchSizing.hoverOvershootGrace
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
        guard let panel = window else { return }
        orderPanelFrontIfAllowed(panel)
    }
}

/// Both halves matter: a window server transition can resize the panel without
/// moving it, or move it without resizing, and either one alone leaves the notch
/// beside the hardware cutout. Corrected rather than fought over: see
/// `repairFrameIfDrifted`.
extension NotchWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        repairFrameIfDrifted()
    }

    func windowDidMove(_ notification: Notification) {
        repairFrameIfDrifted()
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
        // Hover/click hit testing is the closed pill as it is drawn: the notch,
        // its wings and any dropped row — the tolerance bands included. Those
        // wings are painted black, so taking the mouse over them costs nothing
        // the menu bar did not already give up, and leaving them out made the
        // drawn pill answer only in its middle.
        //
        // A dropped HUD/file row is the one difference: it stays a deliberate
        // drag target — the full drawn shape takes the mouse — while the hover
        // probe stays the notch's height there, so aiming a drag at that row can
        // never make the panel open out from under itself.
        if state.collapsedActivityIsInteractive {
            let collapsed = state.collapsedSize
            return CGSize(width: collapsed.width, height: collapsed.height)
        }
        return state.hoverProbeSize
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
        #if DEBUG
        // The click path, traced. A click in a window that is not key is either
        // delivered to the view or spent bringing the window forward, and the
        // one place to tell those apart is here — this override is only ever
        // asked when AppKit is deciding exactly that.
        print("[Notch] click: AppKit asked for first mouse")
        #endif
        return true
    }

    /// Second half of the same trace: if this prints, the event survived hit
    /// testing and reached the hosting view, so anything that still does not
    /// happen belongs to the SwiftUI side or to the action itself.
    override func mouseDown(with event: NSEvent) {
        #if DEBUG
        print("[Notch] click: hosting view got mouseDown at "
            + "\(Int(event.locationInWindow.x)),\(Int(event.locationInWindow.y))")
        #endif
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit hands hitTest a point in the *superview's* coordinate space
        // (unlike UIKit), so it has to be converted before it can be compared
        // against this view's bounds.
        let localPoint = superview != nil ? convert(point, from: superview) : point
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // The same exact region the panel uses to decide whether to take the
        // mouse at all. Keeping this as one measured rectangle prevents a
        // transparent band from claiming clicks around the hardware notch.
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
