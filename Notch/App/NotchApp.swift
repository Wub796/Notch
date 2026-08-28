import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The notch panel is managed entirely by AppDelegate/NotchWindowController.
        // The menu bar item carries the app's commands (HIG: every action the
        // app offers is reachable from the menu bar), and the Settings scene
        // provides the preferences window.
        MenuBarExtra("Notch", systemImage: "sparkles.rectangle.stack") {
            Button(appDelegate.state.mode == .expanded ? "Close Notch" : "Open Notch") {
                if appDelegate.state.mode == .expanded {
                    appDelegate.state.collapse()
                } else {
                    appDelegate.state.expand()
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button(appDelegate.state.media.isPlaying ? "Pause" : "Play") {
                appDelegate.state.media.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
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

            SettingsLink {
                Text("Settings…")
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

        Settings {
            SettingsView()
        }
    }
}
