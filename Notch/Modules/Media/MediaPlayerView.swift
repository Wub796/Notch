import AppKit
import SwiftUI

/// Expanded music module per the reference: large artwork with a soft glow,
/// track metadata with the artist row underneath, the live lyric line, the
/// seekable progress bar, transport, and the bottom heart/shuffle row.
///
/// The reference's chip strip between the lyric and the transport is
/// deliberately absent — the rows below it moved up into that space rather
/// than leaving a band of empty panel behind.
struct MediaPlayerView: View {
    let state: NotchState
    let namespace: Namespace.ID

    private var media: MediaController { state.media }


    var body: some View {
        // Budget: `NotchState.moduleContentSize`, about 518 x 268 at the
        // default panel size. The sections are stacked with even air so the
        // transport and the heart/shuffle row always clear the slab's
        // rounded bottom edge — the module used to overflow its budget and
        // clip the bottom row.
        VStack(alignment: .leading, spacing: 10) {
            header

            if !media.isBrowserVideo {
                ThreeDLyricsView(
                    lyrics: media.lyrics,
                    accent: media.accent,
                    onSelect: { time in
                        media.seek(to: time + 0.05)
                    },
                    emptyMessage: media.hasTrack
                        ? "No lyrics found for this track"
                        : "Lyrics appear here while music plays"
                )
            }

            progressRow

            if state.mediaShowsFullLyrics && !media.isBrowserVideo {
                LyricsView(lyrics: media.lyrics, accent: media.accent) { time in
                    media.seek(to: time + 0.05)
                }
                .frame(height: 90)
                .transition(.opacity)
            }

            transportRow

            bottomActions
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.bottom, 18)
    }

    // MARK: - Active Audio State

    private var activeAudioApp: AudioAppMonitor.App? {
        state.audioApps.apps.first(where: \.isPlaying)
    }

    private var isBrowserVideo: Bool {
        media.isBrowserVideo
    }

    private var displayTitle: String {
        if let title = media.track?.title, !title.isEmpty {
            return title
        }
        if let active = activeAudioApp {
            return active.name
        }
        return "Nothing Playing"
    }

    private var displayArtist: String {
        if let artist = media.track?.artist, !artist.isEmpty {
            return artist
        }
        if activeAudioApp != nil {
            return "Active Audio"
        }
        return "Nothing is playing"
    }

    private var isAudioActive: Bool {
        media.isPlaying || activeAudioApp != nil
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            artwork

            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(
                    text: displayTitle,
                    font: .system(size: 21, weight: .bold, design: .rounded),
                    width: media.upNext == nil ? 300 : 200
                )
                .foregroundStyle(NotchTheme.inkPrimary)

                artistRow

                subtitleLine
            }

            Spacer(minLength: 8)

            upNextCard
        }
        .frame(height: 78)
    }

    /// The line under the artist: the follower count when Spotify is
    /// connected, the album otherwise, or quick support for Apple Music & Spotify.
    @ViewBuilder
    private var subtitleLine: some View {
        if media.track == nil && activeAudioApp == nil {
            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(URL(string: "music://")!)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 10))
                        Text("Apple Music")
                            .font(.notchCaption.weight(.semibold))
                    }
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableButtonStyle())

                Button {
                    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                        NSWorkspace.shared.openApplication(at: app, configuration: .init())
                    } else if let url = URL(string: "spotify:") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                        Text("Spotify")
                            .font(.notchCaption.weight(.semibold))
                    }
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableButtonStyle())
            }
        } else if let followers = media.followersLabel {
            Text(followers)
                .font(.notchCaption.weight(.semibold))
                .foregroundStyle(NotchTheme.inkMuted)
                .lineLimit(1)
        } else if let album = media.track?.album, !album.isEmpty {
            Text(album)
                .font(.notchCaption)
                .foregroundStyle(NotchTheme.inkSecondary)
                .lineLimit(1)
        } else if let active = activeAudioApp {
            Button {
                active.activate()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 9))
                    Text("Bring \(active.name) to Front")
                        .font(.notchCaption.weight(.semibold))
                }
                .foregroundStyle(NotchTheme.inkSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(PressableButtonStyle())
        }
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
                            .fill(Color.white.opacity(0.08))
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    Text("UP NEXT")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(NotchTheme.inkMuted)
                    Text(next.title)
                        .font(.notchCaption.weight(.bold))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                    Text(next.artist)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .lineLimit(1)
                }
                .frame(width: 96, alignment: .leading)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Up next: \(next.title) by \(next.artist)")
        }
    }

    // MARK: - Artwork & metadata

    private var artwork: some View {
        Group {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let icon = media.sourceAppIcon ?? activeAudioApp?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(14)
                    .background(Color.white.opacity(0.08))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 78, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .shadow(color: media.accent.opacity(0.38), radius: 14, y: 5)
    }

    private var artistRow: some View {
        HStack(spacing: 6) {
            // Monogram avatar stands in for the reference's artist photo.
            Text(String(displayArtist.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(NotchTheme.surfaceHover))

            Text(displayArtist)
                .font(.notchCallout.weight(.bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)

            if isAudioActive && !isBrowserVideo {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }

            Spacer(minLength: 0)
        }
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

    /// The reference's centered lyric line — the live synced line, tinted with
    /// the artwork accent, replaced in place as the song moves.
    private var lyricLine: some View {
        Group {
            if let current = media.lyrics.currentLine?.text, !current.isEmpty {
                Text(current)
                    .font(.notchBody.weight(.bold))
                    .foregroundStyle(media.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.opacity)
                    .id(media.lyrics.currentIndex ?? -1)
                    .transition(.opacity)
            } else if media.lyrics.isLoading {
                Text("Finding lyrics…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkMuted)
            } else if !media.lyrics.lines.isEmpty {
                // Unsynced lyrics: show the opening line rather than nothing.
                Text(media.lyrics.lines[0].text)
                    .font(.notchCallout.weight(.semibold))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
            } else {
                Text(media.hasTrack ? "♪" : " ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NotchTheme.inkMuted.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .animation(.notchSpring, value: media.lyrics.currentIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lyrics")
        .accessibilityValue(media.lyrics.currentLine?.text ?? "")
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
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                    media.togglePlayPause()
                }
            } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .hoverLift(1.08)
            .disabled(!media.canControlTransport)
            .opacity(media.canControlTransport ? 1 : 0.4)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(media.isPlaying ? "Pause" : "Play")

            transportIcon(
                "forward.fill",
                size: 16,
                label: "Next track",
                isEnabled: media.canControlTransport
            ) {
                media.nextTrack()
            }

        }
        .frame(maxWidth: .infinity)
    }

    /// Both of these reach the player. The heart is Music's `loved` flag, or
    /// Spotify's Liked Songs when an account is connected — it is disabled
    /// rather than decorative when neither is available, because a control
    /// that only changes its own colour is worse than one that is greyed out.
    private var bottomActions: some View {
        HStack(spacing: 24) {
            transportIcon(
                media.isFavorite ? "heart.fill" : "heart",
                size: 14,
                label: media.isFavorite ? "Remove from favourites" : "Add to favourites",
                tint: media.isFavorite ? .red : nil,
                isEnabled: media.canFavorite
            ) {
                withAnimation(NotchAnimations.content) {
                    media.toggleFavorite()
                }
                state.showToast(
                    media.isFavorite ? "Removed from favourites" : "Added to favourites",
                    symbol: media.isFavorite ? "heart.slash" : "heart.fill"
                )
            }

            transportIcon(
                media.isShuffling ? "shuffle.circle.fill" : "shuffle",
                size: 14,
                label: media.isShuffling ? "Turn off shuffle" : "Shuffle",
                tint: media.isShuffling ? .blue : nil,
                isEnabled: media.canControlTransport
            ) {
                withAnimation(NotchAnimations.content) {
                    media.toggleShuffle()
                }
                state.showToast(
                    media.isShuffling ? "Shuffle off" : "Shuffle on",
                    symbol: "shuffle"
                )
            }
        }
        .frame(maxWidth: .infinity)
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
