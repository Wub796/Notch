import SwiftUI

/// First-run flow: what the notch is, one screen per permission, and the
/// hand-off back to the notch itself.
///
/// The permission screens own none of their own state. `IntegrationPermissions`
/// already knows every answer, remembers which prompts have been raised, and
/// re-reads the real status after each one — so a grant made in System Settings
/// while a screen is open lands here without any state of ours being told about
/// it, and the window can never disagree with what System Settings says.
struct OnboardingView: View {
    let state: NotchState
    let onFinish: () -> Void
    #if DEBUG
    var onStepObserved: ((OnboardingStep) -> Void)?
    #endif

    private static let steps = OnboardingStep.all
    private static let lastIndex = steps.count - 1

    @State private var index: Int
    /// Which way the last step moved, so the outgoing screen leaves the way the
    /// incoming one arrives.
    @State private var direction = 1
    @State private var leaving = false
    /// The window's own arrival, once.
    @State private var entered = false
    @State private var navigationReady = true
    @State private var navigationTask: Task<Void, Never>?
    @State private var dismissalTask: Task<Void, Never>?
    /// The pending confirmation hold, cancellable: a grant confirms for a beat
    /// and then carries the flow on, but only while that screen is still the
    /// one on show.
    @State private var advanceTask: Task<Void, Never>?
    /// The permissions this run actually asked about.
    ///
    /// It separates "granted just now, in front of you" from "was already
    /// granted before this window opened", which the status alone cannot: both
    /// read as granted, and only one of them deserves a button that says so.
    @State private var answered: Set<IntegrationPermissions.Integration> = []
    /// Only a request on the current screen earns automatic advancement.
    /// Returning to a previously granted screen must not skip it again.
    @State private var requestedIntegration: IntegrationPermissions.Integration?
    /// - Parameter startAt: which screen to open on. Only ever non-zero for a
    ///   review run (`--onboarding-step`), which exists so a screenshot of any
    ///   screen can be taken without clicking through the flow to reach it.
    init(state: NotchState, startAt index: Int = 0, onFinish: @escaping () -> Void) {
        self.state = state
        self.onFinish = onFinish
        _index = State(initialValue: min(max(index, 0), Self.lastIndex))
    }

    private var permissions: IntegrationPermissions { .shared }
    private var settings: NotchSettings { .shared }
    private var currentStep: OnboardingStep { Self.steps[index] }
    private var currentIntegration: IntegrationPermissions.Integration? { currentStep.integration }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                screen(currentStep)
                    .id(currentStep)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            OnboardingFooter(
                showsProgress: true,
                progress: Double(index) / Double(Self.lastIndex),
                counter: currentIntegration == nil ? currentStep.title : counterText,
                backEnabled: index > 0 && !leaving && navigationReady,
                laterTitle: laterTitle,
                primaryTitle: primaryTitle,
                primaryEnabled: !currentPending && !leaving && navigationReady,
                primaryGranted: currentStatus == .granted,
                primaryPending: currentPending,
                stepIndex: index,
                tint: currentStep.tint,
                navigationEnabled: navigationReady && !leaving,
                onBack: goBack,
                onLater: advance,
                onPrimary: primary
            )
        }
        .background(surface)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .scaleEffect(entered || OnboardingMotion.prefersReducedMotion ? 1 : 0.985)
        .animation(OnboardingMotion.windowEntrance, value: entered)
        .animation(OnboardingMotion.stepIn, value: index)
        .animation(OnboardingMotion.dismiss, value: leaving)
        .offset(y: OnboardingMotion.prefersReducedMotion ? 0 : (leaving ? -26 : 0) + (entered ? 0 : 6))
        .opacity(leaving ? 0 : (entered || OnboardingMotion.prefersReducedMotion ? 1 : 0))
        .onAppear {
            #if DEBUG
            onStepObserved?(currentStep)
            #endif
            entered = true
            // The folder answers are the only ones no API reports: the app
            // learns them by listing the folders, which the file catcher has
            // already done once at launch. Asking again here is what makes a
            // folder that is already allowed read as granted — "Continue" —
            // instead of offering to ask for something it already has.
            permissions.refresh(probeFolders: true)
        }
        .onChange(of: currentStatus) { previous, current in
            guard let integration = currentIntegration,
                  requestedIntegration == integration else { return }
            switch current {
            case .granted where previous != .granted:
                requestedIntegration = nil
                holdThenAdvance(from: currentStep, granted: integration)
            case .denied where previous != .denied:
                requestedIntegration = nil
                announce("\(integration.title) not granted")
            default:
                break
            }
        }
        .onChange(of: currentStep) { _, step in
            #if DEBUG
            onStepObserved?(step)
            #endif
            requestedIntegration = nil
            announce("\(step.title), step \(index + 1) of \(Self.steps.count)")
        }
        .onKeyPress(.leftArrow) {
            goBack()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            advance()
            return .handled
        }
        .onDisappear {
            advanceTask?.cancel()
            navigationTask?.cancel()
            dismissalTask?.cancel()
        }
    }

    // MARK: - Screens

    @ViewBuilder
    private func screen(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            OnboardingWelcomeView(state: state)

        case let .ask(integration):
            OnboardingAskView(
                integration: integration,
                status: permissions.status(for: integration),
                isPending: permissions.pending.contains(integration),
                note: permissions.notes[integration],
                navigationEnabled: navigationReady && !leaving,
                onSkipRest: skipRest,
                onOpenSettings: { permissions.openSettings(for: integration) }
            )

        case .ready:
            OnboardingReadyView(
                granted: granted,
                notGranted: notGranted,
                launchAtLogin: settings.launchAtLogin,
                launchAtLoginError: settings.launchAtLoginError,
                onSetLaunchAtLogin: { settings.launchAtLogin = $0 },
                onOpenSettings: { permissions.openSettings(for: $0) }
            )
            // A grant completed in System Settings after a screen gave up
            // waiting is only visible to the app once the real status is read
            // again, and the summary is the last chance to tell the truth
            // about it.
            .onAppear { permissions.refresh() }
        }
    }

    // MARK: - State

    private var currentStatus: IntegrationPermissions.Status {
        guard let integration = currentIntegration else { return .unknown }
        return permissions.status(for: integration)
    }

    private var currentPending: Bool {
        guard let integration = currentIntegration else { return false }
        return permissions.pending.contains(integration)
    }

    /// Reading every status also subscribes this view to all of them, so a
    /// grant arriving from System Settings repaints the summary on its own.
    private var granted: [IntegrationPermissions.Integration] {
        IntegrationPermissions.Integration.allCases.filter {
            permissions.status(for: $0) == .granted
        }
    }

    /// What is off and could be switched on. A permission macOS cannot answer
    /// for right now (`.unknown` — an automation target that is not running)
    /// is left out: offering to open a pane for it would be guessing.
    private var notGranted: [IntegrationPermissions.Integration] {
        IntegrationPermissions.Integration.allCases.filter {
            let status = permissions.status(for: $0)
            return status == .denied || status == .notDetermined
        }
    }

    /// Position through the optional asks, separate from permission grants:
    /// skipping advances progress too and is not a failure.
    private var counterText: String {
        let total = IntegrationPermissions.Integration.allCases.count
        return "\(index) of \(total) · \(granted.count) on"
    }

    /// What the one button says. Each state of an ask is a different offer:
    /// make the request, wait for it, carry on, or acknowledge.
    private var primaryTitle: String {
        switch currentStep {
        case .welcome:
            return "Continue"
        case .ready:
            return "Start Using Notch"
        case .ask:
            if currentPending { return "Waiting…" }
            switch currentStatus {
            case .granted:
                // Granted here, on this screen: acknowledge it. Granted before
                // the flow reached it: there is nothing to acknowledge, so the
                // button is the one thing left to do.
                guard let integration = currentIntegration else { return "Continue" }
                return answered.contains(integration) ? "Granted" : "Continue"
            case .denied: return "Next"
            case .notDetermined, .unknown: return "Grant Access"
            }
        }
    }

    /// "Not now" belongs to an unanswered ask and to an ask being waited on.
    /// A decision has already been made in every other state, and offering to
    /// skip it again would be asking the same question twice.
    private var laterTitle: String? {
        guard currentIntegration != nil else { return nil }
        if currentPending { return "Not now" }
        switch currentStatus {
        case .notDetermined, .unknown: return "Not now"
        case .granted, .denied: return nil
        }
    }

    // MARK: - Moving

    private func goBack() {
        guard !leaving, navigationReady, let previous = neighbouringStep(offset: -1) else { return }
        move(to: previous)
    }

    private func advance() {
        guard !leaving, navigationReady, let next = neighbouringStep(offset: 1) else { return }
        move(to: next)
    }

    private func move(to next: Int) {
        advanceTask?.cancel()
        navigationTask?.cancel()
        requestedIntegration = nil
        direction = next > index ? 1 : -1
        navigationReady = false
        index = next
        navigationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(OnboardingMotion.navigationSettle))
            guard !Task.isCancelled else { return }
            navigationReady = true
        }
    }

    /// The screen one step away, in whichever direction.
    ///
    /// Every screen in the flow is walked. A permission that is already granted
    /// does not make its own ask disappear — being walked past is a decision
    /// made on the reader's behalf, and the flow's whole job is to show what is
    /// on and what is off, with the button saying which of the two it is. What
    /// changes for an answer macOS already has is the verb: "Continue" instead
    /// of "Grant Access".
    private func neighbouringStep(offset: Int) -> Int? {
        let candidate = index + offset
        return (0 ... Self.lastIndex).contains(candidate) ? candidate : nil
    }

    /// The one control on every ask that answers all of them at once: asking
    /// nine questions is only acceptable if all nine can be walked away from.
    private func skipRest() {
        guard !leaving, navigationReady else { return }
        move(to: Self.lastIndex)
    }

    private func primary() {
        guard !leaving, !currentPending, navigationReady else { return }
        switch currentStep {
        case .welcome:
            advance()
        case let .ask(integration):
            switch currentStatus {
            case .notDetermined, .unknown:
                request(integration)
            case .granted, .denied:
                // Already answered — this press is the acknowledgement that
                // carries the flow on.
                advance()
            }
        case .ready:
            finish()
        }
    }

    private func request(_ integration: IntegrationPermissions.Integration) {
        answered.insert(integration)
        requestedIntegration = integration
        permissions.request(integration) { [state] in
            // Warm whatever the grant just unlocked, so the first open after
            // onboarding has something to show rather than an empty screen.
            switch integration {
            case .calendar: state.calendar.refresh()
            case .location: state.weather.refresh(force: true)
            default: break
            }
        }
    }

    private func holdThenAdvance(
        from step: OnboardingStep,
        granted integration: IntegrationPermissions.Integration
    ) {
        advanceTask?.cancel()
        advanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(OnboardingMotion.grantHold))
            guard !Task.isCancelled, Self.steps[index] == step else { return }
            // A grant can be revoked during the confirmation hold.
            guard permissions.status(for: integration) == .granted else { return }
            announce("\(integration.title) granted")
            advance()
        }
    }

    private func finish() {
        guard !leaving else { return }
        advanceTask?.cancel()
        leaving = true
        // The window leaves upward, toward the notch it just described, so the
        // last thing the flow shows is where the app actually lives.
        let delay = OnboardingMotion.prefersReducedMotion ? 0.15 : 0.24
        dismissalTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: - Chrome

    /// Sequenced, not cross-faded: the outgoing screen is gone in 160ms and the
    /// incoming one takes 260ms to arrive, which is what makes a step read as a
    /// decision rather than a page turn. Both sides carry their own timing so
    /// neither direction borrows the other's.
    ///
    /// The screen itself moves less than the prototype's 22pt because its parts
    /// now follow it in (`OnboardingReveal`) — this is the frame around the
    /// arrival, not the arrival.
    private var stepTransition: AnyTransition {
        guard !OnboardingMotion.prefersReducedMotion else {
            return .opacity.animation(NotchAnimations.reduced)
        }
        return .asymmetric(
            insertion: screenEffect(direction: CGFloat(direction))
                .animation(OnboardingMotion.stepIn),
            removal: screenEffect(direction: CGFloat(-direction))
                .animation(OnboardingMotion.stepOut)
        )
    }

    private func screenEffect(direction: CGFloat) -> AnyTransition {
        .modifier(
            active: OnboardingScreenEffect(isActive: false, direction: direction),
            identity: OnboardingScreenEffect(isActive: true, direction: 0)
        )
    }

    private var surface: some View {
        LinearGradient(
            colors: [Color(white: 0.105), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            GeometryReader { geometry in
                RadialGradient(colors: [currentStep.tint.opacity(0.12), .clear],
                               center: .center, startRadius: 0, endRadius: 210)
                    .frame(width: 420, height: 420)
                    .position(x: OnboardingMotion.prefersReducedMotion ? geometry.size.width / 2
                              : geometry.size.width * (0.25 + 0.5 * Double(index) / Double(Self.lastIndex)), y: 25)
                    .animation(OnboardingMotion.ambient, value: index)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
        .ignoresSafeArea()
    }
}

/// One screen replacing another: a little travel in the direction of the move,
/// a whisper of scale, and just enough blur to say the incoming screen is
/// arriving rather than being uncovered.
///
/// Every number here is small on purpose. The screen is the frame; the parts
/// inside it (`OnboardingReveal`) are the picture.
private struct OnboardingScreenEffect: ViewModifier {
    let isActive: Bool
    let direction: CGFloat

    func body(content: Content) -> some View {
        let reduced = OnboardingMotion.prefersReducedMotion
        content
            .opacity(isActive ? 1 : 0)
            .offset(x: isActive || reduced ? 0 : direction * OnboardingMotion.stepTravel)
            .scaleEffect(isActive || reduced ? 1 : 0.994, anchor: .center)
            .blur(radius: isActive || reduced ? 0 : 2)
    }
}
