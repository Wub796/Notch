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
/// The notch's own open/close springs live in `NotchContainerView`, matching
/// boring.notch and Atoll exactly: `.spring(response: 0.42, dampingFraction: 1)`
/// opening and `0.45` closing, both critically damped. What lives here is
/// everything else — content swaps, gauges, live-activity changes — which both
/// references drive with `.smooth` and `.bouncy` rather than a tuned spring per
/// gesture.
enum NotchAnimations {
    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// What every animation collapses to under Reduce Motion.
    static let reduced = Animation.easeOut(duration: 0.15)

    private static var profile: AnimationProfile {
        NotchSettings.shared.animationProfile
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
