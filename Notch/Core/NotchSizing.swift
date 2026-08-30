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
    ) = (opened: (top: 19, bottom: 24), closed: (top: 0, bottom: 14))

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
    static let minimumOpenHeight: Double = 150
    static let defaultOpenHeight: Double = 215
    static let maximumOpenHeight: Double = 500

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

    /// Whether the open module's height should hug its content instead of
    /// the fixed per-tab budget.
    ///
    /// The tabs that opt in are the ones whose content is a fixed column
    /// (or a horizontal scroll row): home, weather, calendar, shelf and
    /// clipboard all render a natural height well below their budget, which
    /// is the black band under the module. The rest are vertical ScrollViews
    /// or charts written to fill the budget, so pinning their height to the
    /// budget is correct and fitting them would just clamp to it anyway.
    static func fitsHeight(for tab: NotchTab) -> Bool {
        switch tab {
        case .home, .weather, .calendar, .shelf, .clipboard: true
        default: false
        }
    }

    /// Floor for a fitted module height: below this the panel starts to look
    /// like a sliver rather than a notch, so the slab stays at least this
    /// tall even when the content is a single short row.
    static let minimumFittedModuleHeight: CGFloat = 90

    /// Extra width every dead zone draws beyond the measured notch, split
    /// evenly between the two sides. The notch measurement can run a couple
    /// of points short of the hardware cutout; this margin keeps everything
    /// laid out beside the notch — header flanks, the collapsed wings, the
    /// hover probe — clear of the real notch even then.
    static let notchCoverageBleed: CGFloat = 8

    /// Each screen's natural size at the default width.
    private static func baseSize(for tab: NotchTab) -> CGSize {
        switch tab {
        case .home: CGSize(width: 860, height: 205)
        case .media: CGSize(width: 580, height: 330)
        case .weather: CGSize(width: 600, height: 320)
        case .calendar: CGSize(width: 620, height: 350)
        case .shelf: CGSize(width: 640, height: 240)
        case .clipboard: CGSize(width: 660, height: 255)
        case .tools: CGSize(width: 880, height: 295)
        case .notes: CGSize(width: 580, height: 265)
        case .telemetry: CGSize(width: 800, height: 275)
        case .audio: CGSize(width: 880, height: 280)
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
