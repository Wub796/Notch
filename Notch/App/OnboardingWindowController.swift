import AppKit
import SwiftUI

/// First-launch welcome window: introduces the notch, its gestures, and the
/// optional permissions. Shown once; closing it in any way completes
/// onboarding.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onFinish: () -> Void
    private var didFinish = false

    init(state: NotchState, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.06, alpha: 1)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        super.init(window: window)
        window.delegate = self

        window.contentView = NSHostingView(
            rootView: OnboardingView(state: state) { [weak self] in
                self?.finish()
            }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OnboardingWindowController does not support NSCoding")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        completeIfNeeded()
    }

    private func finish() {
        window?.close()
        completeIfNeeded()
    }

    private func completeIfNeeded() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }
}
