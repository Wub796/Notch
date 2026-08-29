import AppKit
import SwiftUI

/// Owns the NotchPanel, sizes it to fit the fully expanded UI, and pins it to
/// the top-center of the target screen so the SwiftUI content can grow
/// downward out of the physical notch.
final class NotchWindowController: NSWindowController {
    private let state: NotchState

    init(state: NotchState, screen: NSScreen) {
        self.state = state

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
        let hostingView = NotchHostingView(rootView: NotchContainerView(state: state))
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = hostingView

        super.init(window: panel)

        // SwiftUI controls in a borderless non-activating panel only fire
        // reliably once the panel is key (highlighting without firing is a
        // known macOS behavior). Becoming key here does not activate the app
        // or steal focus — it's the standard popover model.
        state.onModeChange = { [weak panel] mode in
            guard let panel else { return }
            if mode == .expanded {
                panel.makeKey()
            } else {
                panel.resignKey()
            }
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

/// Delivers the first click straight to SwiftUI instead of consuming it for
/// window activation, so controls respond on the very first click in the
/// panel.
final class NotchHostingView: NSHostingView<NotchContainerView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
