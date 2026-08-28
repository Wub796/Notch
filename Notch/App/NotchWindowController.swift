import AppKit
import SwiftUI

/// Owns the NotchPanel, sizes it to fit the fully expanded UI, and pins it to
/// the top-center of the target screen so the SwiftUI content can grow
/// downward out of the physical notch.
final class NotchWindowController: NSWindowController {
    private let state: NotchState

    /// Extra transparent margin around the expanded shape so shadows and
    /// spring overshoot are never clipped by the panel bounds.
    private static let overshootMargin: CGFloat = 40

    init(state: NotchState, screen: NSScreen) {
        self.state = state

        let geometry = NotchGeometry(screen: screen)
        state.notchSize = geometry.notchSize

        let width = max(state.expandedSize.width, geometry.notchSize.width) + Self.overshootMargin * 2
        let height = state.expandedSize.height + geometry.notchSize.height + Self.overshootMargin

        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        let panel = NotchPanel(contentRect: frame)
        let hostingView = NSHostingView(rootView: NotchContainerView(state: state))
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = hostingView

        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NotchWindowController does not support NSCoding")
    }

    func showPanel() {
        window?.orderFrontRegardless()
    }
}
