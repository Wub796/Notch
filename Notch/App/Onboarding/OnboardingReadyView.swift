import SwiftUI

/// The hand-off: what is on, the one setting worth offering while the window is
/// still open, the gestures in three lines, and a single way out.
///
/// It ends on the notch, not on a settings screen — the last thing this window
/// does is close, which is the whole point of the flow.
struct OnboardingReadyView: View {
    let granted: [IntegrationPermissions.Integration]
    /// What is off but could be on. The last screen is the last chance to act.
    let notGranted: [IntegrationPermissions.Integration]
    let launchAtLogin: Bool
    let launchAtLoginError: String?
    let onSetLaunchAtLogin: (Bool) -> Void
    let onOpenSettings: (IntegrationPermissions.Integration) -> Void

    /// Flips once, on entry, for the staggered arrival.
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text("You're all set.")
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(OnboardingVerdict.grantedInk)
                        .scaleEffect(appeared || OnboardingMotion.prefersReducedMotion ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)
                        .animation(OnboardingMotion.confirmation.delay(OnboardingMotion.prefersReducedMotion ? 0 : 0.18), value: appeared)
                        .accessibilityHidden(true)
                }
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(lede)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // The tally in the sentence rolls when a grant lands while
                    // this screen is up, rather than the sentence reflowing.
                    .contentTransition(.numericText())
                    .animation(OnboardingMotion.confirmation, value: lede)
            }
            .onboardingReveal(0, appeared: appeared)

            summary
                .padding(.top, 20)
                .onboardingReveal(1, appeared: appeared)

            if !notGranted.isEmpty {
                switches
                    .padding(.top, 14)
                    .onboardingReveal(1, appeared: appeared, extraDelay: 0.06)
            }

            settingRow
                .padding(.top, 16)
                .onboardingReveal(2, appeared: appeared)

            Spacer(minLength: 14)

            recap
                .onboardingReveal(3, appeared: appeared)

            note
                .padding(.top, 12)
                .padding(.bottom, 2)
                .onboardingReveal(4, appeared: appeared)
        }
        .padding(.horizontal, 26)
        .padding(.top, 34)
        .onAppear { appeared = true }
    }

    private var lede: String {
        guard !granted.isEmpty else {
            return "Notch is running in your menu bar, watching the notch."
        }
        return "\(granted.count) of \(IntegrationPermissions.Integration.allCases.count) on. "
            + "Notch is already running, up in your menu bar."
    }

    /// Nothing granted is a result too, and it gets a sentence rather than an
    /// empty row: the summary states what happened, it does not scold.
    private var summary: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 166), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            if granted.isEmpty {
                Text("Nothing granted yet — Settings can change that any time.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            } else {
                // Each chip lands just after the one before it, so a full house
                // reads as a tally being counted rather than as a wall of tags.
                ForEach(Array(granted.enumerated()), id: \.element) { position, integration in
                    OnboardingChip(integration: integration)
                        .onboardingReveal(
                            1,
                            appeared: appeared,
                            travel: 5,
                            extraDelay: Double(position) * 0.035
                        )
                }
            }
        }
        // A grant made in System Settings while this screen is up adds a chip;
        // it should join the tally rather than appear in it.
        .animation(NotchAnimations.content, value: granted)
    }

    /// What is still off, each one a way to the switch that turns it on.
    ///
    /// The alternative — a sentence about Settings → Privacy — asks someone to
    /// remember a path at the exact moment they are finishing a flow. The
    /// panes can be opened directly, so they are.
    /// One row of marks, each a way to the switch that turns it on.
    ///
    /// Labelled chips were the first attempt and measured 624pt on a screen
    /// with room for 620: nine of them wrap to five rows, and the last row is
    /// the one that falls off. A row of marks is a fixed height whatever is
    /// left over, and the name is still there in the tooltip and to VoiceOver.
    private var switches: some View {
        HStack(spacing: 6) {
            Text("Still off — open a switch:")
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.inkMuted)
                .fixedSize()

            ForEach(notGranted) { integration in
                Button {
                    onOpenSettings(integration)
                } label: {
                    Image(systemName: integration.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(integration.tint)
                        .frame(width: 24, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(integration.tint.opacity(0.14))
                        }
                }
                .buttonStyle(PressableButtonStyle())
                .help("Open the Privacy pane for \(integration.title)")
                .accessibilityLabel("Open the Privacy pane for \(integration.title)")
            }

            Spacer(minLength: 0)
        }
        .animation(NotchAnimations.content, value: notGranted)
    }

    private var settingRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Launch Notch at login")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(launchAtLoginError ?? "Starts with your Mac, quietly in the menu bar.")
                    .font(.system(size: 11))
                    .foregroundStyle(launchAtLoginError == nil ? NotchTheme.inkMuted : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { launchAtLogin }, set: onSetLaunchAtLogin))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Launch Notch at login")
        }
        .padding(14)
        .background(card)
        .animation(OnboardingMotion.confirmation, value: launchAtLogin)
        .animation(NotchAnimations.content, value: launchAtLoginError)
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Worth remembering")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
            (
                Text("Hover").bold() + Text(" opens briefly. ")
                    + Text("Click").bold() + Text(" pins it open; unpin or press Escape to close. ")
                    + Text("Drop").bold() + Text(" a file to shelve it. ")
                    + Text("Set a shortcut in Settings → Notch. ")
                    + Text("Siri timers? Check Clock Timer Access in Settings → Activities.")
            )
            .font(.system(size: 11.5))
            .foregroundStyle(NotchTheme.inkSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var note: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.inkMuted)
            Text("Anything left off stays off — Notch asks again the first time a feature actually needs it, and never before.")
                .font(.system(size: 10.5))
                .lineSpacing(2)
                .foregroundStyle(NotchTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            }
    }
}
