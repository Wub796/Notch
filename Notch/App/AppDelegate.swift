import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: NotchState!
    private var windowController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        state = NotchState()
        attachToBestScreen()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Rebuilds the panel on the screen that physically has a notch,
    /// falling back to the main display on non-notched Macs.
    private func attachToBestScreen() {
        guard let screen = NotchGeometry.preferredScreen else { return }
        windowController?.close()
        windowController = NotchWindowController(state: state, screen: screen)
        windowController?.showPanel()
    }

    @objc private func screenParametersDidChange() {
        // Display was plugged/unplugged or resolution changed: re-anchor the panel.
        attachToBestScreen()
    }
}
