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

/// Activation for the app's ordinary windows — Settings and Clipboard.
///
/// Notch runs as an accessory app with no Dock icon, so a real window needs the
/// app to become a regular one while it is open, and to go back once the last
/// such window closes. Each window flipping the policy on its own would hide
/// the Dock icon — and push to the back — a window that was still open.
enum AppWindows {
    static func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Re-asserted a turn later: the policy change only takes effect on the
        // next pass of the run loop, and without this the window can come up
        // behind the app it was opened from.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func didClose(_ closing: NSWindow?) {
        closing?.orderOut(nil)
        let anotherOpen = NSApp.windows.contains { window in
            window !== closing && window.isVisible && window.styleMask.contains(.titled)
        }
        if !anotherOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        let size = SettingsMetrics.windowSize
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        // The chrome itself is Glance's (`WindowConfiguringView`, attached by
        // `SettingsView`): transparent titlebar, hidden title, an item-less
        // `.unified` toolbar for the traffic-light band and the native corner
        // radius, and a fixed frame. Only what has to be true before the first
        // render is set here.
        window.title = "Notch Settings"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("NotchSettingsWindow")
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

    /// Shows the window and gives it key focus so all controls respond
    /// immediately.
    ///
    /// The deferred second `makeKeyAndOrderFront` is deliberate and not a
    /// duplicate: the activation policy change above only takes effect on the
    /// next pass of the run loop, and without re-asserting afterwards the
    /// window can come up behind the app it was opened from.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if window?.isVisible != true {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        AppWindows.didClose(window)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
