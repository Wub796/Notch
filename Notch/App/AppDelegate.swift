import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Explicit app-lifetime route for views hosted in standalone AppKit windows.
    /// Settings actions use the same delegate and root state as the notch panel.
    private(set) static var shared: AppDelegate?

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
        Self.shared = self
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
        // Lock state drives Face ID's optional unlock flow and the independent
        // lock-screen now-playing panel, so keep its monitor alive for the life
        // of the process even when Face ID itself is switched off.
        Task { @MainActor [weak self] in
            self?.state.faceID.start()
        }
        // Shortcuts reaches the mixer through this, and it has to be the
        // mixer this app is already running — see `MixerBridge`.
        MixerBridge.shared.register(
            mixer: state.mixer,
            audioApps: state.audioApps
        )
        presentOnboardingIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        installWakeObservers()

        #if DEBUG
        if CommandLine.arguments.contains("--debug-experience-check") {
            OnboardingExperienceCheck.run(state: state, reportURL: Self.promptLogURL())
        }
        if CommandLine.arguments.contains("--debug-workflow-check") {
            WorkflowCheck.run(state: state, reportURL: Self.promptLogURL())
        }
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
        if CommandLine.arguments.contains("--debug-onboarding-finish-check") {
            let flagBefore = NotchSettings.shared.hasCompletedOnboarding
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let window = self?.onboardingController?.window else { return }
                // Exercise the real default button through its keyboard event.
                guard let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    characters: "\r", charactersIgnoringModifiers: "\r",
                    isARepeat: false, keyCode: 36
                ) else { return }
                _ = window.performKeyEquivalent(with: event)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                let report = "onboarding.closed=\(self?.onboardingController == nil)\n"
                    + "handoff.expanded=\(self?.state.mode == .expanded)\n"
                    + "handoff.pinned=\(self?.state.isPinned == true)\n"
                print(report)
                if let logURL = Self.promptLogURL() {
                    try? report.write(to: logURL, atomically: true, encoding: .utf8)
                }
                self?.onboardingController?.window?.delegate = nil
                self?.onboardingController = nil
                NotchSettings.shared.hasCompletedOnboarding = flagBefore
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--debug-onboarding-check") {
            // Prints whether the first-run window actually made it on screen,
            // and whether the flow's content fits the window it is drawn in.
            // The seen-it flag is put back as it was found before terminating:
            // a check run must not use up somebody's first run.
            // A window that is built and never ordered front is the exact
            // failure this hook exists to catch; a fitting size taller than the
            // hosting view is content that would be clipped.
            let flagBefore = NotchSettings.shared.hasCompletedOnboarding
            // Which verb each ask wears — Continue, or Grant Access — depends
            // on answers that settle asynchronously (and folders need listing
            // before they are known at all), so the probe starts early enough
            // to be in the report.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                IntegrationPermissions.shared.refresh(probeFolders: true)
                // Forced, so the check measures the flow even when the seen-it
                // flag is already set — the flag is put back as it was found
                // before this run ends.
                self?.presentOnboardingIfNeeded(force: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                var lines = ["onboarding-check"]
                lines.append("policy=\(NSApp.activationPolicy() == .accessory ? "accessory" : "other")")
                let onboarding = self?.onboardingController?.window
                for (index, window) in NSApp.windows.enumerated() {
                    lines.append(
                        "window[\(index)] onboarding=\(window === onboarding) "
                            + "class=\(type(of: window)) frame=\(NSStringFromRect(window.frame)) "
                            + "visible=\(window.isVisible) level=\(window.level.rawValue)"
                    )
                }
                if let window = self?.onboardingController?.window {
                    lines.append("window.visible=\(window.isVisible)")
                    lines.append("window.activeSpace=\(window.isOnActiveSpace)")
                    lines.append("window.frame=\(NSStringFromRect(window.frame))")
                    lines.append("window.screen=\(window.screen?.localizedName ?? "none")")
                    if let hosting = window.contentView {
                        lines.append("content.frame=\(NSStringFromRect(hosting.frame))")
                        // Measured on detached probes, width-constrained so the
                        // text wraps the way it does on screen: a hosting view
                        // that is somebody's content view cannot be asked any
                        // more without answering about the window instead.
                        let measured = self.map {
                            OnboardingWindowController.measuredContentHeights(state: $0.state)
                        } ?? []
                        for entry in measured {
                            lines.append("content.step[\(entry.step)].natural=\(entry.height)")
                        }
                        let extremes = OnboardingWindowController.measuredReadyExtremes()
                            + OnboardingWindowController.measuredAskExtremes()
                        for entry in extremes {
                            lines.append("content.\(entry.label)=\(entry.height)")
                        }
                        // The tallest of every screen at this machine's state and
                        // of the last screen at both of its extremes.
                        let tallest = max(
                            measured.map(\.height).max() ?? 0,
                            extremes.map(\.height).max() ?? 0
                        )
                        lines.append("content.tallest=\(tallest)")
                        lines.append("content.fits=\(tallest <= hosting.frame.height)")
                    }
                } else {
                    lines.append("window=nil")
                }
                // Every screen is walked, granted or not: what an answer macOS
                // already holds changes is the button's verb — Continue rather
                // than Grant Access — not whether the ask is shown.
                let granted = IntegrationPermissions.Integration.allCases.filter {
                    IntegrationPermissions.shared.status(for: $0) == .granted
                }
                // Off, and out of chances to be asked: macOS has already
                // recorded an answer, so no screen can prompt for it.
                let unaskable = IntegrationPermissions.Integration.allCases.filter {
                    !granted.contains($0)
                        && !IntegrationPermissions.shared.canPrompt(for: $0)
                }
                // The real geometry the welcome's miniature is meant to be a
                // picture of, so the two can be compared as numbers.
                if let state = self?.state {
                    let notch = state.safeNotchSize
                    let home = state.expandedSize(for: .home)
                    let audio = state.expandedSize(for: .audio)
                    lines.append("geometry.notch=\(notch.width)x\(notch.height)")
                    lines.append("geometry.home=\(home.width)x\(home.height)")
                    lines.append("geometry.audio=\(audio.width)x\(audio.height)")
                    lines.append(
                        "geometry.cornerOpen=\(NotchSizing.cornerRadiusInsets.opened.top)"
                            + "/\(NotchSizing.cornerRadiusInsets.opened.bottom)"
                            + " cornerClosed=\(NotchSizing.cornerRadiusInsets.closed.top)"
                            + "/\(NotchSizing.cornerRadiusInsets.closed.bottom)"
                    )
                    lines.append(
                        "geometry.sideInsetAudio=\(NotchSizing.contentSideInset(for: .audio))"
                            + " bottomInsetAudio=\(NotchSizing.contentBottomInset(for: .audio))"
                            + " sideInsetHome=\(NotchSizing.contentSideInset(for: .home))"
                    )
                }
                if let state = self?.state {
                    let demo = OnboardingDemoGeometry.current(state: state)
                    lines.append(
                        contentsOf: demo.report(drawnAt: OnboardingWindowController.width - 52)
                    )
                }
                lines.append("flow.granted=[\(granted.map(\.rawValue).joined(separator: ","))]")
                lines.append("flow.unaskable=[\(unaskable.map(\.rawValue).joined(separator: ","))]")
                lines.append("flow.screens=\(OnboardingStep.all.count)")
                let report = lines.joined(separator: "\n")
                print(report)
                // Same escape hatch the prompt check has: a run launched the way
                // a person launches the app (`open`) has no stdout to read.
                if let logURL = Self.promptLogURL() {
                    try? (report + "\n").write(to: logURL, atomically: true, encoding: .utf8)
                }
                // AppKit closes every window on the way out, and a close
                // completes onboarding — which would mark a first run as used
                // no matter what the flag is set back to. Detached first.
                self?.onboardingController?.window?.delegate = nil
                self?.onboardingController = nil
                NotchSettings.shared.hasCompletedOnboarding = flagBefore
                NSApp.terminate(nil)
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--debug-render-onboarding"),
           index + 1 < CommandLine.arguments.count {
            // Draws the welcome screen's miniature offscreen to a PNG, with its
            // panel open, so the picture's geometry can be measured on a machine
            // with no screen-recording permission and nobody at the keyboard.
            renderOnboardingDemo(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--debug-permission-prompts"),
           index + 1 < CommandLine.arguments.count,
           let integration = IntegrationPermissions.Integration(
               rawValue: CommandLine.arguments[index + 1]
           ) {
            schedulePermissionPromptCheck(integration)
        }
        if CommandLine.arguments.contains("--debug-clock-timer-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                let timer = self.state.clockTimer
                let snapshot = timer.snapshot
                let report = [
                    "clock-timer-check",
                    "access=\(timer.access)",
                    "detail=\(timer.access.detail)",
                    "timer.present=\(snapshot != nil)",
                    "timer.paused=\(snapshot?.isPaused ?? false)",
                    "timer.remaining=\(snapshot?.remaining ?? 0)",
                    "activity=\(self.state.collapsedActivity?.kind ?? "idle")",
                    "closed.height=\(self.state.collapsedSize.height)",
                    "notch.height=\(self.state.adjustedNotchSize.height)",
                ].joined(separator: "\n")
                print(report)
                if let logURL = Self.promptLogURL() {
                    try? (report + "\n").write(to: logURL, atomically: true, encoding: .utf8)
                }
                NSApp.terminate(nil)
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
        // Wake and display-parameter notifications also fire when the same
        // display is still attached. Reuse its panel on an ordinary parameter
        // refresh so an in-flight shape animation is not interrupted.
        if let existing = windowController, existing.refreshIfAttached(to: screen) {
            existing.showPanel()
            return
        }
        // A scheduled wake/display reattach or a real display change starts
        // from the resting state and uses fresh screen geometry.
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

    /// Called by Face ID settings to start an enrollment in the notch. Select
    /// and expand first; both state transitions settle asynchronously, so the
    /// queued show also guarantees the panel is explicitly brought forward.
    func openFaceIDEnrollment(replacing identity: FaceIdentity? = nil) {
        state.faceEnrollmentRequest = FaceEnrollmentRequest(replacing: identity)
        state.isPinned = true
        state.select(.faceID)
        state.expand()
        DispatchQueue.main.async { [weak self] in
            self?.windowController?.showPanel()
        }
    }

    /// The flow's last move is the product itself.
    ///
    /// The window closes and the notch opens — once, held for a beat — so the
    /// thing the last screens configured is the thing that happens next. The
    /// hold is released afterwards and the panel goes back to its own rules
    /// (hover to peek, click to pin): a welcome that leaves a panel stuck open
    /// is a welcome somebody has to tidy up.
    private func revealNotchAfterOnboarding() {
        // A scripted run would otherwise get the panel dropped over whatever it
        // was looking at.
        guard !CommandLine.arguments.contains("--debug-onboarding-check") else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            // Never onto the camera screen: expanding there turns it on.
            if self.state.tab == .camera { self.state.select(.home) }
            self.state.select(.home)
            self.state.isPinned = true
            let handoffPinRevision = self.state.pinRevision
            self.state.expand()
            self.windowController?.showPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.state.showToast("Welcome — pin keeps this open, Escape closes", symbol: "sparkles")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
                guard let self, self.state.mode == .expanded,
                      self.state.pinRevision == handoffPinRevision else { return }
                self.state.isPinned = false
                if !self.state.isHovering, self.state.settings.autoCollapseOnMouseExit {
                    self.state.collapse()
                }
            }
        }
    }

    /// Menu bar: show the welcome again, deliberately.
    ///
    /// Onboarding is a first-run thing, so this is the only way back to it
    /// without editing defaults — and it closes the loop for anyone who
    /// dismissed it before reading it.
    func showOnboarding() {
        NotchSettings.shared.hasCompletedOnboarding = false
        presentOnboardingIfNeeded(force: true)
    }

    /// Renders the welcome screen at the window's real size, twice scale, with
    /// the demo's panel open — or closed, with `--closed` — then ends the run.
    @MainActor
    private func renderOnboardingDemo(to url: URL) {
        let startsOpen = !CommandLine.arguments.contains("--closed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            // What this run's picture is made of, printed as well as drawn: the
            // rendered PNG can then be checked against the numbers rather than
            // against a second run's idea of them.
            let geometry = OnboardingDemoGeometry.current(state: self.state)
            print("render.panelOpen=\(startsOpen)")
            for line in geometry.report(drawnAt: OnboardingWindowController.width - 52) {
                print(line)
            }
            let renderer = ImageRenderer(
                content: OnboardingWelcomeView(state: self.state, startsOpen: startsOpen)
                    .frame(
                        width: OnboardingWindowController.width,
                        height: OnboardingWindowController.height
                    )
            )
            renderer.scale = 2
            defer { NSApp.terminate(nil) }
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]),
                  (try? png.write(to: url)) != nil
            else {
                print("render-onboarding: failed")
                return
            }
            print("render-onboarding: wrote \(url.path)")
        }
    }

    /// Raises one real consent prompt and reports what macOS did with it.
    ///
    /// "The button did nothing" has two causes that look identical from the
    /// outside: a prompt that is up and still waiting to be answered, and a
    /// request macOS answered at once because it had nothing to ask. The
    /// request's completion separates them — while a prompt is on screen the
    /// completion is withheld — so this prints which of the two happened, for
    /// one integration at a time.
    ///
    /// One integration per process on purpose: two prompts would otherwise sit
    /// on top of each other, and the process ending while a prompt is up
    /// dismisses it without recording a decision either way. Both the seen-it
    /// flag and the "we asked" record are put back as they were found.
    private func schedulePermissionPromptCheck(_ integration: IntegrationPermissions.Integration) {
        let permissions = IntegrationPermissions.shared
        let key = "requested.\(integration.rawValue)"
        let requestedBefore = UserDefaults.standard.object(forKey: key)
        let flagBefore = NotchSettings.shared.hasCompletedOnboarding

        // Findings also go to a file when asked for one, because the launch
        // context changes the answer: a build launched from a terminal is
        // attributed to that terminal for consent purposes, where the same
        // build opened the way a person opens it is attributed to itself. The
        // faithful run (`open -n Notch.app --args …`) has no stdout to read.
        let logURL = Self.promptLogURL()
        func record(_ line: String) {
            print(line)
            guard let logURL else { return }
            let previous = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            try? (previous + line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let before = permissions.status(for: integration)
            record(
                "prompt-check integration=\(integration.rawValue) "
                    + "signal=\(Self.promptSignal(for: integration)) before=\(before.rawValue) "
                    + "canPrompt=\(permissions.canPrompt(for: integration))"
            )

            guard permissions.canPrompt(for: integration) else {
                record(
                    "prompt-check result=skipped reason=already-decided "
                        + "note=\(permissions.notes[integration] ?? "-")"
                )
                Self.endPermissionPromptCheck(requestedBefore, key: key, flag: flagBefore)
                return
            }

            var answered = false
            let started = Date()
            let window: TimeInterval = 6

            permissions.request(integration) {
                answered = true
                record(
                    "prompt-check answered=yes after="
                        + String(format: "%.2f", Date().timeIntervalSince(started))
                        + "s status=\(permissions.status(for: integration).rawValue)"
                )
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + window) {
                if !answered {
                    record(
                        "prompt-check answered=no within=\(Int(window))s "
                            + "verdict=\(Self.promptVerdict(for: integration))"
                    )
                }
                record(
                    "prompt-check after.status=\(permissions.status(for: integration).rawValue) "
                        + "note=\(permissions.notes[integration] ?? "-")"
                )
                Self.endPermissionPromptCheck(requestedBefore, key: key, flag: flagBefore)
            }
        }
    }

    /// Where a check run writes its findings, when `--prompt-log` names a path.
    /// Removed first, so a stale report cannot be mistaken for a new one.
    ///
    /// A run launched from a terminal is attributed to that terminal for
    /// consent purposes — the same binary then answers questions about
    /// permissions differently than when it is opened the way a person opens
    /// it. Reports are therefore written to a file as well, so the faithful run
    /// (`open -n Notch.app --args …`) can be read back.
    private static func promptLogURL() -> URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "--prompt-log"),
              index + 1 < CommandLine.arguments.count
        else { return nil }
        let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        try? FileManager.default.removeItem(at: url)
        return url
    }

    /// How much a withheld completion proves, per integration. The camera,
    /// calendar, notification and Apple Events prompts block until they are
    /// answered, so an unanswered request means one is on screen; the two that
    /// are granted out of band and the two that finish on a timer can only ever
    /// be reported as "no prompt observed".
    private static func promptSignal(for integration: IntegrationPermissions.Integration) -> String {
        switch integration {
        case .camera, .calendar, .notifications, .music: "held-while-prompting"
        case .accessibility, .screenCapture: "polled-out-of-band"
        case .filesAndFolders, .location, .bluetooth: "read-or-timer"
        }
    }

    private static func promptVerdict(for integration: IntegrationPermissions.Integration) -> String {
        switch integration {
        case .camera, .calendar, .notifications, .music: "prompt-on-screen"
        default: "no-prompt-observed"
        }
    }

    private static func endPermissionPromptCheck(_ requestedBefore: Any?, key: String, flag: Bool) {
        if let requestedBefore {
            UserDefaults.standard.set(requestedBefore, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotchSettings.shared.hasCompletedOnboarding = flag
        NSApp.terminate(nil)
    }

    /// Presents the first-run flow.
    ///
    /// Shown once per user, and the flag that decides it lives in
    /// `NotchSettings` — that is, in this account's defaults, not in the app
    /// bundle. Deleting and reinstalling the app therefore does *not* bring the
    /// welcome back: "the first time this Mac opens Notch" means exactly that,
    /// and a second install is not a second first run. The two deliberate ways
    /// back in are `--show-onboarding` for a build being reviewed, and the menu
    /// bar's "Show Welcome Again".
    private func presentOnboardingIfNeeded(force: Bool = false) {
        let forced = force || CommandLine.arguments.contains("--show-onboarding")
        guard forced || !NotchSettings.shared.hasCompletedOnboarding else { return }

        // A permission check raises real system prompts, one per run: the flow
        // window over the top of them would be answering a different question.
        guard !CommandLine.arguments.contains("--debug-permission-prompts") else { return }

        // Never a second window: asking again brings the open one forward.
        if let onboardingController {
            onboardingController.present()
            return
        }

        onboardingController = OnboardingWindowController(state: state) { [weak self] ending in
            NotchSettings.shared.hasCompletedOnboarding = true
            self?.onboardingController = nil
            guard ending == .finished else { return }
            self?.revealNotchAfterOnboarding()
        }
        onboardingController?.present()
    }
}
