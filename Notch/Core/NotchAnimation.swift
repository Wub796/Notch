import SwiftUI

extension Animation {
    /// The single interactive spring used for every notch expansion,
    /// contraction, and internal layout transition.
    static let notchSpring = Animation.spring(
        response: 0.35,
        dampingFraction: 0.65,
        blendDuration: 0.1
    )
}
