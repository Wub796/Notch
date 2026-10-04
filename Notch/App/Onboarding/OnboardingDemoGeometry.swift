import CoreGraphics
import Foundation

/// The geometry of the welcome screen's miniature — derived, not chosen.
///
/// The demo used to carry its own numbers: a 246 × 100 panel, 30pt artwork,
/// hand-picked radii, a rail of invented controls. None of them were the app's,
/// so the picture disagreed with the product it was introducing — a panel twice
/// as tall as the real one, and none of the real one's proportions in it.
///
/// Everything here now comes from the app: the panel's width and the pill from
/// the running `NotchState`, the radii and insets from `NotchSizing`, and the
/// Now page's own row heights from `DevicesScreenMetrics` — the very metrics
/// `NotchState` sizes that page's panel with. The only decisions left are
/// framing: how much menu bar the crop shows beside the panel, and how much
/// screen it shows under it.
///
/// One definition, used by the view that draws the picture and by the check
/// report that measures it, so a report cannot describe a different picture from
/// the one that ships.
struct OnboardingDemoGeometry {
    /// The open panel's width, as the app sizes the audio tab. The width is the
    /// user's own ("Open width" scales it), so the picture follows the
    /// preference rather than disagreeing with it.
    let slabWidth: CGFloat
    /// The closed pill, as the app draws it: the measured cutout plus the
    /// coverage bleed that makes it visible.
    ///
    /// This is the *dead zone* rather than the whole pill: the closed shape the
    /// picture draws is `closedPill`, and this is the middle of it — the part
    /// the hardware camera housing occupies, which no content may be laid out
    /// inside. `ActivityWingLayout` and the open panel's cutout both take it.
    let notch: CGSize
    /// The closed pill the picture draws, at the app's own size for the pill
    /// it depicts.
    ///
    /// The demo shows the playing pill — a cover in one wing, a visualiser in
    /// the other — so it has to be the width the app gives *that* pill even on
    /// a silent Mac: `NotchState.collapsedSize(for: .music)`, which is the
    /// measured cutout plus the playing wings (and no drop, because a playing
    /// pill has nothing beneath it). Drawing the cutout alone put the wings
    /// inside the camera housing and squeezed their contents.
    let closedPill: CGSize
    /// The open panel's header strip — the band the back button and the notch's
    /// own dead zone live in (`NotchState.topBarHeight`).
    let topBar: CGFloat

    /// Menu bar shown either side of the panel, in the app's own points. The
    /// framing decision: the real screen has 1512 points of menu bar and puts
    /// the panel in the middle of them, so the crop shows a margin rather than
    /// the whole screen.
    static let sideMargin: CGFloat = 150
    /// A little screen below the panel, so the picture does not end hard on the
    /// panel's own edge.
    static let belowMargin: CGFloat = 12

    // MARK: The app's own numbers, read rather than repeated

    /// The gutter between the slab's edge and its content.
    var sideInset: CGFloat { NotchSizing.contentSideInset(for: .audio) }
    /// The band the app leaves under the module.
    var bottomInset: CGFloat { NotchSizing.contentBottomInset(for: .audio) }
    /// `NotchLayoutView`'s own gap between the header strip and the module.
    static let headerGap: CGFloat = 6

    /// The Now page's two tiles, their gap, and the safe band under them — the
    /// heights `DevicesScreenMetrics` exists to publish so the panel can be
    /// sized without measuring the page at runtime.
    var heroTile: CGFloat { DevicesScreenMetrics.heroRowHeight }
    var playbackTile: CGFloat { DevicesScreenMetrics.playbackControlsHeight }
    var sectionGap: CGFloat { DevicesScreenMetrics.sectionSpacing }
    var bottomSafe: CGFloat { DevicesScreenMetrics.bottomSafePadding }

    /// Everything under the header: the hero card, the playback card, and the
    /// band that keeps the last row off the slab's rounded corner.
    var module: CGFloat { heroTile + sectionGap + playbackTile + bottomSafe }

    /// The open panel, as the app sizes the Now page: the module plus the
    /// header, their gap and the bottom band — the same sum
    /// `NotchState.expandedSize(for:)` makes for `devicesSection == .now`.
    var slab: CGSize {
        CGSize(
            width: slabWidth,
            height: module + topBar + Self.headerGap + bottomInset
        )
    }

    /// The Now page's cover, as `DevicesScreenView` draws it.
    static let heroArtwork = CGSize(width: 76, height: 76)
    static let heroArtworkCorner: CGFloat = 20

    /// The closed pill's cover tile, as `CollapsedNotchView` draws it: its own
    /// 22pt tile, with the corner that nests inside the closed notch's. Both
    /// numbers live in that view and are mirrored here, so the picture's pill
    /// carries the same cover the real one does.
    static let closedArtworkSide: CGFloat = 22
    static var closedArtworkCorner: CGFloat {
        let gap = NotchSizing.closedArtworkInset - NotchSizing.closedFlareInset
        return max(NotchSizing.cornerRadiusInsets.closed.top - gap, 0)
    }

    var openRadii: (top: CGFloat, bottom: CGFloat) { NotchSizing.cornerRadiusInsets.opened }
    var closedRadii: (top: CGFloat, bottom: CGFloat) { NotchSizing.cornerRadiusInsets.closed }

    /// What the picture shows, in the app's points.
    var crop: CGSize {
        CGSize(
            width: slab.width + 2 * Self.sideMargin,
            height: topBar + slab.height + Self.belowMargin
        )
    }

    /// The one scale the whole picture is drawn at, for a given width.
    func scale(fitting width: CGFloat) -> CGFloat {
        width / crop.width
    }

    static func current(state: NotchState) -> OnboardingDemoGeometry {
        OnboardingDemoGeometry(
            slabWidth: state.expandedSize(for: .audio).width,
            notch: state.safeNotchSize,
            closedPill: state.collapsedSize(for: .music),
            topBar: state.topBarHeight
        )
    }

    /// What a check run prints: the real numbers, then the same numbers as the
    /// picture draws them at `width`.
    func report(drawnAt width: CGFloat) -> [String] {
        let k = scale(fitting: width)
        func drawn(_ value: CGFloat) -> String { String(format: "%.1f", value * k) }
        return [
            "demo.crop=\(Int(crop.width))x\(Int(crop.height)) scale=\(String(format: "%.4f", k))",
            "demo.slab=\(Int(slab.width))x\(Int(slab.height)) drawn=\(drawn(slab.width))x\(drawn(slab.height))",
            "demo.notch=\(Int(notch.width))x\(Int(notch.height)) drawn=\(drawn(notch.width))x\(drawn(notch.height))",
            "demo.closedPill=\(Int(closedPill.width))x\(Int(closedPill.height))"
                + " drawn=\(drawn(closedPill.width))x\(drawn(closedPill.height))",
            "demo.radiiOpen=\(Int(openRadii.top))/\(Int(openRadii.bottom))"
                + " drawn=\(drawn(openRadii.top))/\(drawn(openRadii.bottom))",
            "demo.module=\(Int(module)) hero=\(Int(heroTile)) playback=\(Int(playbackTile))"
                + " drawn=\(drawn(module))",
            "demo.heroArtwork=\(Int(Self.heroArtwork.width)) corner=\(Int(Self.heroArtworkCorner))"
                + " drawn=\(drawn(Self.heroArtwork.width))",
            "demo.closedArtwork=\(Int(Self.closedArtworkSide)) corner=\(Int(Self.closedArtworkCorner))"
                + " drawn=\(drawn(Self.closedArtworkSide))",
            "demo.topBar=\(Int(topBar)) drawn=\(drawn(topBar))",
        ]
    }
}
