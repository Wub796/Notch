import AppKit
import SwiftUI

/// Hosts Settings in a real `NSWindow`.
///
/// SwiftUI's `Settings` scene does not work reliably in an `LSUIElement` app:
/// `openSettings()` is only available inside the scene graph (the notch is an
/// `NSHostingView` in a panel, so it is not), and the scene's window opens
/// without focus behind the frontmost app — which is exactly the symptom of
/// the Dock icon appearing with no visible window. boring.notch hit the same
/// wall and solved it the same way, with its own `SettingsWindowController`.
///
/// Owning the window also means the activation policy can be tied to the
/// window's real lifetime rather than to a SwiftUI `onAppear`/`onDisappear`
/// pair that may never fire.
final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SettingsHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = "Notch Settings"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("NotchSettingsWindow")
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.level = .normal
        window.hidesOnDeactivate = false
        window.contentView = SettingsHostingView(rootView: SettingsView())
        window.center()
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController does not support NSCoding")
    }

    /// Shows the window smoothly and gives it key focus so all controls respond immediately.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if window?.isVisible != true {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
            self?.window?.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
