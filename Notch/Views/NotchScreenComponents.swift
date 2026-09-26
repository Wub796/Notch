import SwiftUI

/// The shared vocabulary every screen in the notch draws from.
///
/// Before this, each screen invented its own: thirty distinct font sizes and
/// seventeen corner radii across the panels, with the older modules running at
/// 8–10pt while the newer ones ran at 12–15pt. The result read as several
/// apps sharing a window. These are the sizes that survived that audit — one
/// step per job, and nothing between the steps.
extension Font {
    /// Screen titles: "Library", the greeting on Discover.
    static let notchDisplay = Font.system(size: 25, weight: .bold, design: .rounded)
    /// A panel's own headline, and the largest readings.
    static let notchTitle = Font.system(size: 19, weight: .bold, design: .rounded)
    /// Card titles, device names, a row's subject.
    static let notchHeadline = Font.system(size: 15, weight: .bold, design: .rounded)
    /// Primary rows and controls — the app's default.
    static let notchBody = Font.system(size: 13, weight: .semibold, design: .rounded)
    /// Supporting text beside a body row.
    static let notchCallout = Font.system(size: 12.5, weight: .medium, design: .rounded)
    /// Labels, counts, timestamps.
    static let notchCaption = Font.system(size: 11.5, weight: .medium, design: .rounded)
    /// Hints and explanations under a control.
    static let notchFootnote = Font.system(size: 10.5, weight: .medium, design: .rounded)
    /// Small all-caps section markers.
    static let notchEyebrow = Font.system(size: 9.5, weight: .heavy, design: .rounded)
}

extension NotchTheme {
    /// One radius per shape family, so a card is never 14 on one screen and
    /// 22 on the next.
    enum Radius {
        /// Panels and list rows.
        static let card: CGFloat = 22
        /// Anything sitting inside a card.
        static let tile: CGFloat = 15
        /// Small square glyph holders and thumbnails.
        static let thumb: CGFloat = 10
    }

    /// The spacing ladder, on a 4pt grid.
    ///
    /// Screens use these rather than arbitrary numbers so the rhythm carries
    /// from one panel to the next — but the rungs themselves also have to sit
    /// on the grid, and these used to be 5/9/13/17: every one of them `4n+1`,
    /// a point off. Nothing laid out with them could align to anything laid
    /// out with a plain 8 or 12, which is most of the app. macOS is built on
    /// 4pt, so these are now 4pt multiples and the two systems agree.
    enum Space {
        /// Hairline gaps — a glyph to its label.
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        /// Section breaks inside a screen.
        static let xxl: CGFloat = 32
    }

    /// The surface system.
    ///
    /// A flat fill on black reads as paint; a real surface reads as a pane of
    /// something. Surfaces here are defined by tone alone — a *gradient* fill,
    /// lighter at the top so it looks lit from above, and a tight shadow.
    /// There are deliberately no strokes: outlines around every card made the
    /// panel look like a wireframe of itself.
    ///
    /// Kept as tokens rather than hand-rolled per screen, because the moment
    /// two screens pick different opacities the whole thing stops reading as
    /// one material.
    enum Surface {
        /// A card sitting on the slab.
        static let fill = LinearGradient(
            colors: [.white.opacity(0.085), .white.opacity(0.035)],
            startPoint: .top,
            endPoint: .bottom
        )

        /// A control or tile sitting *inside* a card — quieter, or the nesting
        /// turns into a stack of competing panes.
        static let nestedFill = LinearGradient(
            colors: [.white.opacity(0.06), .white.opacity(0.025)],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Elevation. Tight and dark rather than wide and grey: a wide soft
        /// shadow on a near-black panel just fogs it.
        static let shadow = Color.black.opacity(0.45)
        static let shadowRadius: CGFloat = 12
        static let shadowY: CGFloat = 4
    }
}

extension View {
    /// The one card treatment: the surface, its shadow, and the shared radius.
    ///
    /// This used to draw *nothing at all* unless `isHighlighted` — the fill and
    /// the stroke the doc comment described had been removed, so every screen
    /// that said `.notchCard()` got an invisible card and the content sat
    /// directly on flat black. That is most of why the panels read as cheap:
    /// there was no material, only paint.
    func notchCard(
        radius: CGFloat = NotchTheme.Radius.card,
        isHighlighted: Bool = false,
        tint: Color? = nil,
        isElevated: Bool = true
    ) -> some View {
        modifier(NotchCardModifier(
            radius: radius,
            isHighlighted: isHighlighted,
            tint: tint,
            isElevated: isElevated
        ))
    }

    /// A quieter surface for something nested inside a card — a tile, a row, a
    /// control. Same material, dialled back so the nesting reads as depth
    /// rather than as two cards fighting.
    func notchTile(
        radius: CGFloat = NotchTheme.Radius.tile,
        isHighlighted: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(NotchCardModifier(
            radius: radius,
            isHighlighted: isHighlighted,
            tint: tint,
            isElevated: false,
            isNested: true
        ))
    }
}

/// The shared surface treatment behind `notchCard` / `notchTile`.
private struct NotchCardModifier: ViewModifier {
    let radius: CGFloat
    var isHighlighted: Bool = false
    var tint: Color? = nil
    var isElevated: Bool = true
    var isNested: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                // Base material. Reduce Transparency swaps the gradient for a
                // solid so the surface stops depending on what is behind it.
                if reduceTransparency {
                    shape.fill(Color.white.opacity(isNested ? 0.10 : 0.13))
                } else {
                    shape.fill(isNested
                        ? NotchTheme.Surface.nestedFill
                        : NotchTheme.Surface.fill)
                }

                // Selection wash, over the material rather than instead of it,
                // so a highlighted card is still made of the same stuff.
                // No stroke: the surface is defined by its fill alone, so a
                // selected card carries a slightly stronger wash instead.
                if isHighlighted {
                    shape.fill((tint ?? Color.accentColor).opacity(0.22))
                }
            }
            .compositingGroup()
            .shadow(
                color: isElevated ? NotchTheme.Surface.shadow : .clear,
                radius: NotchTheme.Surface.shadowRadius,
                y: NotchTheme.Surface.shadowY
            )
        }
    }
}

extension View {
    /// A row's entrance in a list that has just appeared.
    ///
    /// The panel opens onto a finished list, which reads as a picture rather
    /// than as something that arrived — so rows fade up in sequence instead of
    /// all at once. The step is deliberately small: a stagger you *notice* is
    /// a stagger that is too slow, and this list is seen many times a day.
    ///
    /// The total is capped, so a long clipboard history still finishes in a
    /// beat rather than crawling down the panel. Reduce Motion keeps the fade
    /// and drops the travel.
    func notchRowEntrance(_ index: Int) -> some View {
        modifier(RowEntranceModifier(index: index))
    }

    /// Softens the hard edge where a scrolling list runs into the panel.
    ///
    /// A list that is cut off mid-row at the bottom of the slab reads as
    /// broken; the same list dissolving into the glass reads as more of it
    /// being down there. The band is a fixed height rather than a fraction so
    /// a short list is not faded end to end.
    func notchScrollFade(_ length: CGFloat = 16) -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: length)

                Color.black

                LinearGradient(
                    colors: [.black, .black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: length)
            }
        }
    }

    /// The same, across a horizontal tray.
    func notchScrollFadeHorizontal(_ length: CGFloat = 16) -> some View {
        mask {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0), .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: length)

                Color.black

                LinearGradient(
                    colors: [.black, .black.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: length)
            }
        }
    }
}

/// Every screen's opening line: what it is, optionally a word about the state
/// it is in, and whatever controls belong to it on the right.
///
/// The dashboard is the one screen without it — it is a glance, not a place.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        // Trailing controls are centered against the whole title+subtitle
        // block. Baseline alignment pinned them to the subtitle's baseline,
        // which made a 26pt action button hang low beside a big screen
        // title instead of standing opposite it.
        HStack(alignment: .center, spacing: NotchTheme.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.notchDisplay)
                    // Letterspaced so the screen title reads as a header
                    // rather than a word sitting on top of its subtitle.
                    .tracking(1.5)
                    .foregroundStyle(NotchTheme.inkPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.notchCaption)
                        .tracking(0.4)
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: NotchTheme.Space.s)

            trailing()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// The shape an empty screen takes: a glyph, what is missing, and what to do
/// about it. Used wherever a module has nothing to show, so "nothing here"
/// looks deliberate rather than broken.
struct ScreenEmptyState: View {
    let symbol: String
    let title: String
    var caption: String?
    var tint: Color = NotchTheme.inkMuted

    /// Drives the quiet fade-settle entrance. Empty states are occasional-to-
    /// rare, so a brief entrance belongs; it must never bounce or pop.
    @State private var isPresented = false

    var body: some View {
        VStack(spacing: NotchTheme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(tint)

            Text(title)
                .font(.notchBody)
                .foregroundStyle(NotchTheme.inkSecondary)

            if let caption {
                Text(caption)
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scaleEffect(isPresented ? 1 : 0.97)
        .opacity(isPresented ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear {
            // House content spring; collapses to a 150ms fade under Reduce
            // Motion. Never scale(0) — nothing appears from nothing.
            withAnimation(NotchAnimations.content) {
                isPresented = true
            }
        }
    }
}

/// A small text button in the panel's own idiom — used for "Clear", "Clear
/// unpinned" and the like, which were three different treatments before.
struct ScreenTextButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = NotchTheme.inkSecondary
    /// Filled rather than quiet, for the one action a screen leads with.
    var isProminent = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            #if DEBUG
            // Same trace as `NotchHostingView.mouseDown`: a line here means the
            // click reached this button and its action ran, so a button that
            // does nothing without logging this never got the click at all.
            print("[Notch] tap: \(title)")
            #endif
            action()
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .bold))
                }
                Text(title)
                    .font(.notchCaption.weight(.semibold))
            }
            .foregroundStyle(isProminent ? .white : tint)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background {
                Capsule().fill(
                    isProminent
                        ? Color.accentColor.opacity(isHovering ? 1 : 0.88)
                        // `NotchTheme.surface` is `Color.clear`, so the quiet
                        // variant's hover fill used to multiply two zeroes and
                        // never appear. `surfaceHover` is the real 8% white.
                        : NotchTheme.surfaceHover.opacity(isHovering ? 1.8 : 1)
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in
            withAnimation(NotchAnimations.content) { isHovering = hovering }
        }
    }
}


/// Drives `notchRowEntrance`.
private struct RowEntranceModifier: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    /// 35ms between rows, and never more than 210ms of total lead-in.
    private var delay: Double {
        min(Double(index) * 0.035, 0.21)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                guard !shown else { return }
                withAnimation(
                    (reduceMotion ? NotchAnimations.reduced : NotchAnimations.content)
                        .delay(delay)
                ) {
                    shown = true
                }
            }
    }
}
