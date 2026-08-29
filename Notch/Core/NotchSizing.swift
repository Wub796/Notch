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
    static let defaultOpenWidth: Double = 900
    static let minimumOpenHeight: Double = 140
    static let defaultOpenHeight: Double = 182
    static let maximumOpenHeight: Double = 420

    static func maxAllowedOpenWidth(for screen: NSScreen? = NSScreen.main) -> Double {
        guard let width = screen?.frame.width, width > 0 else { return 900 }
        return max(Double(width) - 60, minimumOpenWidth)
    }

    /// The open slab for a given screen.
    ///
    /// Per-tab again. Sharing one size across every screen kept the panel from
    /// resizing on a tab switch, which is what boring.notch and Atoll do — but
    /// these screens are genuinely different shapes, and forcing a month grid
    /// and a weather hero into the same box shrank both past legibility. The
    /// width preference now scales them together rather than setting one.
    static func openNotchSize(for tab: NotchTab) -> CGSize {
        let base = baseSize(for: tab)
        let scale = min(max(NotchSettings.shared.openNotchWidth, minimumOpenWidth),
                        maxAllowedOpenWidth()) / defaultOpenWidth
        return CGSize(
            width: min(base.width * scale, maxAllowedOpenWidth()),
            height: min(base.height * scale, maximumOpenHeight)
        )
    }

    /// Each screen's natural size at the default width.
    private static func baseSize(for tab: NotchTab) -> CGSize {
        switch tab {
        case .home: CGSize(width: 900, height: 182)
        case .media: CGSize(width: 880, height: 290)
        case .weather: CGSize(width: 980, height: 300)
        case .calendar: CGSize(width: 940, height: 340)
        case .shelf: CGSize(width: 820, height: 220)
        case .clipboard: CGSize(width: 840, height: 200)
        case .tools: CGSize(width: 940, height: 210)
        case .notes: CGSize(width: 760, height: 240)
        case .telemetry: CGSize(width: 840, height: 190)
        case .audio: CGSize(width: 860, height: 300)
        }
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
