import SwiftUI

/// Single-line text that scrolls horizontally when it doesn't fit
/// (boring.notch-style). Falls back to tail truncation under Reduce Motion.
struct MarqueeText: View {
    let text: String
    let font: Font
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0

    private var needsScrolling: Bool {
        textWidth > width && !reduceMotion
    }

    var body: some View {
        Group {
            if needsScrolling {
                MarqueeScroller(text: text, font: font, textWidth: textWidth)
                    .id(text)
            } else {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .background {
            // Invisible measurement copy; re-measures when the text changes.
            Text(text)
                .font(font)
                .fixedSize()
                .background {
                    GeometryReader { proxy in
                        Color.clear.onAppear { textWidth = proxy.size.width }
                    }
                }
                .hidden()
                .id(text)
        }
        .accessibilityLabel(text)
    }
}

private struct MarqueeScroller: View {
    let text: String
    let font: Font
    let textWidth: CGFloat

    @State private var animate = false

    private static let gap: CGFloat = 28
    private static let pointsPerSecond: Double = 32

    var body: some View {
        HStack(spacing: Self.gap) {
            Text(text).font(font).fixedSize()
            Text(text).font(font).fixedSize()
        }
        .offset(x: animate ? -(textWidth + Self.gap) : 0)
        .animation(
            .linear(duration: Double(textWidth + Self.gap) / Self.pointsPerSecond)
                .delay(1.2)
                .repeatForever(autoreverses: false),
            value: animate
        )
        .onAppear { animate = true }
    }
}
