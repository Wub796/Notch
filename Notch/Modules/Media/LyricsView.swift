import SwiftUI

/// Timestamp-synchronized lyrics with automatic vertical scrolling. The live
/// line stays centered, highlighted in the artwork accent, and tapping any
/// synced line seeks playback to it.
struct LyricsView: View {
    let lyrics: LyricsEngine
    let accent: Color
    let onSelect: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LYRICS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(NotchTheme.inkMuted)
                .accessibilityAddTraits(.isHeader)

            Group {
                if lyrics.lines.isEmpty {
                    emptyState
                } else {
                    lyricsScroller
                }
            }
            .frame(maxHeight: .infinity)
        }
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

/// 3D perspective-tilted lyric view:
/// Shows the current active line prominent and bright in the center,
/// with the previous line faded and tilted upwards in 3D, and the next line
/// faded and tilted downwards in 3D.
struct ThreeDLyricsView: View {
    let lyrics: LyricsEngine
    let accent: Color
    var onSelect: ((TimeInterval) -> Void)? = nil

    private var currentIndex: Int? {
        lyrics.currentIndex
    }

    private var previousLine: LyricsEngine.Line? {
        guard let idx = currentIndex, idx > 0, lyrics.lines.indices.contains(idx - 1) else { return nil }
        return lyrics.lines[idx - 1]
    }

    private var currentLine: LyricsEngine.Line? {
        guard let idx = currentIndex, lyrics.lines.indices.contains(idx) else {
            return lyrics.lines.first
        }
        return lyrics.lines[idx]
    }

    private var nextLine: LyricsEngine.Line? {
        guard let idx = currentIndex, idx + 1 < lyrics.lines.count else {
            if currentIndex == nil && lyrics.lines.count > 1 {
                return lyrics.lines[1]
            }
            return nil
        }
        return lyrics.lines[idx + 1]
    }

    var body: some View {
        VStack(spacing: 3) {
            if lyrics.lines.isEmpty {
                if lyrics.isLoading {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                            .symbolEffect(.pulse)
                        Text("Finding lyrics…")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(NotchTheme.inkMuted)
                    .frame(height: 48)
                } else {
                    Spacer(minLength: 0)
                        .frame(height: 48)
                }
            } else {
                // 1. Previous Line (Faded, facing UP in 3D)
                Group {
                    if let prev = previousLine {
                        Text(prev.text)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary.opacity(0.4))
                            .lineLimit(1)
                            .rotation3DEffect(.degrees(24), axis: (x: 1, y: 0, z: 0), anchor: .bottom)
                            .scaleEffect(0.92)
                            .opacity(0.38)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect?(prev.time)
                            }
                    } else {
                        Text(" ")
                            .font(.system(size: 11.5))
                            .opacity(0)
                    }
                }
                .frame(height: 16)

                // 2. Current Line (Prominent, bright accent, centered)
                Group {
                    if let curr = currentLine {
                        Text(curr.text)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(accent == .white ? .white : accent)
                            .lineLimit(1)
                            .shadow(color: accent.opacity(0.32), radius: 5, x: 0, y: 1)
                            .contentTransition(.numericText())
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect?(curr.time)
                            }
                    } else {
                        Text("…")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
                }
                .frame(height: 20)
                .animation(.notchSpring, value: currentLine)

                // 3. Next Line (Faded, facing DOWN in 3D)
                Group {
                    if let next = nextLine {
                        Text(next.text)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary.opacity(0.4))
                            .lineLimit(1)
                            .rotation3DEffect(.degrees(-24), axis: (x: 1, y: 0, z: 0), anchor: .top)
                            .scaleEffect(0.92)
                            .opacity(0.38)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect?(next.time)
                            }
                    } else {
                        Text(" ")
                            .font(.system(size: 11.5))
                            .opacity(0)
                    }
                }
                .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}
