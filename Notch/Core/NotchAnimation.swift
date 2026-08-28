import AppKit
import SwiftUI

extension Animation {
    /// The single interactive spring used for every notch expansion,
    /// contraction, and internal layout transition.
    ///
    /// Respects the system Reduce Motion setting: when enabled, springs
    /// collapse to a short cross-fade-style ease so state changes stay
    /// legible without choreography.
    static var notchSpring: Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .easeOut(duration: 0.15)
        }
        return .spring(response: 0.35, dampingFraction: 0.65, blendDuration: 0.1)
    }
}
