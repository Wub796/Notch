import AppKit
import SwiftUI

/// Opens the Settings scene from anywhere in the app.
///
/// `@Environment(\.openSettings)` only works inside the SwiftUI scene graph.
/// The notch itself is an `NSHostingView` created by hand in an `NSPanel`, so
/// it sits outside every scene and the environment action there is a no-op —
/// which is why the gear in the notch looked live and did nothing. AppKit's
/// settings selector reaches the same scene from outside it.
enum SettingsLauncher {
    static func open() {
        // A window can only take focus once the app has a real activation
        // policy; see SettingsWindowActivator below for why.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // macOS 14 renamed the selector. Try the current one, then the legacy
        // name, so the gear works across every supported release.
        let selectors = [
            Selector(("showSettingsWindow:")),
            Selector(("showPreferencesWindow:")),
        ]
        for selector in selectors {
            if NSApp.sendAction(selector, to: nil, from: nil) { return }
        }

        // Nothing responded — surface any settings window that already exists
        // rather than leaving the click silently unanswered.
        if let window = NSApp.windows.first(where: { $0.canBecomeKey && !($0 is NotchPanel) }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// Makes the Settings window actually usable in an agent app.
///
/// Notch runs with `.accessory` activation policy so it has no Dock icon.
/// An app in that policy has no reliable way to bring itself forward, so the
/// Settings window can open unfocused behind the frontmost app: every control
/// renders, and clicks land somewhere else. Switching to `.regular` while
/// Settings is open gives it a real key window (and a menu bar), and the
/// policy is restored on close so the Dock icon does not linger.
struct SettingsWindowActivator: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { Self.activate() }
            .onDisappear { Self.deactivate() }
    }

    private static func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // The window exists by the next runloop turn; the notch panel is
        // excluded so focus lands on Settings itself.
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && !($0 is NotchPanel) && $0.canBecomeKey
            }) else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private static func deactivate() {
        // Only drop back to accessory once no ordinary window is left,
        // otherwise closing one settings sheet would hide another window.
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains {
                $0.isVisible && !($0 is NotchPanel) && $0.canBecomeKey
            }
            guard !hasVisibleWindow else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension View {
    /// Apply to the root of a window that needs real keyboard/mouse focus.
    func activatesAsRegularApp() -> some View {
        modifier(SettingsWindowActivator())
    }
}
