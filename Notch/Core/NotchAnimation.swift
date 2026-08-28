import AppKit
import SwiftUI

/// Animation personality, selectable in Settings (profile tables adapted from
/// Sapphire's NotchConfiguration).
enum AnimationProfile: String, CaseIterable, Identifiable {
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

/// Per-gesture springs: expansion overshoots, collapse settles hard, hover is
/// quick, content transitions are fully damped. All collapse to a short ease
/// under Reduce Motion.
enum NotchAnimations {
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static var profile: AnimationProfile {
        AnimationProfile(rawValue: NotchSettings.shared.animationProfile) ?? .snappy
    }

    private static let reduced = Animation.easeOut(duration: 0.15)

    /// Opening into the full panel — the one gesture allowed to overshoot.
    static var expand: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.4, dampingFraction: 0.55)
        case .bouncy: return .spring(response: 0.4, dampingFraction: 0.5)
        case .calm: return .spring(response: 0.7, dampingFraction: 0.9)
        }
    }

    /// Closing back into the hardware notch — settles without bounce.
    static var collapse: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.3, dampingFraction: 0.98)
        case .bouncy: return .spring(response: 0.3, dampingFraction: 0.85)
        case .calm: return .spring(response: 0.5, dampingFraction: 0.95)
        }
    }

    /// The hover "peek" scale.
    static var hover: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.25, dampingFraction: 0.55)
        case .bouncy: return .spring(response: 0.25, dampingFraction: 0.45)
        case .calm: return .spring(response: 0.5, dampingFraction: 1.0)
        }
    }

    /// Tab switches, gauge fills, lyric moves — damped, no wobble.
    static var content: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.45, dampingFraction: 1.0)
        case .bouncy: return .spring(response: 0.55, dampingFraction: 0.85)
        case .calm: return .spring(response: 0.75, dampingFraction: 0.9)
        }
    }

    /// Live-activity wing swaps in the collapsed notch.
    static var activity: Animation {
        guard !reduceMotion else { return reduced }
        switch profile {
        case .snappy: return .spring(response: 0.4, dampingFraction: 0.98)
        case .bouncy: return .spring(response: 0.4, dampingFraction: 0.8)
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
