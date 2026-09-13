import SwiftUI

/// Single-line text that scrolls horizontally when it doesn't fit. Titles that
/// fit are rendered exactly once; long titles use two copies for a seamless
/// looping marquee.
struct MarqueeText: View {
    let text: String
    let font: Font
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var animate = false

    private static let gap: CGFloat = 32
    private static let pointsPerSecond: Double = 22

    private var shouldScroll: Bool {
        textWidth > width && !reduceMotion
    }

    private var measuredText: some View {
        Text(text)
            .font(font)
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { textWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            textWidth = newWidth
                        }
                }
            }
    }

    var body: some View {
        Group {
            if shouldScroll {
                HStack(spacing: Self.gap) {
                    measuredText
                    Text(text)
                        .font(font)
                        .fixedSize()
                }
                .offset(x: animate ? -(textWidth + Self.gap) : 0)
            } else {
                measuredText
            }
        }
        .animation(
            shouldScroll
                ? .linear(
                    duration: Double(textWidth + Self.gap) / Self.pointsPerSecond
                )
                .delay(1.0)
                .repeatForever(autoreverses: false)
                : nil,
            value: animate
        )
        .onAppear {
            if shouldScroll { animate = true }
        }
        // A new text swaps in while the loop is mid-flight, the offset would
        // jump to wherever the old scroll happened to be — and worse, the
        // `measuredText` width changes under it. Restarting the run (offset 0
        // → scroll) makes every track change start the marquee from its home
        // position, which is what the references do.
        .onChange(of: text) { _, _ in
            // Snap the offset home with no animation at all. Assigning `false`
            // plainly let the `.repeatForever` linear curve pick the reset up,
            // so every track change scrolled the old title slowly *backwards*
            // before the new one started.
            withAnimation(.none) { animate = false }
            // Let the reset land before restarting, so the new run begins from
            // offset 0 rather than retargeting mid-loop. Re-checked here
            // because the new text may not need to scroll at all.
            DispatchQueue.main.async {
                guard shouldScroll else { return }
                animate = true
            }
        }
        .onChange(of: shouldScroll) { _, scrolling in
            animate = scrolling
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
