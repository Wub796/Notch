import AppKit
import SwiftUI

/// Expanded music module per the reference: large artwork with a soft glow,
/// track metadata with a monogram artist row, a synced-lyrics panel, the
/// seekable progress bar, transport, and the bottom heart/shuffle row.
struct MediaPlayerView: View {
    let state: NotchState
    let namespace: Namespace.ID

    private var media: MediaController { state.media }

    @State private var showLyrics = true
    @State private var isFavorite = false
    @State private var shuffleOn = false

    var body: some View {
        // Budget: NotchState.moduleContentSize, about 132pt tall at the
        // default panel size. Artwork 64 plus the progress and transport rows
        // and their 6pt gaps fills it, so the lyric line and the extra
        // action row live in the lyrics column beside the artwork rather than
        // stacking below it.
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 20) {
                artwork

                VStack(alignment: .leading, spacing: 5) {
                    MarqueeText(
                        text: media.track?.title ?? "Nothing Playing",
                        font: .system(size: 20, weight: .black, design: .rounded),
                        width: 200
                    )
                    .foregroundStyle(NotchTheme.inkPrimary)

                    artistRow

                    if let reason = media.emptyStateReason {
                        // Nothing is showing for a reason the user can act on;
                        // "Unknown Album" under "Nothing Playing" told them
                        // nothing at all.
                        Text(reason)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchTheme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3)
                    } else {
                        Text(media.track?.album ?? "")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(NotchTheme.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showLyrics {
                    LyricsView(lyrics: media.lyrics, accent: media.accent) { time in
                        media.seek(to: time + 0.05)
                    }
                    .frame(width: 200)
                } else {
                    // Without the lyrics column the current line and the
                    // secondary actions take its place, so the panel keeps the
                    // same shape either way.
                    VStack(alignment: .leading, spacing: 8) {
                        lyricLine
                        bottomActions
                        Spacer(minLength: 0)
                    }
                    .frame(width: 200, alignment: .leading)
                }
            }

            progressRow

            transportRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .frame(width: 64, height: 64)
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
        }
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
                showLyrics ? "list.bullet.rectangle.fill" : "list.bullet.rectangle",
                size: 15,
                label: showLyrics ? "Hide lyrics panel" : "Show lyrics panel",
                tint: showLyrics ? nil : NotchTheme.inkMuted
            ) {
                withAnimation(NotchAnimations.content) {
                    showLyrics.toggle()
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
                    .frame(width: 34, height: 34)
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

    static func timeString(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
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
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 34, alignment: .trailing)

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
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 38, alignment: .leading)
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
