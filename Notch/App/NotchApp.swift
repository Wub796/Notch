import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The shortcut the user actually chose, so the menu advertises the same
    /// keys the global hotkey is registered on.
    private var toggleShortcut: HotKeyManager.Shortcut {
        HotKeyManager.Shortcut(rawValue: appDelegate.state.settings.hotKey) ?? .disabled
    }

    var body: some Scene {
        // The notch panel is managed entirely by AppDelegate/NotchWindowController,
        // and Settings by SettingsWindowController — SwiftUI's Settings scene
        // opens unfocused behind everything in an LSUIElement app. The menu bar
        // item carries the app's commands (HIG: every action the app offers is
        // reachable from the menu bar).
        MenuBarExtra("Notch", systemImage: "sparkles.rectangle.stack") {
            Button(appDelegate.state.mode == .expanded ? "Close Notch" : "Open Notch") {
                if appDelegate.state.mode == .expanded {
                    appDelegate.state.collapse()
                } else {
                    appDelegate.state.expand()
                }
            }
            .modifier(OptionalShortcut(
                key: toggleShortcut.menuKey,
                modifiers: toggleShortcut.menuModifiers
            ))

            Divider()

            Button(appDelegate.state.media.isPlaying ? "Pause" : "Play") {
                appDelegate.state.media.togglePlayPause()
            }
            .disabled(!appDelegate.state.media.hasTrack)

            Button("Next Track") {
                appDelegate.state.media.nextTrack()
            }
            .disabled(!appDelegate.state.media.hasTrack)

            Button("Previous Track") {
                appDelegate.state.media.previousTrack()
            }
            .disabled(!appDelegate.state.media.hasTrack)

            Divider()

            Toggle("Keep Mac Awake", isOn: Binding(
                get: { appDelegate.state.keepAwake.isActive },
                set: { _ in appDelegate.state.keepAwake.toggle() }
            ))

            Button("AirDrop Shelf Items") {
                appDelegate.state.shelf.airDropAll()
            }
            .disabled(appDelegate.state.shelf.items.isEmpty)

            Divider()

            Button("Start 5-Minute Timer") {
                appDelegate.state.timer.start(minutes: 5)
            }
            .disabled(appDelegate.state.timer.isRunning)

            Button("Cancel Timer") {
                appDelegate.state.timer.cancel()
            }
            .disabled(!appDelegate.state.timer.isRunning)

            Toggle("Eye Break Reminders", isOn: Binding(
                get: { appDelegate.state.eyeBreak.isEnabled },
                set: { appDelegate.state.eyeBreak.setEnabled($0) }
            ))

            Divider()

            Button("Check for Updates…") {
                UpdateController.shared.checkForUpdates()
            }

            Button("Settings…") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",")

            Button("About Notch") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }

            Divider()

            Button("Quit Notch") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}


/// Applies a keyboard shortcut only when there is one to apply — the toggle
/// shortcut can be set to Off, and a menu item should then carry no keys at
/// all rather than a stale default.
private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?
    let modifiers: SwiftUI.EventModifiers

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}
