import AppKit
import SwiftUI

/// Layout constants, following boring.notch's `sizing/matters.swift` and
/// Atoll's variant of it.
///
/// The important idea borrowed from both: **one open size for every tab**.
/// Sizing each screen to its own content meant the slab resized whenever you
/// switched tabs, which is the jankiest thing a notch can do. Both references
/// open to a fixed panel and fit their modules inside it, so switching tabs
/// only changes what is drawn.
enum NotchSizing {
    /// Corner radii for the two states, taken verbatim from the references.
    /// Top corners flare into the menu bar; bottom corners round inward.
    static let cornerRadiusInsets: (
        opened: (top: CGFloat, bottom: CGFloat),
        closed: (top: CGFloat, bottom: CGFloat)
    ) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

    /// Transparent margin the panel window keeps around the slab so the drop
    /// shadow is never clipped by the window bounds.
    static let shadowPadding: CGFloat = 20

    /// Album art in the two states, as in `MusicPlayerImageSizes`.
    enum ArtworkSizes {
        static let cornerRadius: (opened: CGFloat, closed: CGFloat) = (opened: 13, closed: 4)
        static let size: (opened: CGSize, closed: CGSize) = (
            opened: CGSize(width: 90, height: 90),
            closed: CGSize(width: 20, height: 20)
        )
    }

    /// Inner padding of the open slab: the horizontal inset matches the open
    /// top radius so content clears the flare, plus the references' extra 12
    /// on the sides and bottom.
    static let openContentInset: CGFloat = 12

    /// Bounds for the two size preferences. These are `Double`, not `CGFloat`:
    /// they are slider bounds before they are geometry, and `NotchSettings`
    /// stores every preference as a `Double`. Mixing the two only forces a
    /// conversion at each `Binding` in Settings. The geometry below converts
    /// once, at the point it becomes a `CGSize`.
    ///
    /// Atoll clamps the width to the screen so the slab can never overhang a
    /// scaled display; `maxAllowedOpenWidth` is that rule.
    static let minimumOpenWidth: Double = 520
    static let defaultOpenWidth: Double = 700
    static let minimumOpenHeight: Double = 170
    static let defaultOpenHeight: Double = 210
    static let maximumOpenHeight: Double = 340

    static func maxAllowedOpenWidth(for screen: NSScreen? = NSScreen.main) -> Double {
        guard let width = screen?.frame.width, width > 0 else { return 900 }
        return max(Double(width) - 60, minimumOpenWidth)
    }

    /// The open slab, from the user's preference clamped to what fits.
    ///
    /// Reads `NSScreen`, so it is main-thread-only in practice; every caller is
    /// a SwiftUI body or a `NotchState` property evaluated on the main thread.
    /// Left un-isolated deliberately: annotating it `@MainActor` warns at every
    /// one of those call sites, since `NotchState` is a plain observable class.
    static var openNotchSize: CGSize {
        let settings = NotchSettings.shared
        let width = min(
            max(settings.openNotchWidth, minimumOpenWidth),
            maxAllowedOpenWidth()
        )
        let height = min(max(settings.openNotchHeight, minimumOpenHeight), maximumOpenHeight)
        return CGSize(width: width, height: height)
    }

    /// The window is sized once for the largest slab the sliders allow, plus
    /// the shadow margin, so growing the panel never clips against its window.
    static var windowSize: CGSize {
        CGSize(
            width: maxAllowedOpenWidth() + Double(shadowPadding) * 2,
            height: maximumOpenHeight + Double(shadowPadding) * 2
        )
    }
}
