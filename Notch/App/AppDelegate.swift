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
        _ = UpdateController.shared
        clearRetiredSpotifyCookie()

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

        #if DEBUG
        // Screenshot hooks for development: there is no other way to drive the
        // panel from a script, because opening it needs either a click or the
        // global hotkey and both require Accessibility.
        if CommandLine.arguments.contains("--debug-expand") {
            // Re-assert rather than expand once. A display wake triggers a
            // screen re-attach, which collapses the panel by design, and an
            // outside click collapses it too — both of which happen while a
            // screenshot is being taken on a machine somebody is using.
            for step in 0 ..< 14 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + 0.5 * Double(step)) { [weak self] in
                    guard let self else { return }
                    if self.state.mode != .expanded { self.state.expand() }
                    self.state.isPinned = true
                }
            }
        }
        if CommandLine.arguments.contains("--debug-cycle") {
            // Opens and closes the panel on a loop so the expand and collapse
            // motion can be screen-recorded and inspected frame by frame.
            // Never onto the camera screen: expanding there turns the camera on.
            for step in 0 ..< 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3 + 1.5 * Double(step)) { [weak self] in
                    guard let self else { return }
                    if self.state.tab == .camera { self.state.select(.home) }
                    if step.isMultiple(of: 2) { self.state.expand() } else { self.state.collapse() }
                }
            }
        }
        if CommandLine.arguments.contains("--debug-tab-cycle") {
            // Walks the open panel through Home, Weather and Calendar (and the
            // month grid) so tab transitions can be recorded frame by frame.
            let script: [(TimeInterval, (NotchState) -> Void)] = [
                (2.0, { $0.select(.home); $0.expand(); $0.isPinned = true }),
                (4.0, { $0.select(.weather) }),
                (6.0, { $0.select(.home) }),
                (8.0, { $0.select(.calendar) }),
                (10.0, { $0.calendar.isMonthView = true }),
                (12.0, { $0.calendar.isMonthView = false }),
                (14.0, { $0.select(.weather) }),
                (16.0, { $0.select(.calendar) }),
                (18.0, { $0.select(.home) }),
            ]
            for (delay, step) in script {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    step(self.state)
                }
            }
        }
        if CommandLine.arguments.contains("--debug-clipboard") {
            // Opens the clipboard window, which otherwise needs a click on the rail.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                ClipboardWindowController.shared.show(clipboard: self.state.clipboard)
            }
        }
        if CommandLine.arguments.contains("--debug-tap") {
            // A real click on the closed notch, delivered to the panel itself,
            // so opening goes through the SwiftUI tap gesture the way a user's
            // click does rather than through a timer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, let panel = self.windowController?.window else { return }
                if self.state.tab == .camera { self.state.select(.home) }
                let point = NSPoint(x: panel.frame.width / 2, y: panel.frame.height - 12)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: panel.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1,
                        pressure: type == .leftMouseDown ? 1 : 0
                    ) else { continue }
                    panel.sendEvent(event)
                }
                // Held open so an unrelated click elsewhere cannot close it
                // before it has been looked at.
                self.state.isPinned = true
            }
        }
        if CommandLine.arguments.contains("--debug-timer") {
            // Puts a countdown on screen so the timer widget's running state
            // can be looked at without clicking a preset.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.state.timer.start(minutes: 15)
            }
        }
        if CommandLine.arguments.contains("--debug-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                SettingsWindowController.shared.show()
                // Full height, so a whole pane fits in one screenshot without
                // needing to scroll it.
                if let window = SettingsWindowController.shared.window,
                   let screen = window.screen ?? NSScreen.main {
                    let visible = screen.visibleFrame
                    window.setFrame(
                        NSRect(x: visible.midX - 410, y: visible.minY,
                               width: 820, height: visible.height),
                        display: true
                    )
                }
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--debug-tab"),
           index + 1 < CommandLine.arguments.count,
           let tab = NotchTab(rawValue: CommandLine.arguments[index + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.state.select(tab)
            }
        }
        #endif
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

        if let existing = windowController {
            existing.cleanup()
            existing.close()
            windowController = nil
        }

        HotKeyManager.shared.apply(.disabled)
        state.shutdown()
    }

    /// Deletes the Spotify session cookie the retired Canvas feature stored.
    ///
    /// Canvas is gone — see the note in README. It ran on Spotify's
    /// `get_access_token`, which now answers 403 to every request and whose
    /// replacement states that third-party use is not permitted, so nothing
    /// is left that could use this credential. Anything still in the keychain
    /// is account access for a feature that no longer exists, and keeping it
    /// there is the one part of this retirement that is not cosmetic.
    ///
    /// Runs once: guarded by a defaults flag, so it is not a keychain write on
    /// every launch, and not a migration that repeats forever.
    private func clearRetiredSpotifyCookie() {
        let key = "retiredSpotifyCanvasCookieCleared"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        KeychainStore.delete("spotify.sp_dc")
        // The feature's own preference goes with it, so nothing is left in
        // defaults for a switch that no longer exists.
        UserDefaults.standard.removeObject(forKey: "spotifyCanvasEnabled")
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Rebuilds the panel on the screen that physically has a notch,
    /// falling back to the main display on non-notched Macs. Space changes
    /// alone do not require rebuilding: the panel is joined to every Space and
    /// its controller re-anchors its existing window without disrupting hover.
    private func attachToBestScreen() {
        // Cancel, don't just forget: a direct call (the screen preference
        // changing) while a debounced rebuild was armed left the old work item
        // scheduled, so the panel was rebuilt a second time 0.4s later.
        screenChangeWork?.cancel()
        screenChangeWork = nil
        guard let screen = NotchGeometry.preferredScreen else { return }
        // Never carry an expanded panel across a display change — the new
        // geometry starts from the resting state.
        state.collapse()
        if let existing = windowController {
            existing.cleanup()
            existing.close()
            existing.window?.orderOut(nil)
            windowController = nil
        }
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
