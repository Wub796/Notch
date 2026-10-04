import CoreGraphics

/// The two arrangements the Home dashboard's cards are drawn in, and the width
/// each one needs to be drawn in without being squeezed.
///
/// The dashboard is three cards side by side, and each hugs its own content:
/// the player's title column, the weather's readout, the calendar's day strip.
/// Their combined width is therefore not a constant — it moves with the
/// track's name, the city, and the next meeting — which is how cards ended up
/// painted past the slab's rounded edge: the row needed more than the module
/// had, and the only thing left to give was the cards' own frames.
///
/// Two things keep that from happening.
///
/// **One card is elastic.** The player's column takes whatever the other two
/// leave — it already did, that is what its `layoutPriority` is for — and it
/// gives the width back when the row is tight, truncating its own title and
/// artist instead of pushing its neighbours out of the panel. The other two
/// are deliberately rigid: their cells and readings are what make them
/// legible at a glance, and a squeezed one reads as a bug rather than as a
/// smaller card.
///
/// **The two rigid cards have minimums, and the slab is never narrower than
/// they need.** Every width below is the atom end of the card — a cap, a
/// measured glyph, a cell — summed worst-case, so `minimumContentWidth` is a
/// number the row can always be laid out at with both rigid cards intact. The
/// compact arrangement exists for the widths below the roomy one's minimum:
/// on a narrow display, or at a narrow "Open width" preference, the cards step
/// down together instead of being crushed.
///
/// The string and glyph widths were measured against the same fonts the view
/// asks SwiftUI for (`.system(size:weight:design:.rounded)`, with monospaced
/// digits where the view uses them) and rounded up:
///
/// - the widest weather symbol box is `cloud.sun.fill`, 53pt at a 36pt point
///   size and 45pt at 30pt;
/// - the temperature is the widest reading on the card, 117.5pt for "100°F" at
///   38pt (99.2pt at 32pt), against the city and condition lines' 120pt cap;
/// - the metrics column is an 18pt glyph frame, an 8pt gap and "100 km/h" at
///   14pt (67pt);
/// - the calendar's widest month label is 70pt ("sept." at the 27pt month
///   size; the abbreviated month is at most four characters);
/// - a day cell is its content, and 22.7pt at 17pt monospaced digits (a
///   two-digit number) beats the cell's own 20pt floor;
/// - the next-event line's fixed front is a 16pt glyph, an 8pt gap, "10:30 AM"
///   at 13pt (66pt) and another 8pt gap; its title is capped;
/// - the player's rigid part is its 88pt cover, the 12pt gap beside it, and
///   the transport row (three 32pt buttons and two 16pt gaps = 128pt).
///
/// Values are shared with the view rather than restated there — the caps, the
/// glyph sizes, the day-cell sizes and the spaces between the cards all come
/// from the arrangement below, so a change to one of them cannot leave this
/// arithmetic describing a layout that no longer exists.
///
/// The arithmetic models those three cards, because they are what the row is
/// built around and each is wider than any of the optional widgets (System,
/// Batteries, Timer — the widest of those is under the player's *minimum*). A
/// dashboard made of different widgets is therefore held to a requirement that
/// is larger than it needs, which costs it nothing: every number below belongs
/// to a card that is not on screen.
struct HomeDashboardSizing: Equatable {
    /// Which arrangement to draw: everything at the size the dashboard was
    /// tuned at, or the stepped-down version for a slab that cannot hold it.
    enum Arrangement: String {
        case roomy
        case compact
    }

    let arrangement: Arrangement

    // MARK: Player

    /// Ceiling on the marquee's width. The marquee clips itself to whatever
    /// the layout offers, so this is a cap and not a size — but the card's
    /// roomy ideal is this cap, which is why it is here rather than inline.
    ///
    /// It is deliberately modest: the player card is the row's elastic card,
    /// so what it is given is what the other two cards leave it, and the
    /// weather card spends its own share on the wind/precipitation/humidity
    /// column rather than on the row's spare width.
    let marqueeWidth: CGFloat
    /// Ceiling on the artist line under the title.
    let artistWidth: CGFloat
    /// Gap between the cover and the title column. The transport row is
    /// pinned to that column's leading edge rather than centred under the
    /// text, so this gap is also the constant distance from the cover's rim
    /// to the buttons, whatever track is playing.
    let coverGap: CGFloat

    /// The cover's side, in both arrangements. Deliberately not stepped down:
    /// it is the tallest thing on the dashboard, so shrinking it would move
    /// the fitted row height — and with it the slab — every time the cards
    /// changed arrangement, which is a much louder change than the card
    /// getting narrower.
    static let coverArtSize: CGFloat = 88

    // MARK: Weather

    /// Point size of the weather glyph.
    let weatherGlyphSize: CGFloat
    /// Point size of the temperature — the card's loudest reading.
    let temperatureSize: CGFloat
    /// Cap on the city and condition lines.
    let weatherTextWidth: CGFloat
    /// Whether the card carries its wind/precipitation/humidity column, its
    /// third register. The compact arrangement drops it: it is the widest
    /// thing on the card, the third place on screen the same three numbers
    /// appear, and the detail screen behind a tap has them all.
    let showsWeatherMetrics: Bool

    // MARK: Calendar

    /// Point size of the month label above the day strip.
    let monthSize: CGFloat

    /// The five day cells: their point sizes, and the width each cell is given.
    struct DayStrip: Equatable {
        let todayWeekdaySize: CGFloat
        let todayNumberSize: CGFloat
        let otherWeekdaySize: CGFloat
        let otherNumberSize: CGFloat
        /// Width of today's cell. At least the widest content it holds — the
        /// 12pt "WED" is 29pt and the 22pt number is 30.1pt, so the roomy
        /// arrangement's 32 is the floor that fits both.
        let todayCellWidth: CGFloat
        /// Width of one of the four neighbouring cells. 17pt monospaced digits
        /// measure 22.7pt for a two-digit day, past the 20pt it was floored at.
        let otherCellWidth: CGFloat
        /// Gap between cells.
        let cellGap: CGFloat

        /// The strip's own width: five cells and the gaps between them.
        var width: CGFloat {
            todayCellWidth + otherCellWidth * 4 + cellGap * 4
        }
    }

    let dayStrip: DayStrip
    /// Cap on the next event's title.
    let eventTitleWidth: CGFloat

    // MARK: Shared

    /// Space inside each card, horizontally.
    let panePadding: CGFloat
    /// Space between two cards.
    let paneGap: CGFloat
    /// Space between the weather glyph, its readout and its metrics column.
    let readoutGap: CGFloat

    // MARK: - Measured atoms

    /// Width the weather glyph takes at `weatherGlyphSize`.
    private var weatherGlyphWidth: CGFloat { arrangement == .roomy ? 53 : 45 }
    /// Width of the widest temperature string at `temperatureSize`.
    private var temperatureWidth: CGFloat { arrangement == .roomy ? 118 : 105 }
    /// The metrics column: an 18pt glyph frame, an 8pt gap, and "100 km/h".
    private var metricsWidth: CGFloat { 18 + 8 + 70 }
    /// Widest abbreviated month label.
    private var monthWidth: CGFloat { 70 }
    /// The next-event line's fixed front: glyph, gap, time, gap.
    private var eventPrefixWidth: CGFloat { 16 + 8 + 68 + 8 }
    /// Width of the next-event line inside its card.
    private var eventLineWidth: CGFloat { eventPrefixWidth + eventTitleWidth }
    /// The transport row: three 32pt buttons and two 16pt gaps. The player's
    /// other rigid part, and the same in both arrangements.
    private var transportWidth: CGFloat { 3 * 32 + 2 * 16 }

    // MARK: - Minimums

    /// The player card's rigid part. Its title column can shrink to nothing —
    /// the marquee clips to whatever it is offered — but the cover cannot, and
    /// neither can the transport row beside it.
    var musicMinimumWidth: CGFloat {
        panePadding * 2 + Self.coverArtSize + coverGap + transportWidth
    }

    /// The widest the player card has any use for: its cover, the title
    /// column at its own cap, and the padding around them.
    ///
    /// Past this the card can only grow *empty*. It is still the row's elastic
    /// card — it gives width back when the row is tight — but the position it
    /// used to take was unbounded: with the dashboard row on a wide panel it
    /// took every spare point the other two cards left, so most of the player
    /// card's right side was a hole between the transport row and its own
    /// edge (measured: drawn content stops at ~320pt while the card reached
    /// 886pt on a 1500pt row).
    ///
    /// This is that cap, and it is the card's target: the elastic card fills
    /// whatever the two beside it leave, up to here. The roomy slab leaves it
    /// a little short of the cap — 326 of the 336 — because the row is full at
    /// that width, which is the point: the weather card keeps its metrics
    /// column and the player's card is exactly what is left (see
    /// `HomeDashboardView.musicPane`).
    var musicMaximumWidth: CGFloat {
        panePadding * 2 + Self.coverArtSize + coverGap + marqueeWidth
    }

    /// The weather card's minimum: glyph, the wider of the temperature and the
    /// capped text lines, and the metrics column where it is showing.
    ///
    /// A third of the row, and rightly so: this card is the row's *rigid* one
    /// beside the player's, and it holds its own width — a reading that wraps
    /// or a cell that clips is worse than the player card's title losing a few
    /// points to the scroll. Its share is what the player card is not given.
    var weatherMinimumWidth: CGFloat {
        var width = panePadding * 2 + weatherGlyphWidth + readoutGap
        width += max(temperatureWidth, weatherTextWidth)
        if showsWeatherMetrics {
            width += readoutGap + metricsWidth
        }
        return width
    }

    /// The calendar card's minimum: the day strip, or the next-event line when
    /// that is the wider of the two. Whichever is wider is what the card
    /// measures, because the two are stacked.
    var calendarMinimumWidth: CGFloat {
        let strip = monthWidth + dayStrip.cellGap + dayStrip.width
        return panePadding * 2 + max(strip, eventLineWidth)
    }

    /// Every atom end summed: the player's cover and transport row, the
    /// weather's glyph, reading and metrics, the calendar's widest of its two
    /// registers, and the gaps between the three cards.
    var atomMinimumWidth: CGFloat {
        musicMinimumWidth + weatherMinimumWidth + calendarMinimumWidth + paneGap * 2
    }

    /// Band added to the atoms before an arrangement is compared with a real
    /// width.
    ///
    /// The atoms are measured and the sums are arithmetic, but the strings
    /// they cap are not: a locale's month name, a temperature that grows a
    /// character, a font that shifts a hair under a system update. Each of
    /// those moves the real minimum by a point or two in a direction this
    /// type cannot know, and the failure mode if they land the wrong way is
    /// the one this whole arrangement exists to prevent — a rigid card
    /// squeezed past its own content. 32pt is deliberately wider than the
    /// drift those can produce, and cheap: the alternative is measuring the
    /// dashboard at runtime, which is a second layout pass on every open.
    static let measurementSlack: CGFloat = 32

    /// The narrowest content width this arrangement may be given. Below it the
    /// row has nothing left to give but the rigid cards' own frames, which is
    /// the state this type exists to keep the panel out of.
    var minimumContentWidth: CGFloat { atomMinimumWidth + Self.measurementSlack }

    // MARK: - The arrangements

    /// The dashboard as it was tuned: the full-size glyph, the whole metrics
    /// column, a 180pt event title.
    static let roomy = HomeDashboardSizing(
        arrangement: .roomy,
        marqueeWidth: 220,
        artistWidth: 220,
        coverGap: 12,
        weatherGlyphSize: 36,
        temperatureSize: 38,
        weatherTextWidth: 120,
        showsWeatherMetrics: true,
        monthSize: 27,
        dayStrip: DayStrip(
            todayWeekdaySize: 12,
            todayNumberSize: 22,
            otherWeekdaySize: 10,
            otherNumberSize: 17,
            todayCellWidth: 32,
            otherCellWidth: 23,
            cellGap: 8
        ),
        eventTitleWidth: 180,
        panePadding: 8,
        paneGap: 8,
        readoutGap: 12
    )

    /// The same cards when the slab cannot hold the full size: a smaller
    /// glyph and temperature, capped city lines, no metrics column, a tighter
    /// day strip and a shorter event title. The cover art and the transport
    /// row stay — the player's minimum is what the row gives back to, and
    /// shrinking either of those is what would make a *roomy* dashboard look
    /// cramped instead of making a compact one look deliberate.
    static let compact = HomeDashboardSizing(
        arrangement: .compact,
        marqueeWidth: 168,
        artistWidth: 168,
        coverGap: 12,
        weatherGlyphSize: 30,
        temperatureSize: 32,
        weatherTextWidth: 96,
        showsWeatherMetrics: false,
        monthSize: 27,
        dayStrip: DayStrip(
            todayWeekdaySize: 11,
            todayNumberSize: 19,
            otherWeekdaySize: 9.5,
            otherNumberSize: 15,
            todayCellWidth: 28,
            otherCellWidth: 20,
            cellGap: 6
        ),
        eventTitleWidth: 120,
        panePadding: 8,
        paneGap: 6,
        readoutGap: 10
    )

    /// The arrangement to draw at this content width: the roomiest one that
    /// fits. Stepping *down* rather than squeezing is the whole point — the
    /// roomy cards where there is width for them, the compact ones below it.
    static func sizing(forContentWidth width: CGFloat) -> HomeDashboardSizing {
        width >= roomy.minimumContentWidth ? .roomy : .compact
    }

    /// The slab width this arrangement needs, given the module's side gutters.
    /// `NotchSizing.minimumHomeWidth` is built from the compact one, so the
    /// panel can always be shown at a width the cards fit.
    func minimumSlabWidth(contentSideInset: CGFloat) -> CGFloat {
        minimumContentWidth + contentSideInset * 2
    }
}
