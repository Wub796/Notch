import SwiftUI

/// Timestamp-synchronized lyrics with automatic vertical scrolling. The live
/// line stays centered, highlighted in the artwork accent, and tapping any
/// synced line seeks playback to it.
struct LyricsView: View {
    let lyrics: LyricsEngine
    let accent: Color
    let onSelect: (TimeInterval) -> Void

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
                .foregroundStyle(NotchTheme.inkMuted)
                .symbolEffect(.variableColor, isActive: lyrics.isLoading)
            Text(lyrics.isLoading ? "Finding lyrics…" : "No lyrics available")
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.inkMuted)
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
                            .font(.system(
                                size: isCurrent ? 13 : 11.5,
                                weight: isCurrent ? .bold : .regular
                            ))
                            .foregroundStyle(isCurrent ? accent : NotchTheme.inkPrimary.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .id(line.id)
                            .animation(.notchSpring, value: isCurrent)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard lyrics.isSynced else { return }
                                onSelect(line.time)
                            }
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
