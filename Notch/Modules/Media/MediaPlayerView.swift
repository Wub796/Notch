import AppKit
import SwiftUI

/// Expanded music module per the reference: large artwork with a soft glow,
/// track metadata with a monogram artist row, a synced-lyrics panel, the
/// seekable progress bar, transport, and the bottom heart/shuffle row.
struct MediaPlayerView: View {
    let state: NotchState
    let namespace: Namespace.ID

    private var media: MediaController { state.media }

    @State private var isFavorite = false
    @State private var shuffleOn = false

    var body: some View {
        // Budget: `NotchState.moduleContentSize`, about 498 x 250. Metadata
        // row 72, scrubber 22, lyrics or queue 30, transport 46, actions 28,
        // with 12pt gaps.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                artwork

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        text: media.track?.title ?? "Nothing Playing",
                        font: .system(size: 20, weight: .bold, design: .rounded),
                        width: 210
                    )
                    .foregroundStyle(NotchTheme.inkPrimary)

                    artistRow

                    if let reason = media.emptyStateReason {
                        Text(reason)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchTheme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                    } else if let followers = media.followersLabel {
                        Text(followers)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkMuted)
                            .lineLimit(1)
                    } else if let album = media.track?.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                upNextCard
            }
            .frame(height: 72)

            progressRow

            secondaryRow

            if state.mediaShowsFullLyrics {
                LyricsView(lyrics: media.lyrics, accent: media.accent) { time in
                    media.seek(to: time + 0.05)
                }
                .frame(height: 104)
                .transition(.opacity)
            }

            transportRow
                .frame(maxWidth: .infinity)

            bottomActions
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// What plays next, from the connected player's own queue. Absent unless
    /// Spotify is connected — nothing else exposes a queue.
    @ViewBuilder
    private var upNextCard: some View {
        if let next = media.upNext {
            HStack(spacing: 8) {
                Group {
                    if let art = next.artwork {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(NotchTheme.surfaceHover)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    Text("UP NEXT")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(NotchTheme.inkMuted)
                    Text(next.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                    Text(next.artist)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                }
                .frame(width: 100, alignment: .leading)
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NotchTheme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Up next: \(next.title) by \(next.artist)")
        }
    }

    /// The row under the scrubber: the lyrics, or the queue.
    ///
    /// Lyrics lost their home when the panel narrowed — the side column no
    /// longer fits at 498pt — and the one-line fallback only appeared when
    /// Spotify had nothing queued, so with an account connected they never
    /// showed at all. It is the live line again by default, with the queue
    /// when there are no lyrics — and the list button in the transport row
    /// opens the full scrolling panel, which grows the whole player.
    @ViewBuilder
    private var secondaryRow: some View {
        Group {
            if media.lyrics.isSynced, !media.lyrics.lines.isEmpty {
                lyricStrip
            } else if media.queue.count > 1 {
                queueChips
            } else {
                lyricLine
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 30)
    }

    /// The live line with the one after it trailing behind, so there is a hint
    /// of where the song is going rather than a single word in isolation.
    private var lyricStrip: some View {
        let index = media.lyrics.currentIndex
        let current = index.map { media.lyrics.lines[$0].text } ?? ""
        let next = index
            .map { $0 + 1 }
            .flatMap { media.lyrics.lines.indices.contains($0) ? media.lyrics.lines[$0].text : nil }

        return HStack(spacing: 10) {
            Text(current.isEmpty ? "♪" : current)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(media.accent)
                .lineLimit(1)
                .contentTransition(.opacity)

            if let next, !next.isEmpty {
                Text(next)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .animation(.notchSpring, value: media.lyrics.currentIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lyrics")
        .accessibilityValue(current)
    }

    /// The queue as chips: every one is a track that is genuinely coming.
    private var queueChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(media.queue.dropFirst().prefix(6).enumerated()),
                        id: \.offset) { _, item in
                    HStack(spacing: 5) {
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(media.accent)
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkPrimary)
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(NotchTheme.surface))
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Artwork & metadata

    private var artwork: some View {
        Group {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NotchTheme.surface)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .shadow(color: media.accent.opacity(0.5), radius: 16, y: 6)
    }

    private var artistRow: some View {
        HStack(spacing: 6) {
            // Monogram avatar stands in for the reference's artist photo.
            Text(String(media.track?.artist.prefix(1) ?? "?").uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(NotchTheme.surfaceHover))

            Text(media.track?.artist ?? "Unknown Artist")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)

            if media.track != nil {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Verified artist")
            }

            Spacer(minLength: 0)
        }
        // The glyphs cannot compress the way the name can, so without this the
        // badge wraps onto its own line when the column gets tight.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Progress & lyrics

    private var progressRow: some View {
        ScrubberBar(
            duration: media.track?.duration ?? 0,
            elapsed: media.displayedElapsed,
            accent: media.accent
        ) { target in
            media.seek(to: target)
        }
    }

    /// The reference's centered lyric line — the live synced line, tinted.
    private var lyricLine: some View {
        Group {
            if let current = media.lyrics.currentLine?.text, !current.isEmpty {
                Text(current)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(media.accent)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            } else {
                Text("♪")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NotchTheme.inkMuted.opacity(0.5))
            }
        }
        .frame(height: 20)
        .animation(.notchSpring, value: media.lyrics.currentIndex)
    }

    // MARK: - Transport

    private var transportRow: some View {
        HStack(spacing: 24) {
            transportIcon(
                state.mediaShowsFullLyrics
                    ? "list.bullet.rectangle.fill"
                    : "list.bullet.rectangle",
                size: 15,
                label: state.mediaShowsFullLyrics ? "Hide full lyrics" : "Show full lyrics",
                tint: state.mediaShowsFullLyrics ? nil : NotchTheme.inkMuted
            ) {
                withAnimation(NotchAnimations.content) {
                    state.mediaShowsFullLyrics.toggle()
                }
            }

            transportIcon(
                "backward.fill",
                size: 16,
                label: "Previous track",
                isEnabled: media.canControlTransport
            ) {
                media.previousTrack()
            }

            Button {
                media.togglePlayPause()
            } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .hoverLift(1.08)
            .disabled(!media.canControlTransport)
            .opacity(media.canControlTransport ? 1 : 0.4)
            .accessibilityLabel(media.isPlaying ? "Pause" : "Play")

            transportIcon(
                "forward.fill",
                size: 16,
                label: "Next track",
                isEnabled: media.canControlTransport
            ) {
                media.nextTrack()
            }

            transportIcon(state.audio.currentSymbol, size: 15, label: "Switch audio output") {
                state.audio.cycleToNextDevice()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomActions: some View {
        HStack(spacing: 24) {
            transportIcon(
                isFavorite ? "heart.fill" : "heart",
                size: 14,
                label: isFavorite ? "Remove from favorites" : "Favorite",
                tint: isFavorite ? .red : nil
            ) {
                withAnimation(NotchAnimations.content) {
                    isFavorite.toggle()
                }
            }

            transportIcon(
                shuffleOn ? "shuffle.fill" : "shuffle",
                size: 14,
                label: shuffleOn ? "Turn off shuffle" : "Shuffle",
                tint: shuffleOn ? .blue : nil
            ) {
                withAnimation(NotchAnimations.content) {
                    shuffleOn.toggle()
                }
            }
        }
    }

    private func transportIcon(
        _ systemImage: String,
        size: CGFloat,
        label: String,
        tint: Color? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint ?? NotchTheme.inkPrimary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .modifier(HoverIconModifier())
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    /// "3:07", or "1:02:33" once a track runs past an hour — podcasts and DJ
    /// sets did the latter and came out as "83:20".
    static func timeString(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// Seekable progress bar in the reference style: white timestamps, a solid
/// accent fill over a dark track, growing on hover with a knob while dragging.
struct ScrubberBar: View {
    let duration: TimeInterval
    let elapsed: TimeInterval
    let accent: Color
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var showRemaining = true

    private var playbackFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    private var displayedFraction: Double {
        dragFraction ?? playbackFraction
    }

    private var isInteracting: Bool {
        hovering || dragFraction != nil
    }

    /// While dragging, the readout follows the drag rather than playback, so
    /// the number under the thumb is the position you are about to seek to.
    private var remaining: TimeInterval {
        guard duration > 0 else { return 0 }
        let position = dragFraction.map { $0 * duration } ?? elapsed
        return max(duration - min(position, duration), 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(MediaPlayerView.timeString(dragFraction.map { $0 * duration } ?? elapsed))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
                // Sized by its content: a fixed 34 clipped anything past
                // "9:59", so long tracks and podcasts lost digits.
                .fixedSize()

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(width * displayedFraction, 0))

                    if isInteracting {
                        Circle()
                            .fill(.white)
                            .frame(width: 11, height: 11)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .offset(x: max(width * displayedFraction - 5.5, 0))
                            .transition(.opacity)
                    }
                }
                .frame(height: isInteracting ? 7 : 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0, width > 0 else { return }
                            dragFraction = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { _ in
                            if let fraction = dragFraction {
                                onSeek(fraction * duration)
                            }
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 14)
            .animation(.notchSpring, value: isInteracting)
            .onHover { hovering = $0 }

            Text(showRemaining
                ? "−" + MediaPlayerView.timeString(remaining)
                : MediaPlayerView.timeString(duration))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
                .fixedSize()
                .contentShape(Rectangle())
                .onTapGesture { showRemaining.toggle() }
                .accessibilityLabel(showRemaining ? "Time remaining" : "Track duration")
                .accessibilityHint("Click to toggle between remaining and total time")
        }
        .opacity(duration > 0 ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(MediaPlayerView.timeString(elapsed)) of \(MediaPlayerView.timeString(duration))"
        )
    }
}
