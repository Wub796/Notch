import SwiftUI

/// The permission's mark: one tinted tile, at the same radius-to-size ratio as
/// the app's other icon tiles, so a screen full of asks still reads as Notch.
struct OnboardingTile: View {
    let integration: IntegrationPermissions.Integration
    var size: CGFloat = 34
    /// Whether this permission has been answered yes. The mark settles a touch
    /// larger and takes a green ring — a state, not a firework: a permission
    /// that is granted should look granted for as long as the screen is up.
    var granted = false

    private var reduction: Bool { OnboardingMotion.prefersReducedMotion }
    @State private var confirming = false

    var body: some View {
        Image(systemName: integration.systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(integration.tint)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .fill(integration.tint.opacity(granted ? 0.22 : 0.16))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .stroke(OnboardingVerdict.grantedInk.opacity(granted ? 0.5 : 0), lineWidth: 1.5)
            }
            // Reduce Motion keeps the ring — it is the readout — and drops the
            // change in size.
            .scaleEffect(granted && !reduction ? 1.05 : 1)
            .symbolEffect(.bounce, value: granted && !reduction)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .stroke(OnboardingVerdict.grantedInk.opacity(confirming ? 0 : 0.65), lineWidth: 1.5)
                    .scaleEffect(confirming && !reduction ? 1.65 : 1)
                    .opacity(granted && !reduction ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(OnboardingMotion.confirmation, value: granted)
            .onChange(of: granted) { old, new in
                guard new, !old else { confirming = false; return }
                withAnimation(OnboardingMotion.confirmationRing) { confirming = true }
            }
            .accessibilityHidden(true)
    }
}

/// What the current screen concluded: waiting, granted, or not granted.
///
/// An unanswered ask says nothing here — a line that says "not granted" before
/// anyone has answered would be answering for them.
struct OnboardingVerdict: View {
    enum Kind {
        case pending
        case granted
        case refused
    }

    let kind: Kind
    let text: String
    /// The engine's own explanation when nothing moved, e.g. "Enable Notch in
    /// Privacy & Security → Accessibility". Only ever shown beside a state the
    /// permission engine actually observed.
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
                .frame(width: 14, height: 14)
                .padding(.top, 1)
                // Waiting → granted swaps the glyph rather than cutting to it.
                .contentTransition(OnboardingMotion.prefersReducedMotion ? .opacity : .symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(foreground)
                    .contentTransition(.opacity)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(OnboardingMotion.confirmation, value: kind)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .pending:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
        case .granted:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Self.grantedInk)
                // The one piece of pure delight in the flow, and it is spent on
                // the moment that deserves it: a permission landing.
                .symbolEffect(.bounce, value: kind == .granted && !OnboardingMotion.prefersReducedMotion)
        case .refused:
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(NotchTheme.inkMuted)
        }
    }

    private var foreground: Color {
        kind == .granted ? Self.grantedInk : NotchTheme.inkMuted
    }

    static let grantedInk = Color(red: 91 / 255, green: 228 / 255, blue: 126 / 255) // #5BE47E
}

/// The granted summary's one chip: icon and name, in the permission's own tint.
struct OnboardingChip: View {
    let integration: IntegrationPermissions.Integration

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: integration.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(integration.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(integration.tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(integration.tint.opacity(0.15)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The flow's one persistent control strip: where you are, how far there is to
/// go, and the single thing the screen is asking for.
///
/// Back, the progress track, the tally, the skip and the primary all live here
/// rather than in the screens, so every step is left the same way it was
/// entered and nobody has to look for the way out.
struct OnboardingFooter: View {
    var showsProgress = true
    var progress: Double = 0
    var counter = ""
    var backEnabled = true
    var laterTitle: String?
    var primaryTitle: String
    var primaryEnabled = true
    var primaryGranted = false
    var primaryPending = false
    var stepIndex: Int?
    var tint: Color = .white
    var navigationEnabled = true
    var onBack: () -> Void = {}
    var onLater: () -> Void = {}
    var onPrimary: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(PressableButtonStyle())
                .modifier(HoverIconModifier())
                .disabled(!backEnabled)
                .opacity(backEnabled ? 1 : 0.3)
                .help("Back")
                .accessibilityLabel("Previous onboarding step")

                if showsProgress {
                    track
                    Text(counter)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(NotchTheme.inkMuted)
                        .fixedSize()
                        // The tally counts twice in one line ("6 of 9 · 3
                        // left"), so the digits roll rather than the sentence
                        // crossfading: a number changing is a number changing.
                        .contentTransition(.numericText())
                        .animation(OnboardingMotion.confirmation, value: counter)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 26)

            HStack(spacing: 10) {
                if let laterTitle {
                    Button(laterTitle, action: onLater)
                        .buttonStyle(PressableButtonStyle())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        }
                        // Arrives from the edge the primary is not on, so it
                        // reads as making room rather than as appearing.
                        .transition(OnboardingMotion.prefersReducedMotion
                            ? .opacity : .opacity.combined(with: .offset(x: -8)))
                        .disabled(!navigationEnabled)
                }

                Button(action: onPrimary) {
                    HStack(spacing: 8) {
                        if primaryPending {
                            ProgressView().controlSize(.small).tint(.black)
                                .transition(.opacity)
                        }
                        Text(primaryTitle)
                        if primaryGranted {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                .transition(OnboardingMotion.auxiliaryTransition)
                        }
                    }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryGranted ? OnboardingVerdict.grantedInk : .black)
                        // Grant Access → Waiting… → Granted is one button
                        // changing its mind; a crossfade says that, a hard cut
                        // says something was replaced.
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.18), value: primaryTitle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(primaryGranted ? Color.green.opacity(0.16) : Color.white)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            Color.green.opacity(primaryGranted ? 0.3 : 0),
                                            lineWidth: 1
                                        )
                                }
                        }
                        .overlay { OnboardingSheen(isActive: primaryGranted, cornerRadius: 12) }
                }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!primaryEnabled)
                .opacity(primaryEnabled ? 1 : 0.45)
                // The fill's change of heart is the loudest thing on the
                // screen when it happens, so it gets the spring; the ring is
                // always present and simply fades in.
                .animation(OnboardingMotion.confirmation, value: primaryGranted)
                .animation(NotchAnimations.content, value: primaryEnabled)
                .animation(NotchAnimations.content, value: laterTitle)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    private var track: some View {
        Group {
            if let stepIndex {
                HStack(spacing: 4) {
                    ForEach(Array(OnboardingStep.all.enumerated()), id: \.offset) { index, step in
                        Capsule()
                            .fill(index < stepIndex ? tint.opacity(0.6)
                                  : index == stepIndex ? tint : Color.white.opacity(0.10))
                            .frame(maxWidth: .infinity)
                            .frame(height: index == stepIndex ? 6 : 3)
                            .help(step.title)
                    }
                }
                .animation(OnboardingMotion.track, value: stepIndex)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(tint.opacity(0.65))
                            .frame(width: max(0, proxy.size.width * min(max(progress, 0), 1)))
                    }
                }
                .frame(height: 4)
                .animation(OnboardingMotion.track, value: progress)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue(stepIndex.map { "Step \($0 + 1) of \(OnboardingStep.all.count)" }
                             ?? "\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}
