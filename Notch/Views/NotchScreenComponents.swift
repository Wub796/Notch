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
        static let card: CGFloat = 18
        /// Anything sitting inside a card.
        static let tile: CGFloat = 12
        /// Small square glyph holders and thumbnails.
        static let thumb: CGFloat = 8
    }

    /// The spacing ladder. Screens use these rather than arbitrary numbers so
    /// the rhythm carries from one panel to the next.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 22
    }
}

extension View {
    /// The one card treatment: the glass surface, a hairline, and the shared
    /// radius. Everything that used to hand-roll a `RoundedRectangle` fill
    /// plus a stroke at whatever radius it felt like now says this instead.
    func notchCard(
        radius: CGFloat = NotchTheme.Radius.card,
        isHighlighted: Bool = false,
        tint: Color? = nil
    ) -> some View {
        background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill((tint ?? Color.accentColor).opacity(0.12))
            }
        }
    }
}

extension View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
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
        Button(action: action) {
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
                        : NotchTheme.surface.opacity(isHovering ? 1.8 : 1)
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
