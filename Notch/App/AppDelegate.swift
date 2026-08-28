import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Root app state; exposed so the menu bar scene can drive commands
    /// (open notch, play/pause, keep awake) against the same instance.
    let state = NotchState()

    private var windowController: NotchWindowController?
    private var scrollMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        attachToBestScreen()
        installScrollGesture()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Two-finger scroll over the notch opens it; scrolling back up over the
    /// open panel closes it (DynamicNotch-style interaction). Scroll events
    /// route to the window under the pointer, so a local monitor is enough.
    private func installScrollGesture() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  NotchSettings.shared.scrollToExpand,
                  let panel = self.windowController?.window,
                  event.window === panel
            else { return event }

            // Direction-agnostic: the sign of scrollingDeltaY flips with the
            // user's natural-scrolling preference, so any decisive scroll
            // over the closed notch opens it.
            if abs(event.scrollingDeltaY) > 8, self.state.mode != .expanded {
                self.state.expand()
            }
            return event
        }
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
