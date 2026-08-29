import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Root app state; exposed so the menu bar scene can drive commands
    /// (open notch, play/pause, keep awake) against the same instance.
    let state = NotchState()

    private var windowController: NotchWindowController?
    private var onboardingController: OnboardingWindowController?
    private var scrollMonitor: Any?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        attachToBestScreen()
        installScrollGesture()
        installOutsideClickMonitor()
        installHotKey()
        NotchSettings.shared.onScreenPreferenceChanged = { [weak self] in
            self?.attachToBestScreen()
        }
        presentOnboardingIfNeeded()

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

    /// Spotify's consent page redirects the browser to notch://spotify-callback;
    /// the scheme is registered in Info.plist, so the OS delivers it here.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "notch" {
            SpotifyAuth.shared.handleCallback(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }

    /// Rebuilds the panel on the screen that physically has a notch,
    /// falling back to the main display on non-notched Macs.
    private func attachToBestScreen() {
        guard let screen = NotchGeometry.preferredScreen else { return }
        // Never carry an expanded panel across a display change — the new
        // geometry starts from the resting state.
        state.collapse()
        windowController?.close()
        windowController = NotchWindowController(state: state, screen: screen)
        windowController?.showPanel()
    }

    @objc private func screenParametersDidChange() {
        // Display was plugged/unplugged or resolution changed: re-anchor the panel.
        attachToBestScreen()
    }

    /// Two-finger scroll over the notch opens it (DynamicNotch-style
    /// interaction). Scroll events route to the window under the pointer, so
    /// a local monitor is enough.
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

    /// A click anywhere outside the app closes the expanded panel — global
    /// monitors only receive events delivered to other applications, which
    /// is exactly the "outside" we want.
    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.state.mode == .expanded, !self.state.isPinned else { return }
            self.state.collapse()
        }
    }

    /// System-wide shortcut that opens or closes the notch from anywhere.
    private func installHotKey() {
        HotKeyManager.shared.onTrigger = { [weak self] in
            guard let self else { return }
            if self.state.mode == .expanded {
                self.state.collapse()
            } else {
                self.state.expand()
            }
        }
        HotKeyManager.shared.apply(
            HotKeyManager.Shortcut(rawValue: NotchSettings.shared.hotKey) ?? .disabled
        )
    }

    private func presentOnboardingIfNeeded() {
        guard !NotchSettings.shared.hasCompletedOnboarding else { return }
        onboardingController = OnboardingWindowController(state: state) { [weak self] in
            NotchSettings.shared.hasCompletedOnboarding = true
            self?.onboardingController = nil
        }
        onboardingController?.present()
    }
}
