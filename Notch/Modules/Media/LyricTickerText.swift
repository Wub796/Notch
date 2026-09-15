import SwiftUI

/// One lyric line in a fixed-width row under the closed notch.
///
/// A line that fits is centred. One that does not is never cut off with an
/// ellipsis — the words are the point — so it scrolls, once, over the time it
/// is sung: it holds at its start long enough to begin reading, then glides so
/// the last word arrives about as the line ends. A looping marquee was the
/// obvious alternative and the wrong one: it restarts mid-read and has nothing
/// to do with when the words are sung.
struct LyricTickerText: View {
    let text: String
    /// How long the line is on screen, which paces the scroll.
    let duration: TimeInterval
    let font: Font
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var hasScrolled = false

    /// The fastest the text may travel. A short line with a lot of overflow
    /// would otherwise whip past faster than it can be read; it simply does
    /// not reach its end before the next line takes over.
    private static let maxSpeed: CGFloat = 70

    /// Soft edges while scrolling, so words slide in and out of the row
    /// rather than being sliced by it. The text is padded by the same amount,
    /// so its first and last letters come to rest fully visible.
    private static let edgeFade: CGFloat = 10

    private var overflow: CGFloat {
        max(textWidth - width, 0)
    }

    var body: some View {
        Group {
            if reduceMotion {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: width)
            } else {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, Self.edgeFade)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        textWidth = newWidth
                        startScrollIfNeeded()
                    }
                    .offset(x: hasScrolled ? -overflow : 0)
                    .frame(width: width, alignment: overflow > 0 ? .leading : .center)
                    .mask { fadeMask }
            }
        }
        .clipped()
    }

    @ViewBuilder
    private var fadeMask: some View {
        if overflow > 0 {
            let fade = Self.edgeFade / max(width, 1)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: fade),
                    .init(color: .black, location: 1 - fade),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Rectangle()
        }
    }

    private func startScrollIfNeeded() {
        guard !hasScrolled, overflow > 0 else { return }
        let hold = min(0.7, duration * 0.2)
        let travel = max(duration - hold - 0.5, Double(overflow / Self.maxSpeed))
        withAnimation(.linear(duration: travel).delay(hold)) {
            hasScrolled = true
        }
    }
}
