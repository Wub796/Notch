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
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = "Notch Settings"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("NotchSettingsWindow")
        window.appearance = NSAppearance(named: .darkAqua)
        // A managed window that takes part in cycling, unlike the notch panel.
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController does not support NSCoding")
    }

    /// Shows the window and gives it focus.
    ///
    /// The policy change has to come first: an `.accessory` app cannot bring
    /// its own window forward, so ordering the window in before switching to
    /// `.regular` is what leaves it invisible behind everything else.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

        // Activation completes on the next runloop turn; without this the
        // window is frontmost but not key, so its controls stay unresponsive.
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Drops the Dock icon again once Settings is gone.
    private func relinquishFocus() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
