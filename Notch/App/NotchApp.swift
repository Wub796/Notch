import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The notch panel is managed entirely by AppDelegate/NotchWindowController.
        // The only scene we expose is a menu bar item so the agent app can be quit.
        MenuBarExtra("Notch", systemImage: "sparkles.rectangle.stack") {
            Button("About Notch") {
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
