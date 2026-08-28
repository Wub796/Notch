import SwiftUI

/// Timestamp-synchronized lyrics with automatic vertical scrolling: the live
/// line stays centered and highlighted as playback advances.
struct LyricsView: View {
    let lyrics: LyricsEngine

    var body: some View {
        Group {
            if lyrics.lines.isEmpty {
                emptyState
            } else {
                lyricsScroller
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: lyrics.isLoading ? "ellipsis" : "quote.opening")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.3))
                .symbolEffect(.variableColor, isActive: lyrics.isLoading)
            Text(lyrics.isLoading ? "Finding lyrics…" : "No lyrics available")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lyricsScroller: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(lyrics.lines) { line in
                        let isCurrent = lyrics.currentIndex == line.id
                        Text(line.text)
                            .font(.system(size: isCurrent ? 13 : 11.5, weight: isCurrent ? .bold : .regular))
                            .foregroundStyle(.white.opacity(isCurrent ? 1.0 : 0.38))
                            .fixedSize(horizontal: false, vertical: true)
                            .id(line.id)
                            .animation(.notchSpring, value: isCurrent)
                    }
                }
                // Vertical padding lets the first/last lines reach center.
                .padding(.vertical, 70)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.15),
                        .init(color: .black, location: 0.85),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onChange(of: lyrics.currentIndex) { _, index in
                guard let index else { return }
                withAnimation(.notchSpring) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
}
