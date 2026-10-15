import SwiftUI

/// 3D perspective-tilted lyric view:
/// Shows the current active line prominent and bright in the center,
/// with the previous line faded and tilted upwards in 3D, and the next line
/// faded and tilted downwards in 3D.
struct ThreeDLyricsView: View {
    let lyrics: LyricsEngine
    let accent: Color
    var onSelect: ((TimeInterval) -> Void)? = nil
    /// Shown when there are no lyric lines: a hint when nothing is playing,
    /// or a "no lyrics" note when a track is loaded but has none. The blank
    /// 48pt spacer this replaces read as dead space in the middle of the
    /// player.
    var emptyMessage: String = "Lyrics appear here while music plays"

    private var currentIndex: Int? {
        lyrics.currentIndex
    }

    private var previousLine: LyricsEngine.Line? {
        guard let idx = currentIndex, idx > 0, lyrics.lines.indices.contains(idx - 1) else { return nil }
        return lyrics.lines[idx - 1]
    }

    /// The line being sung, or nothing at all.
    ///
    /// Deliberately not `lines.first` as a fallback. Before the first timestamp
    /// — the intro, which for a lot of songs is 15 seconds of music — the first
    /// line used to be drawn in the bright, bold "this is what you are hearing"
    /// slot, so the panel announced a line the singer had not reached yet and
    /// read as lyrics running ahead of the song. It belongs in the *upcoming*
    /// slot below until its moment comes.
    private var currentLine: LyricsEngine.Line? {
        guard let idx = currentIndex, lyrics.lines.indices.contains(idx) else { return nil }
        return lyrics.lines[idx]
    }

    /// The line after the current one — or, before anything has been sung, the
    /// first line waiting its turn.
    private var nextLine: LyricsEngine.Line? {
        guard let idx = currentIndex else { return lyrics.lines.first }
        guard idx + 1 < lyrics.lines.count else { return nil }
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
                    emptyState
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
        // Same slot, same reason as the flat view: the carousel replaces its
        // own empty message when the lyrics land, and used to do it abruptly.
        .animation(NotchAnimations.content, value: lyrics.lines.isEmpty)
    }

    /// What fills the 3D carousel when there are no lyric lines: a quiet
    /// one-line hint in the same slot, so the layout never collapses.
    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.quote")
                .font(.system(size: 10, weight: .semibold))
            Text(emptyMessage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(NotchTheme.inkMuted.opacity(0.9))
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(emptyMessage)
    }
}
