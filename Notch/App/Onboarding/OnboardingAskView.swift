import SwiftUI

/// One permission, alone on its screen.
///
/// Nine asks do not fit in a 620pt window without hiding some of them below a
/// scroll, and an ask nobody scrolled to is an ask that was never made. One
/// screen each means every request is fully on screen when it happens, the
/// visitor can walk away from any of them, and nothing is ever granted by
/// accidental proximity to the next question.
struct OnboardingAskView: View {
    let integration: IntegrationPermissions.Integration
    /// Read from `IntegrationPermissions`, never tracked separately: the real
    /// answer is the one macOS gives, and this screen only draws it.
    let status: IntegrationPermissions.Status
    let isPending: Bool
    let note: String?
    var navigationEnabled = true
    let onSkipRest: () -> Void
    let onOpenSettings: () -> Void

    @State private var skipHovering = false
    /// Flips once, on entry: everything below arrives in the order it is read.
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                skipRest
            }

            Spacer(minLength: 0)

            OnboardingTile(
                integration: integration,
                size: 38,
                granted: status == .granted
            )
            .padding(.bottom, 17)
            .onboardingReveal(0, appeared: appeared)

            Text(integration.title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(NotchTheme.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingReveal(1, appeared: appeared)

            Text(integration.askHeadline)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(NotchTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .onboardingReveal(2, appeared: appeared)

            Text(integration.askWithout)
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .foregroundStyle(NotchTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .onboardingReveal(3, appeared: appeared)

            // The third thing a person wants before answering a privacy
            // question, after what it buys and what happens without it: seeing
            // it. It arrives last because it is the footnote to the two lines
            // above it, not the headline.
            OnboardingAskDemo(
                integration: integration,
                isLive: status == .granted,
                appeared: appeared
            )
            .padding(.top, 16)
            .onboardingReveal(4, appeared: appeared)

            // The verdict is not part of the arrival: it is the answer, and it
            // animates when it has something to say (see `OnboardingVerdict`).
            if let verdict {
                VStack(alignment: .leading, spacing: 10) {
                    OnboardingVerdict(kind: verdict.kind, text: verdict.text, detail: note)
                    if showsSettingsButton { settingsButton }
                }
                .padding(.top, 16)
                .transition(OnboardingMotion.auxiliaryTransition)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .padding(.bottom, 10)
        // The engine's answers arrive from outside this view — a system prompt
        // being answered, or a switch being flipped in System Settings — so the
        // verdict showing up has to be given a transaction here.
        .animation(OnboardingMotion.confirmation, value: status)
        .animation(OnboardingMotion.confirmation, value: isPending)
        .onAppear { appeared = true }
    }

    /// Walking away is always available and always at the same place: asking
    /// nine questions is only acceptable if all nine can be declined at once.
    private var skipRest: some View {
        Button("Skip the rest", action: onSkipRest)
            .buttonStyle(PressableButtonStyle())
            .font(.system(size: 11.5))
            .foregroundStyle(skipHovering ? NotchTheme.inkSecondary : NotchTheme.inkMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(skipHovering ? 0.06 : 0)))
            .contentShape(Capsule())
            .onHover { skipHovering = $0 }
            .animation(NotchAnimations.content, value: skipHovering)
            .help("Skip the remaining permissions — Settings → Privacy can change any of them later")
            .disabled(!navigationEnabled)
            .keyboardShortcut("s", modifiers: [.command, .shift])
    }

    /// Whether there is a switch to go and flip. A wait must never be a dead
    /// end — the pane the user was sent to can be closed by accident, and a
    /// refusal can be reconsidered — so both states carry the way back to it.
    private var showsSettingsButton: Bool {
        if isPending { return integration.grantNeedsSettings }
        return status == .denied
    }

    private var settingsButton: some View {
        Button("Open System Settings", action: onOpenSettings)
            .buttonStyle(PressableButtonStyle())
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(integration.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(integration.tint.opacity(0.14)))
            .help("Opens the exact Privacy pane that holds this switch")
    }

    /// What the screen concluded, in the flow's own words. Nothing is claimed
    /// before an answer exists: an unanswered ask shows no verdict at all.
    private var verdict: (kind: OnboardingVerdict.Kind, text: String)? {
        if isPending {
            return (
                .pending,
                integration.grantNeedsSettings
                    ? "Enable Notch in System Settings, then return here. Not now is always available."
                    : "Waiting for macOS… You can choose Not now to continue."
            )
        }

        switch status {
        case .granted:
            return (.granted, "Granted. Notch picks it up straight away.")
        case .denied:
            return (.refused, "Not granted — you can change that any time in Settings → Privacy.")
        case .notDetermined, .unknown:
            return nil
        }
    }
}
