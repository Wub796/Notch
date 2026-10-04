import SwiftUI

/// A screen's parts arriving in the order they are read.
///
/// This is where an entrance gets its character, rather than from the screen
/// swap itself: the mark, the permission's name, why it is being asked, what
/// happens without it, and finally the verdict — each a few points of travel and
/// a fade, `OnboardingMotion.stagger` apart.
///
/// Two rules are load-bearing:
///
/// - **Nothing is scaled up from nothing.** These are entrances for content that
///   is already there, so they move by a few points and fade; a scale from zero
///   would read as a popup, which is the vocabulary of an advertisement, not of
///   a welcome.
/// - **Reduce Motion removes the delays and the travel, not the fade.** The
///   order of arrival is decoration; the content still has to turn up.
struct OnboardingReveal: ViewModifier {
    var index: Int
    var appeared: Bool
    var travel: CGFloat = OnboardingMotion.revealTravel
    var extraDelay: Double = 0

    func body(content: Content) -> some View {
        let reduced = OnboardingMotion.prefersReducedMotion
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduced ? 0 : travel)
            .animation(OnboardingMotion.revealStep(index, extraDelay: extraDelay), value: appeared)
    }
}

extension View {
    /// Arrives as the `index`-th part of the screen it belongs to.
    func onboardingReveal(
        _ index: Int,
        appeared: Bool,
        travel: CGFloat = OnboardingMotion.revealTravel,
        extraDelay: Double = 0
    ) -> some View {
        modifier(OnboardingReveal(index: index, appeared: appeared, travel: travel, extraDelay: extraDelay))
    }
}

/// The invitation: a ring around the demo notch, breathing outward until the
/// notch has been touched once, then gone for good.
///
/// The welcome screen's whole ask is "point at the notch", and a still shape
/// does not ask for anything. It stops after the first interaction rather than
/// looping forever — an invitation that keeps waving after it has been accepted
/// is nagging.
struct OnboardingInviteHalo: View {
    var width: CGFloat
    var height: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Whether the ring is still wanted. It is the demo's own `hasTried`.
    var isActive: Bool

    /// Whether the ring is still being drawn at all.
    ///
    /// Kept apart from `isActive` so an accepted invitation can *withdraw*: the
    /// timeline has to outlive the decision by the length of the fade, or the
    /// ring is cut mid-breath the instant the notch is touched, which is the one
    /// moment on this screen everyone is looking at it.
    @State private var drawing = true
    @State private var withdrawalTask: Task<Void, Never>?

    /// How long the ring takes to leave once it has been accepted.
    private static let withdrawal: Double = 0.3

    /// One breath, in seconds.
    private static let period: Double = 1.9
    /// How often the breath is sampled.
    ///
    /// A repeating animation would redraw this ring on every frame of every
    /// display it is on, forever, for an ambient pulse nobody is reading — it
    /// measured at 7% of a core on the welcome screen. Sampled and glided
    /// (`NotchAnimations.clockStep`) it is indistinguishable and costs a
    /// fraction.
    private static let sample: Double = 0.12

    var body: some View {
        ZStack {
            if drawing {
                if OnboardingMotion.prefersReducedMotion {
                    // Reduce Motion keeps the ring and drops the breathing
                    // entirely: a still outline says the same thing without any
                    // motion at all.
                    ring(at: nil).opacity(0.7)
                } else {
                    TimelineView(.periodic(from: .now, by: Self.sample)) { context in
                        ring(at: context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: Self.period) / Self.period)
                    }
                }
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(isActive ? nil : .easeOut(duration: Self.withdrawal), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // An invitation nobody has answered is the only reason to sample the
        // clock: opening on an already-touched notch (a review run, a replay)
        // draws nothing and costs nothing.
        .onAppear { if !isActive { drawing = false } }
        .onChange(of: isActive) { _, active in
            withdrawalTask?.cancel()
            guard !active else { drawing = true; return }
            withdrawalTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.withdrawal + 0.06))
                guard !Task.isCancelled, !isActive else { return }
                drawing = false
            }
        }
        .onDisappear { withdrawalTask?.cancel() }
    }

    /// - Parameter progress: 0…1 through a breath, or nil for the still ring.
    private func ring(at progress: Double?) -> some View {
        // Smoothstep: the ring leaves slowly and arrives slowly, rather than
        // snapping at the ends of a linear ramp.
        let eased: Double = progress.map { step in
            let t = min(max(step, 0), 1)
            return t * t * (3 - 2 * t)
        } ?? 0

        return NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
            .stroke(Color.white.opacity(0.30), lineWidth: 1)
            .frame(width: width, height: height)
            .scaleEffect(1 + 0.16 * eased)
            .opacity(0.5 * (1 - eased))
            .animation(NotchAnimations.clockStep(Self.sample), value: eased)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A sheen that crosses a surface once, used when the demo's panel opens: the
/// glass catching the light as it unfolds.
///
/// Optional by design — under Reduce Motion it is not drawn at all, and it never
/// carries meaning, so its absence costs nothing.
struct OnboardingSheen: View {
    var isActive: Bool
    var cornerRadius: CGFloat

    var body: some View {
        if !OnboardingMotion.prefersReducedMotion {
            sheen
        }
    }

    private var sheen: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.10), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.6)
            .offset(x: isActive ? proxy.size.width * 1.05 : -proxy.size.width * 0.65)
            .animation(isActive ? .easeOut(duration: 0.7).delay(0.08) : nil, value: isActive)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}
