import SwiftUI

/// Single-line text that scrolls horizontally when it doesn't fit. Text that
/// fits is rendered exactly once and never moves; longer text runs a two-copy
/// marquee that loops seamlessly.
///
/// Two things here are deliberate, because both are ways this used to fail.
///
/// `width` is a *cap*, not the width the marquee draws at. The space a title
/// actually gets comes from the layout, and it is routinely narrower than the
/// number passed in — the card it sits in, the artwork tile beside it and the
/// column's padding all come off it first. Clipping to the cap alone is how a
/// long title ended up sliced mid-glyph without ever starting to scroll: the
/// marquee believed it had 220pt, decided the text fitted, and drew it into
/// whatever the row really offered. Here the frame is flexible up to the cap,
/// the width it ends up with is measured, and both the scroll decision and the
/// clip use that — so "does it fit" and "is it on screen" can never disagree.
///
/// The position is a **function of the clock**, not an animation. A
/// `repeatForever` animation is started once and then never re-derived, so
/// anything that changes underneath it — the measured width landing a frame
/// later, a new track swapping the text, the panel's own spring while the
/// notch opens — leaves it retargeted, mis-phased or simply dropped, and a
/// dropped animation is a title that sits still and clipped. A timeline can't
/// be dropped: every frame asks the clock where the text should be, so the
/// marquee either scrolls or the view is not on screen.
struct MarqueeText: View {
    let text: String
    let font: Font

    /// The widest the marquee may draw. The layout may offer less, in which
    /// case it takes that instead; there is no way for the caller to know the
    /// real column width, so this must not be treated as an exact size.
    var width: CGFloat = .infinity

    /// Letterspacing applied to both the measuring and the scrolling copies,
    /// so a tracked style measures at its tracked width and scrolls with it.
    var tracking: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var drawnWidth: CGFloat = 0

    /// When this run of the marquee began. Reset whenever the text or its
    /// measured width changes, so every track starts from the home position
    /// and every loop is timed against the width it is actually scrolling.
    @State private var startedAt = Date()

    private static let gap: CGFloat = 32
    private static let pointsPerSecond: Double = 28

    /// A beat before the text starts moving, so a title that changes while the
    /// panel is open is readable from its first word.
    private static let leadIn: Double = 0.9

    /// The width the text is actually drawn into: whatever the layout offered,
    /// capped by the caller. Falls back to the cap for the first pass, before
    /// the measurement lands.
    private var clipWidth: CGFloat {
        drawnWidth > 0 ? min(width, drawnWidth) : width
    }

    private var shouldScroll: Bool {
        textWidth > clipWidth && !reduceMotion
    }

    /// How far one copy travels before the second copy is exactly home again —
    /// the two copies plus the gap between them, which is one full cycle.
    private var travel: CGFloat { textWidth + Self.gap }

    private var loopDuration: Double { Double(travel) / Self.pointsPerSecond }

    private func distance(at now: Date) -> CGFloat {
        guard shouldScroll, travel > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(startedAt) - Self.leadIn
        guard elapsed > 0 else { return 0 }
        let phase = elapsed.truncatingRemainder(dividingBy: loopDuration)
        return CGFloat(phase * Self.pointsPerSecond)
    }

    private var copy: some View {
        Text(text)
            .font(font)
            .tracking(tracking)
            .fixedSize()
    }

    /// One copy carrying the measurement of its own natural width.
    private var measuredCopy: some View {
        copy.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { textWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        textWidth = newWidth
                    }
            }
        }
    }

    /// Measures the space the marquee was given, from inside its own frame: the
    /// flexible frame below settles at `min(offer, width)`, so this reads the
    /// drawn width rather than the cap.
    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { drawnWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in
                    drawnWidth = newWidth
                }
        }
    }

    private func restart() {
        startedAt = Date()
    }

    var body: some View {
        Group {
            if shouldScroll {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    HStack(spacing: Self.gap) {
                        measuredCopy
                        copy
                    }
                    .offset(x: -distance(at: context.date))
                }
            } else {
                measuredCopy
            }
        }
        .onAppear { restart() }
        // New text, or the same text measured for the first time: either way
        // the run that is in flight was timed against a different width, so it
        // starts again over.
        .onChange(of: text) { _, _ in restart() }
        .onChange(of: textWidth) { _, _ in restart() }
        .onChange(of: shouldScroll) { _, _ in restart() }
        .frame(maxWidth: width, alignment: .leading)
        .clipped()
        .background(widthReader)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
