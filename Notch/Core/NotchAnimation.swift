import AppKit
import SwiftUI

/// Animation personality, selectable in Settings (profile tables adapted from
/// Sapphire's NotchConfiguration).
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

/// Per-gesture springs: longer response and heavier damping than classic
/// springs so the notch glides instead of snapping, with only a gentle
/// overshoot on expansion. All collapse to a short ease under Reduce Motion.
enum NotchAnimations {
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static var profile: AnimationProfile {
        NotchSettings.shared.animationProfile
    }

    private static let reduced = Animation.easeOut(duration: 0.15)

    /// Opening into the full panel. Timing curves rather than springs: a
    /// spring accelerates and settles at a varying rate, which reads as the
    /// notch speeding up and easing off. These hold an even pace so the
    /// shape simply grows.
    static var expand: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .easeInOut(duration: 0.30)
        case .bouncy: return .spring(response: 0.36, dampingFraction: 0.66)
        case .calm: return .easeInOut(duration: 0.45)
        }
    }

    /// Closing back into the hardware notch — the same pace, in reverse.
    static var collapse: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .easeInOut(duration: 0.28)
        case .bouncy: return .spring(response: 0.3, dampingFraction: 0.85)
        case .calm: return .easeInOut(duration: 0.42)
        }
    }

    /// The hover "peek" scale.
    static var hover: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .easeInOut(duration: 0.18)
        case .bouncy: return .spring(response: 0.22, dampingFraction: 0.66)
        case .calm: return .easeInOut(duration: 0.28)
        }
    }

    /// Tab switches, gauge fills, lyric moves — fully damped, no wobble.
    static var content: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .easeInOut(duration: 0.26)
        case .bouncy: return .spring(response: 0.36, dampingFraction: 0.86)
        case .calm: return .easeInOut(duration: 0.4)
        }
    }

    /// Live-activity wing swaps in the collapsed notch.
    static var activity: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .easeInOut(duration: 0.32)
        case .bouncy: return .spring(response: 0.45, dampingFraction: 0.8)
        case .calm: return .easeInOut(duration: 0.45)
        }
    }

    /// The animation that should drive a change into the given mode.
    static func forMode(_ mode: NotchMode) -> Animation {
        switch mode {
        case .expanded: expand
        case .peek: hover
        case .collapsed: collapse
        }
    }
}

extension Animation {
    /// Shared micro-interaction spring used across module views.
    static var notchSpring: Animation {
        NotchAnimations.content
    }
}
