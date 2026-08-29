import AppKit
import SwiftUI

/// Makes the Settings window actually usable in an agent app.
///
/// Notch runs with `.accessory` activation policy so it has no Dock icon.
/// A side effect is that its windows never become key on their own, which
/// leaves every control in Settings visibly present but unresponsive — the
/// window renders, and clicks go nowhere. Switching to `.regular` while
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
