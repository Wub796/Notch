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

    /// Opening into the full panel — a glide with a soft settle and just a
    /// hint of overshoot.
    static var expand: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.34, dampingFraction: 0.82)
        case .bouncy: return .spring(response: 0.38, dampingFraction: 0.62)
        case .calm: return .spring(response: 0.5, dampingFraction: 0.95)
        }
    }

    /// Closing back into the hardware notch — settles without bounce.
    static var collapse: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.26, dampingFraction: 1.0)
        case .bouncy: return .spring(response: 0.3, dampingFraction: 0.88)
        case .calm: return .spring(response: 0.42, dampingFraction: 1.0)
        }
    }

    /// The hover "peek" scale.
    static var hover: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.2, dampingFraction: 0.86)
        case .bouncy: return .spring(response: 0.22, dampingFraction: 0.66)
        case .calm: return .spring(response: 0.32, dampingFraction: 1.0)
        }
    }

    /// Tab switches, gauge fills, lyric moves — fully damped, no wobble.
    static var content: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.3, dampingFraction: 0.95)
        case .bouncy: return .spring(response: 0.36, dampingFraction: 0.86)
        case .calm: return .spring(response: 0.46, dampingFraction: 0.98)
        }
    }

    /// Live-activity wing swaps in the collapsed notch.
    static var activity: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.45, dampingFraction: 0.95)
        case .bouncy: return .spring(response: 0.45, dampingFraction: 0.8)
        case .calm: return .spring(response: 0.6, dampingFraction: 0.98)
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
