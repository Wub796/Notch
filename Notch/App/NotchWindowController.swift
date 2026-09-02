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
    private var collapseResizeWork: DispatchWorkItem?

    init(state: NotchState, screen: NSScreen) {
        self.state = state
        self.trackedScreen = screen

        let geometry = NotchGeometry(screen: screen)
        state.notchSize = geometry.notchSize

        // Size the window dynamically to what is actually needed for the active mode
        let window = NotchSizing.windowSize
        let width = max(window.width, geometry.notchSize.width)
        let height = window.height + geometry.notchSize.height

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
        panel.contentView = hostingView

        super.init(window: panel)

        setupModeChangeObserver()
        setupSpaceObserver()
        setupMouseTracking()
    }

    deinit {
        cleanup()
    }

    func cleanup() {
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
    }

    // MARK: - Window Anchoring

    private func setupModeChangeObserver() {
        state.onModeChange = { [weak self] mode in
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.window else { return }
                if mode == .expanded {
                    panel.ignoresMouseEvents = false
                    panel.orderFrontRegardless()
                } else {
                    self.updateIgnoreMouseEvents()
                }
            }
        }
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
        let window = NotchSizing.windowSize
        let width = max(window.width, state.notchSize.width)
        let height = window.height + state.notchSize.height
        let newOrigin = NSPoint(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height
        )
        guard abs(panel.frame.origin.x - newOrigin.x) > 0.5 || abs(panel.frame.origin.y - newOrigin.y) > 0.5 else { return }
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

        guard panel.ignoresMouseEvents != shouldIgnore else { return }
        panel.ignoresMouseEvents = shouldIgnore

        // The panel stops receiving events the moment it starts ignoring them,
        // so SwiftUI never sees the pointer leave. Say so directly, or the
        // notch stays open behind a pointer that is long gone.
        if shouldIgnore, state.isHovering {
            state.hoverChanged(false)
        }
    }

    private func interactiveScreenRect(on screen: NSScreen) -> NSRect {
        if state.mode == .expanded {
            let width = state.expandedSize.width + NotchSizing.shadowPadding * 2
            // The expanded total (which includes the band the volume/brightness
            // HUD drops into) rather than the bare fitted size, so the dropped
            // bar and its drag handle stay inside the interactive region.
            let height = state.expandedTotalHeight + NotchSizing.shadowPadding
            return NSRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - height,
                width: width,
                height: height
            )
        } else {
            let probe = state.hoverProbeSize
            let collapsed = state.collapsedSize
            let width = max(probe.width, collapsed.width) + 24
            let height = max(probe.height, collapsed.height) + 20
            return NSRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - height,
                width: width,
                height: height
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NotchWindowController does not support NSCoding")
    }

    func showPanel() {
        guard let panel = window else { return }
        panel.orderFrontRegardless()
        // Reassert visibility after lock-screen transitions. The panel is
        // nonactivating, so this does not steal focus from the login UI.
        panel.orderFrontRegardless()
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

        let width: CGFloat
        let height: CGFloat

        if state.mode == .expanded {
            width = state.expandedSize.width + NotchSizing.shadowPadding * 2
            height = state.expandedTotalHeight + NotchSizing.shadowPadding
        } else {
            width = max(state.hoverProbeSize.width, state.collapsedSize.width) + 28
            height = max(state.hoverProbeSize.height, state.collapsedSize.height) + 20
        }

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
