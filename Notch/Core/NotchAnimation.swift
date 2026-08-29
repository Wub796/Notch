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
/// The open and close springs are the references' shape — critically damped —
/// but much longer than their 0.42/0.45, which snap. Opening is the slower of
/// the two here: a panel unfolding wants to be savoured, where closing wants
/// to get out of the way.
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

    /// Opening into the full panel.
    ///
    /// A timing curve rather than a spring, and this is the one place the two
    /// differ on purpose. A spring applies its full restoring force from the
    /// first frame: it leaves at speed and spends its length decelerating,
    /// which is why opening felt abrupt however long the response got. These
    /// control points hold the opening almost still for the first tenth and
    /// only reach a quarter of the way by the time a third of the duration has
    /// passed, so the panel eases away from the notch before it travels, then
    /// glides the rest. Closing keeps its spring — leaving briskly is the
    /// right behaviour on the way out.
    static var open: Animation {
        guard !prefersReducedMotion else { return reduced }
        switch profile {
        case .snappy: return .timingCurve(0.6, 0, 0.35, 1, duration: 0.8)
        case .bouncy: return .spring(response: 0.9, dampingFraction: 0.82, blendDuration: 0)
        case .calm: return .timingCurve(0.65, 0, 0.3, 1, duration: 1.05)
        }
    }

    /// Closing back into the hardware notch, slightly longer than opening so
    /// the notch never appears to snap shut.
    static var close: Animation {
        guard !prefersReducedMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.74, dampingFraction: 1, blendDuration: 0)
        case .bouncy: return .spring(response: 0.76, dampingFraction: 0.95, blendDuration: 0)
        case .calm: return .spring(response: 1.0, dampingFraction: 1, blendDuration: 0)
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
        case .snappy: return .smooth(duration: 0.25)
        case .bouncy: return .bouncy(duration: 0.35)
        case .calm: return .smooth(duration: 0.4)
        }
    }

    /// Live-activity swaps in the closed notch.
    static var activity: Animation {
        guard !prefersReducedMotion else { return reduced }
        switch profile {
        case .snappy: return .smooth(duration: 0.3)
        case .bouncy: return .bouncy(duration: 0.42)
        case .calm: return .smooth(duration: 0.45)
        }
    }

    /// Hovering the closed pill.
    static var hover: Animation {
        guard !prefersReducedMotion else { return reduced }
        return .bouncy.speed(1.2)
    }

    /// The HUD bar's own settle, matching `DraggableProgressBar`.
    static let hudBar = Animation.smooth(duration: 0.3)

    /// Closed-notch activity swap, from Atoll: a small scale in and a slightly
    /// deeper scale out, so one activity replacing another reads as a
    /// substitution rather than a flicker.
    static var activitySwap: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.965, anchor: .center))
                .animation(.spring(response: 0.34, dampingFraction: 0.88)),
            removal: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .center))
                .animation(.smooth(duration: 0.22))
        )
    }
}

extension Animation {
    /// Shared micro-interaction curve used across module views.
    static var notchSpring: Animation {
        NotchAnimations.content
    }
}
