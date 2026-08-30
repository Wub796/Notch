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
    private var swipeMonitor: Any?
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
        setupSwipeTracking()
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
        if let swipeMonitor {
            NSEvent.removeMonitor(swipeMonitor)
            self.swipeMonitor = nil
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
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                self.state.swipeCompensationOffset = 0
            }
            self.reanchorToTrackedScreen()
        }
    }

    private func setupSwipeTracking() {
        swipeMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.scrollWheel, .swipe]
        ) { [weak self] event in
            guard let self else { return }

            if event.type == .scrollWheel {
                if event.phase == .began {
                    if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                        self.state.swipeCompensationOffset = 0
                    }
                } else if event.phase == .changed {
                    if abs(event.scrollingDeltaX) > 0.5 {
                        let delta = event.scrollingDeltaX
                        DispatchQueue.main.async {
                            self.state.swipeCompensationOffset -= delta
                        }
                    }
                } else if event.phase == .ended || event.phase == .cancelled {
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.state.swipeCompensationOffset = 0
                        }
                    }
                }
            } else if event.type == .swipe {
                let deltaX = event.deltaX
                DispatchQueue.main.async {
                    self.state.swipeCompensationOffset -= deltaX * 20
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.state.swipeCompensationOffset = 0
                    }
                }
            }
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
        mouseMoveGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged],
            handler: update
        )
        mouseMoveLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.updateIgnoreMouseEvents()
            return event
        }
        updateIgnoreMouseEvents()
    }

    func updateIgnoreMouseEvents() {
        guard let panel = window, let screen = trackedScreen else { return }

        // Hard guard: while expanded, NEVER ignore mouse events
        if state.mode == .expanded {
            if panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = false
            }
            return
        }

        // Collapsed/peek mode: test live interactive rect in screen coordinates
        let mouseLocation = NSEvent.mouseLocation
        let activeRect = interactiveScreenRect(on: screen)

        let shouldIgnore = !activeRect.contains(mouseLocation)
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }

    private func interactiveScreenRect(on screen: NSScreen) -> NSRect {
        if state.mode == .expanded {
            let width = state.expandedSize.width + NotchSizing.shadowPadding * 2
            let height = state.expandedSize.height + NotchSizing.shadowPadding
            return NSRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - height,
                width: width,
                height: height
            )
        } else {
            let probe = state.hoverProbeSize
            let collapsed = state.collapsedSize
            let width = max(probe.width, collapsed.width) + 16
            let height = max(probe.height, collapsed.height) + 12
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
        window?.orderFrontRegardless()
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
            height = state.expandedSize.height + NotchSizing.shadowPadding
        } else {
            width = max(state.hoverProbeSize.width, state.collapsedSize.width) + 16
            height = max(state.hoverProbeSize.height, state.collapsedSize.height) + 12
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
