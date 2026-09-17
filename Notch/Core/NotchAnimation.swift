import AppKit
import SwiftUI

/// Animation personality, selectable in Settings.
enum AnimationProfile: String, CaseIterable, Identifiable, Hashable, Sendable {
    case snappy
    case bouncy
    case calm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .snappy: "Snappy"
        case .bouncy: "Bouncy"
        case .calm: "Calm"
        }
    }
}

/// Shared animation curves.
///
/// Springs, per the Apple-style fluid-motion vocabulary: interruptible and
/// velocity-aware, which is exactly what a notch you can grab and reverse
/// mid-flight needs. The three profiles vary response and damping together,
/// and every value collapses to a short fade under Reduce Motion.
/// They live here rather than in the view so the Animation Style picker
/// actually reaches the expansion, which is the motion it most obviously
/// describes.
enum NotchAnimations {
    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// What every animation collapses to under Reduce Motion.
    static let reduced = Animation.easeOut(duration: 0.15)

    private static var profile: AnimationProfile {
        NotchSettings.shared.animationProfile
    }

    /// Opening into the full panel: a natural, fluid spring that is
    /// interruptible and momentum-aware. Opening is the slower of the two
    /// directions on purpose — a panel unfolding wants to be savoured, where
    /// closing wants to get out of the way.
    static var open: Animation {
        guard !prefersReducedMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0)
        case .bouncy: return .spring(response: 0.44, dampingFraction: 0.76, blendDuration: 0)
        case .calm: return .spring(response: 0.48, dampingFraction: 0.98, blendDuration: 0)
        }
    }

    /// Closing back into the hardware notch: brisk and responsive so it gets out of the way.
    static var close: Animation {
        guard !prefersReducedMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.32, dampingFraction: 0.96, blendDuration: 0)
        case .bouncy: return .spring(response: 0.36, dampingFraction: 0.85, blendDuration: 0)
        case .calm: return .spring(response: 0.40, dampingFraction: 1.0, blendDuration: 0)
        }
    }

    /// The animation that should drive a change into the given mode.
    static func forMode(_ mode: NotchMode) -> Animation {
        mode == .expanded ? open : close
    }

    /// How long a close takes to be *finished* rather than merely started.
    ///
    /// A spring has no duration of its own, but two things need the same
    /// answer to "has the notch finished closing yet?": the panel window, which
    /// must not shrink until the slab has finished animating inside it (it would
    /// clip the slab mid-flight), and the hover probe, which must not re-open the
    /// notch while it is still on its way down. One number, so the two can never
    /// disagree about when the motion is over.
    static var closeSettle: TimeInterval {
        guard !prefersReducedMotion else { return 0.2 }
        switch profile {
        case .snappy: return 0.55
        case .bouncy: return 0.6
        case .calm: return 0.65
        }
    }

    /// Tab switches, gauge fills, lyric moves.
    static var content: Animation {
        guard !prefersReducedMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.24, dampingFraction: 0.92, blendDuration: 0)
        case .bouncy: return .spring(response: 0.30, dampingFraction: 0.78, blendDuration: 0)
        case .calm: return .spring(response: 0.34, dampingFraction: 0.98, blendDuration: 0)
        }
    }

    /// Live-activity swaps in the closed notch.
    static var activity: Animation {
        guard !prefersReducedMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.28, dampingFraction: 0.90, blendDuration: 0)
        case .bouncy: return .spring(response: 0.36, dampingFraction: 0.80, blendDuration: 0)
        case .calm: return .spring(response: 0.40, dampingFraction: 0.98, blendDuration: 0)
        }
    }

    /// Hovering the closed pill: subtle, responsive expansion.
    static var hover: Animation {
        guard !prefersReducedMotion else { return reduced }
        return .spring(response: 0.24, dampingFraction: 0.78)
    }

    /// The HUD bar's own settle, matching `DraggableProgressBar`. Computed,
    /// not stored: a `let` could collapse under neither Reduce Motion nor the
    /// Animation Style picker.
    static var hudBar: Animation {
        guard !prefersReducedMotion else { return reduced }
        switch profile {
        case .snappy: return .smooth(duration: 0.26)
        case .bouncy: return .smooth(duration: 0.30)
        case .calm: return .smooth(duration: 0.36)
        }
    }

    /// Charging popup: pops in beneath the notch with subtle physical spring,
    /// then dismisses cleanly.
    static var chargePop: AnyTransition {
        if prefersReducedMotion {
            return .opacity
        }
        // Arriving is the deliberate moment and gets the slower `activity`
        // spring; leaving snaps out of the way on `content`. Both follow the
        // user's Animation Style, which a hardcoded spring here did not.
        return .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .top)
                .combined(with: .opacity)
                .combined(with: .offset(y: -4))
                .animation(activity),
            removal: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .top))
                .animation(content)
        )
    }

    /// Closed-notch activity swap: a subtle scale-in (0.97) and scale-out (0.94),
    /// so one activity replacing another reads as an organic substitution.
    static var activitySwap: AnyTransition {
        // Reduce Motion keeps the substitution readable and drops the scale:
        // gentler, not absent. This used to scale regardless, the one
        // transition in the app that ignored the preference.
        if prefersReducedMotion {
            return .opacity.animation(reduced)
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.97, anchor: .center))
                .animation(activity),
            removal: .opacity
                .combined(with: .scale(scale: 0.94, anchor: .center))
                .animation(content)
        )
    }
}

extension NotchAnimations {
    /// The open panel's content — its header and module — arriving and
    /// leaving with the slab.
    ///
    /// Timed against the slab's spring rather than riding it. Riding it, the
    /// content sat at full size from the first frame and the growing slab
    /// uncovered it like a curtain; on the way down the shrinking slab cropped
    /// straight through a panel that was still fully opaque. Now it arrives a
    /// beat after the slab starts to open, resolving out of a slight blur and
    /// scale as the panel unfolds, and on close it clears out before the slab
    /// has closed over it.
    static var panelContent: AnyTransition {
        if prefersReducedMotion {
            return .opacity.animation(reduced)
        }
        let effect = AnyTransition.modifier(
            active: PanelContentEffect(isPresented: false),
            identity: PanelContentEffect(isPresented: true)
        )
        return .asymmetric(
            insertion: effect.animation(open.delay(0.05)),
            removal: effect.animation(.easeOut(duration: 0.12))
        )
    }

    /// One screen of the open panel replacing another. Sequenced, not
    /// crossfaded: the outgoing screen clears in a tenth of a second and the
    /// incoming one arrives just after, settling up out of a small offset. A
    /// crossfade drew two dense screens over each other at half opacity for
    /// most of the swap — "Houston 28°" through "September" — while the panel
    /// was resizing underneath both.
    static var screenSwap: AnyTransition {
        if prefersReducedMotion {
            return .opacity.animation(reduced)
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 6))
                .animation(content.delay(0.09)),
            removal: .opacity.animation(.easeOut(duration: 0.09))
        )
    }

    /// The header strip's version of `screenSwap`: the same sequencing, with no
    /// travel — a header sliding down out of the hardware notch looks broken.
    static var headerSwap: AnyTransition {
        if prefersReducedMotion {
            return .opacity.animation(reduced)
        }
        return .asymmetric(
            insertion: .opacity.animation(content.delay(0.09)),
            removal: .opacity.animation(.easeOut(duration: 0.09))
        )
    }

    /// The closed strip — the wings and anything dropped beneath the notch —
    /// trading places with the open panel. It gets out of the way almost at
    /// once when the notch opens, and on close waits until the slab has mostly
    /// shrunk back before it returns, so the two never cross-fade over each
    /// other.
    static var closedStrip: AnyTransition {
        if prefersReducedMotion {
            return .opacity.animation(reduced)
        }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.16)),
            removal: .opacity.animation(.easeOut(duration: 0.08))
        )
    }
}

/// The blur, fade and slight scale the open panel's content arrives from.
/// Anchored to the top, so it settles down out of the notch rather than
/// swelling from its own middle.
private struct PanelContentEffect: ViewModifier {
    let isPresented: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPresented ? 1 : 0.96, anchor: .top)
            .blur(radius: isPresented ? 0 : 6)
            .opacity(isPresented ? 1 : 0)
    }
}

extension Animation {
    /// Shared micro-interaction curve used across module views.
    static var notchSpring: Animation {
        NotchAnimations.content
    }
}
