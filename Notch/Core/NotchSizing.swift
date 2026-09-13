import AppKit
import SwiftUI

/// Layout constants, following boring.notch's `sizing/matters.swift` and
/// Atoll's variant of it.
///
/// The references open to **one fixed panel for every tab** and fit their
/// modules inside it, because a slab that resizes on every tab switch is the
/// jankiest thing a notch can do. This app keeps the spirit but not the
/// letter: a month grid and a weather hero are genuinely different shapes, and
/// forcing both into one box shrank each past legibility. So the size is
/// per-tab (`baseSize(for:)`), and the two size preferences scale every tab
/// together rather than setting any one of them — switching tabs moves the
/// slab, but always between two sizes the user's own sliders chose.
enum NotchSizing {
    /// Corner radii for the two states. Top corners flare into the menu bar;
    /// bottom corners round inward. Both pairs are deliberately generous —
    /// the slab reads as a soft pill rather than a hard rectangle, and the
    /// content insets below clear them.
    static let cornerRadiusInsets: (
        opened: (top: CGFloat, bottom: CGFloat),
        closed: (top: CGFloat, bottom: CGFloat)
    ) = (opened: (top: 26, bottom: 30), closed: (top: 16, bottom: 18))

    /// Transparent margin the panel window keeps around the slab so the drop
    /// shadow is never clipped by the window bounds.
    static let shadowPadding: CGFloat = 20

    // MARK: - Top-bar rail geometry

    /// The open header's module rail controls are uniform. `NotchTopBarView`
    /// sizes its icons and spacing to these, and `NotchState` floors the slab
    /// width against them (see `topBarRailControlCount`), so the numbers live
    /// in one place and a module switch can never crop the rail against the
    /// hardware notch.
    static let topBarRailIconSize: CGFloat = 28
    static let topBarRailSpacing: CGFloat = 10

    /// How many controls the home rail carries. Derived from the rail's own
    /// list so adding a control can never leave this behind — a stale count
    /// here lets narrow modules clip the rail against the hardware notch.
    static var topBarRailControlCount: Int { NotchTopBarView.railControlCount }

    /// Intrinsic width of the top-bar rail for `count` controls (icons plus
    /// the gaps between them).
    static func topBarRailWidth(controlCount: Int) -> CGFloat {
        CGFloat(controlCount) * topBarRailIconSize
            + CGFloat(max(controlCount - 1, 0)) * topBarRailSpacing
    }

    /// Whether a tab draws the full module rail (Home, Shelf, Clipboard,
    /// Notes, Tools, Stats) rather than a detail header. Only these tabs need
    /// the slab wide enough to hold the whole rail beside the hardware notch.
    static func usesFullTopRail(for tab: NotchTab) -> Bool {
        switch tab {
        case .home, .shelf, .clipboard, .notes, .tools, .telemetry, .camera: true
        default: false
        }
    }

    /// Album art in the two states, as in `MusicPlayerImageSizes`.
    enum ArtworkSizes {
        static let cornerRadius: (opened: CGFloat, closed: CGFloat) = (opened: 18, closed: 6)
        static let size: (opened: CGSize, closed: CGSize) = (
            opened: CGSize(width: 90, height: 90),
            closed: CGSize(width: 20, height: 20)
        )
    }

    /// Inner padding of the open slab: the horizontal inset matches the open
    /// top radius so content clears the flare, plus the references' extra 5
    /// on the sides and bottom.
    static let openContentInset: CGFloat = 5

    /// Per-tab horizontal gutter between the open slab's edge and its content.
    /// The home dashboard's columns are bottom-anchored against the rounded
    /// corners; the side gutter carries a little more air than the bottom so
    /// the row reads as relaxed rather than cramped, while the bottom stays
    /// tight to the transport row. The other surfaces keep the corner-radius
    /// clearance plus breathing room.
    static func contentSideInset(for tab: NotchTab) -> CGFloat {
        tab == .home ? 30 : cornerRadiusInsets.opened.top + openContentInset
    }

    /// Per-tab inset below the open module. Home's bottom gutter is kept
    /// tight (5pt) — just enough air under the transport row, well short of
    /// the 30pt side gutter so the panel doesn't carry a tall black band
    /// beneath the dashboard. Taller surfaces keep the baseline inset.
    static func contentBottomInset(for tab: NotchTab) -> CGFloat {
        tab == .home ? 5 : openContentInset
    }

    /// Height the open slab grows by while a volume/brightness HUD drops below
    /// the module, replacing the on-top-of-the-content overlay. The bar is
    /// centered in this band, and the panel pokes down to hold it — extending
    /// the notch vertically instead of covering the screen beneath.
    /// Deliberately shorter than the closed 34pt drop: against a tall open
    /// panel a full-size HUD reads heavy.
    static let expandedHUDDropHeight: CGFloat = 28

    /// The dropped HUD's width on the open panel. The slab is far wider than
    /// the collapsed notch, and a full-panel strip would read as a new screen
    /// rather than a level readout — capping it keeps the bar a centered
    /// capsule.
    static let expandedHUDWidth: CGFloat = 280

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

    /// The widest slab a display can hold. Defaults to the screen the notch
    /// actually lives on, not `NSScreen.main` — main is whichever display has
    /// keyboard focus, so using it made the slab's width cap change as the
    /// user moved between windows on a multi-display Mac.
    static func maxAllowedOpenWidth(
        for screen: NSScreen? = NotchGeometry.preferredScreen
    ) -> Double {
        guard let width = screen?.frame.width, width > 0 else { return defaultOpenWidth }
        return max(Double(width) - 60, minimumOpenWidth)
    }

    /// The open slab for a tab, scaled by the user's two size preferences.
    ///
    /// Each preference drives its own axis: width scales the per-tab base
    /// width, height scales the per-tab base height. Height used to be scaled
    /// by the *width* preference, which left the "Open height" slider with
    /// nothing to do — it saved a value nothing ever read.
    static func openNotchSize(for tab: NotchTab, showsLyrics: Bool = true) -> CGSize {
        let base = baseSize(for: tab)
        let maxWidth = maxAllowedOpenWidth()
        let widthScale = min(max(NotchSettings.shared.openNotchWidth, minimumOpenWidth),
                             maxWidth) / defaultOpenWidth
        let heightScale = min(max(NotchSettings.shared.openNotchHeight, minimumOpenHeight),
                              maximumOpenHeight) / defaultOpenHeight
        let height = min(base.height * heightScale, maximumOpenHeight)
        return CGSize(
            width: min(base.width * widthScale, maxWidth),
            height: tab == .audio && !showsLyrics
                ? max(height - mediaLyricsRowHeight, minimumOpenHeight)
                : height
        )
    }

    /// Height the Now player's compact synced-lyric row occupies, removed from
    /// the Audio slab's budget when the row is switched off.
    static let mediaLyricsRowHeight: CGFloat = 46

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
    /// hover probe — clear of the real notch even then. It is also the closed
    /// pill's side padding: the collapsed notch is drawn to `safeNotchSize`,
    /// so half of this bleed is how far the black shape visibly extends past
    /// the hardware cutout on each side — 30 gives 15pt a side.
    ///
    /// This is the *only* coverage margin. `NotchGeometry` used to fold an
    /// undocumented `+ 4` into its measurement as well, so the real bleed was
    /// the sum of two numbers in two files and neither comment was right about
    /// it. That 4 was moved here, which is why this reads 30 rather than 26 —
    /// the drawn pill is unchanged.
    static let notchCoverageBleed: CGFloat = 30

    /// Each screen's natural size at the default width.
    private static func baseSize(for tab: NotchTab) -> CGSize {
        switch tab {
        // 236 only sets the module-budget ceiling for the home dashboard —
        // the fitted slab hugs the content (header + the 88pt music row, up
        // to +24pt for the other-audio chips, plus the 5pt bottom gutter),
        // so the base height simply needs to leave that tallest case room
        // to fit.
        // 900, not 860: the dashboard's three columns are surfaces now, and a
        // surface costs its own horizontal padding — 54pt across the row. The
        // extra 40 gives that back, so the columns keep the breathing room
        // they had before the tiles were added.
        case .home: CGSize(width: 900, height: 236)
        case .audio: CGSize(width: 880, height: 390)
        case .weather: CGSize(width: 600, height: 320)
        case .calendar: CGSize(width: 620, height: 350)
        case .shelf: CGSize(width: 640, height: 240)
        case .clipboard: CGSize(width: 660, height: 255)
        case .tools: CGSize(width: 880, height: 295)
        case .notes: CGSize(width: 580, height: 265)
        case .telemetry: CGSize(width: 800, height: 275)
        // Taller than the rest: the preview is the content, and a 16:9 feed in
        // a short panel is a letterboxed sliver.
        case .camera: CGSize(width: 620, height: 380)
        }
    }

}
