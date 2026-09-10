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

    /// The HUD bar's own settle, matching `DraggableProgressBar`.
    static let hudBar = Animation.smooth(duration: 0.3)

    /// Charging popup: pops in beneath the notch with subtle physical spring,
    /// then dismisses cleanly.
    static var chargePop: AnyTransition {
        if prefersReducedMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .top)
                .combined(with: .opacity)
                .combined(with: .offset(y: -4))
                .animation(.spring(response: 0.34, dampingFraction: 0.78)),
            removal: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .top))
                .animation(.spring(response: 0.24, dampingFraction: 0.92))
        )
    }

    /// Closed-notch activity swap: a subtle scale-in (0.97) and scale-out (0.94),
    /// so one activity replacing another reads as an organic substitution.
    static var activitySwap: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.97, anchor: .center))
                .animation(.spring(response: 0.28, dampingFraction: 0.85)),
            removal: .opacity
                .combined(with: .scale(scale: 0.94, anchor: .center))
                .animation(.spring(response: 0.22, dampingFraction: 0.95))
        )
    }
}

extension Animation {
    /// Shared micro-interaction curve used across module views.
    static var notchSpring: Animation {
        NotchAnimations.content
    }
}
