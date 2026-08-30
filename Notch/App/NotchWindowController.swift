import AppKit
import SwiftUI

/// Owns the NotchPanel, sizes it to fit the fully expanded UI, and pins it to
/// the top-center of the target screen so the SwiftUI content can grow
/// downward out of the physical notch.
final class NotchWindowController: NSWindowController {
    private let state: NotchState
    private weak var trackedScreen: NSScreen?
    private var spaceObserver: NSObjectProtocol?

    init(state: NotchState, screen: NSScreen) {
        self.state = state
        self.trackedScreen = screen

        let geometry = NotchGeometry(screen: screen)
        state.notchSize = geometry.notchSize

        // Sized once for the largest slab the size sliders allow, plus the
        // shadow margin, so neither opening nor widening ever needs to resize
        // the window mid-animation — the SwiftUI content morphs inside it.
        let window = NotchSizing.windowSize
        let width = max(window.width, geometry.notchSize.width)
        let height = window.height + geometry.notchSize.height

        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        let panel = NotchPanel(contentRect: frame)
        let hostingView = NotchHostingView(
            rootView: NotchContainerView(state: state),
            state: state
        )
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = hostingView

        super.init(window: panel)

        state.onModeChange = { [weak panel] mode in
            guard let panel else { return }
            if mode == .expanded {
                panel.orderFrontRegardless()
            }
        }

        // A panel joined to every Space remains at one global screen position,
        // but its coordinate space can change when Mission Control switches
        // desktops. Re-apply the physical screen's top-center anchor whenever
        // the active Space changes so the panel follows the real notch instead
        // of leaving a stale transparent hit target behind.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reanchorToTrackedScreen()
        }
    }

    deinit {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
    }

    func reanchorToTrackedScreen() {
        guard let panel = window, let screen = trackedScreen else { return }
        let frame = panel.frame
        let origin = NSPoint(
            x: screen.frame.midX - frame.width / 2,
            y: screen.frame.maxY - frame.height
        )
        guard abs(frame.origin.x - origin.x) > 0.5 || abs(frame.origin.y - origin.y) > 0.5 else { return }
        panel.setFrameOrigin(origin)
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
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let width: CGFloat
        let height: CGFloat

        if state.mode == .expanded {
            width = state.expandedSize.width + 60
            height = state.expandedSize.height + 40
        } else {
            width = max(state.hoverProbeSize.width, state.collapsedSize.width) + 40
            height = max(state.hoverProbeSize.height, state.collapsedSize.height) + 24
        }

        let minX = bounds.midX - width / 2
        let maxX = bounds.midX + width / 2
        let minY = bounds.maxY - height
        let maxY = bounds.maxY

        if point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY {
            return super.hitTest(point)
        }

        return nil
    }
}
