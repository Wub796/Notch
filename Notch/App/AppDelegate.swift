import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Root app state; exposed so the menu bar scene can drive commands
    /// (open notch, play/pause, keep awake) against the same instance.
    let state = NotchState()

    private var windowController: NotchWindowController?
    private var onboardingController: OnboardingWindowController?
    private var scrollMonitor: Any?
    private var outsideClickMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenChangeWork: DispatchWorkItem?

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
        installWakeObservers()
    }

    /// Waking is not a quiet event for this app: CoreAudio re-enumerates its
    /// devices, so listeners attached before the sleep are watching objects
    /// that no longer exist, and the weather is as old as the sleep was.
    /// Without this the notch comes back looking alive and quietly isn't.
    private func installWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.state.refreshAfterWake()
                self?.scheduleScreenReattach()
            },
            center.addObserver(
                forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.scheduleScreenReattach()
            },
        ]
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
        screenChangeWork?.cancel()

        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
        NotificationCenter.default.removeObserver(self)

        HotKeyManager.shared.apply(.disabled)
        state.shutdown()
    }

    /// Rebuilds the panel on the screen that physically has a notch,
    /// falling back to the main display on non-notched Macs. Space changes
    /// alone do not require rebuilding: the panel is joined to every Space and
    /// its controller re-anchors its existing window without disrupting hover.
    private func attachToBestScreen() {
        screenChangeWork = nil
        guard let screen = NotchGeometry.preferredScreen else { return }
        // Never carry an expanded panel across a display change — the new
        // geometry starts from the resting state.
        state.collapse()
        windowController?.close()
        windowController = NotchWindowController(state: state, screen: screen)
        windowController?.showPanel()
    }

    @objc private func screenParametersDidChange() {
        scheduleScreenReattach()
    }

    /// A display change is not one notification: plugging in a monitor,
    /// changing resolution or waking a lid fires several in a row, and
    /// rebuilding the panel on each one flickers — and can leave it anchored
    /// to a screen that is about to disappear. One rebuild, after it settles.
    private func scheduleScreenReattach() {
        screenChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.attachToBestScreen()
        }
        screenChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
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
