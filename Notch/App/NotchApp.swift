import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The notch panel is managed entirely by AppDelegate/NotchWindowController.
        // These scenes provide the menu bar item (quit/settings) and the
        // Settings window.
        MenuBarExtra("Notch", systemImage: "sparkles.rectangle.stack") {
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
