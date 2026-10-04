import AppKit
import SwiftUI

/// First-launch welcome window: introduces the notch, its gestures, and the
/// optional permissions. Shown once; closing it in any way completes
/// onboarding.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    /// The window's content size, and the size the flow is laid out in.
    static let width: CGFloat = 460
    static let height: CGFloat = 620

    /// How the window went away. Onboarding is complete either way — closing
    /// the welcome is as valid an answer as finishing it — but only one of the
    /// two endings has earned the payoff that follows it.
    enum Ending {
        /// The last button on the last screen.
        case finished
        /// The window was closed, or the app was quit, on any other screen.
        case dismissed
    }

    private let onFinish: (Ending) -> Void
    private var didFinish = false

    init(state: NotchState, onFinish: @escaping (Ending) -> Void) {
        self.onFinish = onFinish

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.06, alpha: 1)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        super.init(window: window)
        window.delegate = self

        // The hosting view is given its frame *before* it becomes the content
        // view. A SwiftUI root that fills its container reports an ideal size
        // AppKit will happily grow the window to on assignment, which is how
        // this window briefly ended up 4038pt tall.
        let hosting = NSHostingView(
            rootView: OnboardingView(state: state, startAt: Self.launchStepIndex) { [weak self] in
                self?.finish()
            }
        )
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        window.contentView = hosting

        // A hosting view sizes its window to its own idea of the content's
        // ideal size, and for a root that fills its container that idea is not
        // a number anyone wants a window to be — this window briefly came up
        // 4038pt tall. The welcome is a fixed-size window by design, so the
        // hosting view is told not to size it and the content size is asserted
        // afterwards anyway.
        hosting.sizingOptions = []
        window.setContentSize(NSSize(width: Self.width, height: Self.height))
        // Again, now the size is the one that will stick: centring before it
        // was asserted left the window a little off-centre.
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OnboardingWindowController does not support NSCoding")
    }

    /// Review hook, the port's answer to the prototype's `?step=`: open the
    /// flow on a given screen so any of them can be looked at without clicking
    /// through to reach it. `--onboarding-step 6`, zero-based (welcome is 0).
    static var launchStepIndex: Int {
        #if DEBUG
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--onboarding-step"),
           flag + 1 < arguments.count,
           let step = Int(arguments[flag + 1]) {
            return max(0, min(step, OnboardingStep.all.count - 1))
        }
        #endif
        return 0
    }

    #if DEBUG
    /// How tall each screen's content naturally is at the window's width.
    ///
    /// Measured on detached hosting views, width-constrained so text wraps the
    /// way it does on screen: the real one is somebody's content view and can
    /// no longer be asked without answering about the window instead. Used by
    /// `--debug-onboarding-check` to prove no screen is being clipped — the
    /// tallest one is the one that decides whether the window is big enough.
    /// The last screen at both extremes of the only state that changes its
    /// height: every permission on, and none of them. Its grants, its tally and
    /// its actions row are all answer-dependent, so a single sample of whatever
    /// this machine happens to have says nothing about whether it fits.
    static func measuredReadyExtremes() -> [(label: String, height: CGFloat)] {
        let all = IntegrationPermissions.Integration.allCases

        func height(of view: some View) -> CGFloat {
            NSHostingView(rootView: AnyView(view.frame(width: width))).fittingSize.height
        }

        // The footer is what the container adds around every screen. Measured
        // separately so these numbers come out in the same units as the
        // per-step measurements — a screen-only figure beside a container one
        // reads as a regression that is not there.
        let footer = NSHostingView(
            rootView: AnyView(
                OnboardingFooter(primaryTitle: "Start Using Notch").frame(width: width)
            )
        ).fittingSize.height

        return [
            (
                "ready.allGranted",
                height(of: OnboardingReadyView(
                    granted: all,
                    notGranted: [],
                    launchAtLogin: true,
                    launchAtLoginError: nil,
                    onSetLaunchAtLogin: { _ in },
                    onOpenSettings: { _ in }
                )) + footer
            ),
            (
                "ready.noneGranted",
                height(of: OnboardingReadyView(
                    granted: [],
                    notGranted: all,
                    launchAtLogin: true,
                    launchAtLoginError: "Could not enable: move Notch to Applications first.",
                    onSetLaunchAtLogin: { _ in },
                    onOpenSettings: { _ in }
                )) + footer
            ),
        ]
    }

    static func measuredAskExtremes() -> [(label: String, height: CGFloat)] {
        let footer = NSHostingView(rootView: OnboardingFooter(
            laterTitle: "Not now", primaryTitle: "Waiting…", primaryPending: true,
            stepIndex: 8
        ).frame(width: width)).fittingSize.height
        return OnboardingStep.askOrder.flatMap { integration in
            [IntegrationPermissions.Status.granted, .denied, .notDetermined].map { status in
                let pending = status == .notDetermined
                let screen = NSHostingView(rootView: OnboardingAskView(
                    integration: integration, status: status, isPending: pending,
                    note: status == .denied ? "Enable Notch in Privacy & Security, then return to continue." : nil,
                    onSkipRest: {}, onOpenSettings: {}
                ).frame(width: width))
                return ("ask.\(integration.rawValue).\(pending ? "pending" : status.rawValue)",
                        screen.fittingSize.height + footer)
            }
        }
    }

    static func measuredContentHeights(state: NotchState) -> [(step: Int, height: CGFloat)] {
        OnboardingStep.all.enumerated().map { index, _ in
            let probe = NSHostingView(
                rootView: AnyView(
                    OnboardingView(state: state, startAt: index) {}.frame(width: width)
                )
            )
            return (index, probe.fittingSize.height)
        }
    }
    #endif

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        completeIfNeeded(.dismissed)
    }

    private func finish() {
        // Closing synchronously calls windowWillClose. Record the intentional
        // finish first so that delegate callback cannot turn it into a dismissal.
        completeIfNeeded(.finished)
        window?.close()
    }

    private func completeIfNeeded(_ ending: Ending) {
        guard !didFinish else { return }
        didFinish = true
        onFinish(ending)
    }
}
