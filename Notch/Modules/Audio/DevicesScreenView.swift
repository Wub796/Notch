import AppKit
import SwiftUI

/// Which screen of the Devices surface is showing.
///
/// Outside the view for the same reason `AudioScreenTab` is: `NotchState`
/// holds the selection, and it must not depend on a view type compiling.
enum DevicesSection: String, CaseIterable, Identifiable {
    case now, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "Now"
        case .audio: "Audio"
        }
    }

    var symbol: String {
        switch self {
        case .now: "music.note.list"
        case .audio: "hifispeaker.fill"
        }
    }
}

/// The Now page's fixed column heights, shared with NotchState so the slab can
/// size itself to the page without a runtime measurement — the same arrangement
/// HomeDashboardMetrics uses for the dashboard. Keep these in step with the
/// layout below.
///
/// Only Now swaps in its own budget: it is a short fixed column, while Audio is
/// a content-filled surface that legitimately wants the full Audio slab height.
/// Sizing the whole tab to Now would starve it, so the fit is scoped to this
/// one section.
enum DevicesScreenMetrics {
    /// The hero row (artwork, track info, account chip + section switch),
    /// including the surface padding it now carries.
    static let heroRowHeight: CGFloat = 82 + NotchTheme.Space.s * 2
    /// Vertical gap between the top-level stacked rows.
    static let sectionSpacing: CGFloat = 8
    /// The centered synced-lyric line shown when lyrics are toggled on.
    static let centeredLyricsHeight: CGFloat = 46
    /// progress + transport + heart/shuffle rows, their spacing, and the
    /// surface padding around them. The 108 included a 4pt top inset that the
    /// surface's own padding replaced.
    static let playbackControlsHeight: CGFloat = 104 + NotchTheme.Space.s * 2
    /// Extra inset beneath the controls so they clear the slab's rounded
    /// bottom edge instead of sitting flush against it.
    ///
    /// Small now: the controls sit in a surface with its own bottom padding,
    /// which provides that clearance. Keeping the old 20 on top of it left a
    /// visible band of empty slab below the card's bottom edge — invisible
    /// when the controls were bare on black, obvious once they had an edge.
    static let bottomSafePadding: CGFloat = 6

    static func naturalNowHeight(showsLyrics: Bool) -> CGFloat {
        let base = heroRowHeight + sectionSpacing + playbackControlsHeight
        return showsLyrics
            ? base + sectionSpacing + centeredLyricsHeight
            : base
    }
}

/// The Devices screen: a title row, the account chip, the section switch, and
/// whichever section is selected.
///
/// Every screen here is live: Now tracks whatever is playing, and Audio's tabs
/// are all this Mac's own outputs, read from CoreAudio.
struct DevicesScreenView: View {
    let state: NotchState
    let namespace: Namespace.ID

    private var media: MediaController { state.media }

    private var activeAudioApp: AudioAppMonitor.App? {
        state.audioApps.apps.first(where: \.isPlaying)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if state.devicesSection == .audio {
                    sectionSwitch
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                } else {
                    topHeroRow
                        .padding(.horizontal, NotchTheme.Space.m)
                        .padding(.vertical, NotchTheme.Space.s)
                        .notchTile(radius: NotchTheme.Radius.card)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(NotchAnimations.content, value: state.devicesSection)

            if state.devicesSection == .now && state.mediaShowsFullLyrics && !media.isBrowserVideo {
                centeredLyrics
                    .transition(.opacity)
            }

            Group {
                switch state.devicesSection {
                case .now:
                    nowPlaybackSection
                case .audio:
                    AudioDevicesView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity
                )
            )
            .id(state.devicesSection)
            .animation(NotchAnimations.content, value: state.devicesSection)
            .animation(NotchAnimations.content, value: state.mediaShowsFullLyrics)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Top Hero Row (Artwork + Title + Artist aligned with Section buttons & 3D lyrics)

    private var topHeroRow: some View {
        HStack(alignment: .top, spacing: 12) {
            // LEFT: Album Art + Track Info + Subtitle
            HStack(alignment: .center, spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        MarqueeText(
                            text: displayTitle,
                            font: .system(size: 19, weight: .bold, design: .rounded),
                            width: 190
                        )
                        .foregroundStyle(NotchTheme.inkPrimary)


                    }

                    artistRow

                    subtitleButtons
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 8)

            // RIGHT: the section switch. Lyrics belong solely to Now and are
            // centered below the hero.
            sectionSwitch
        }
        .frame(minHeight: 78, maxHeight: 78)
    }

    private var centeredLyrics: some View {
        ThreeDLyricsView(
            lyrics: media.lyrics,
            accent: media.accent,
            onSelect: { time in
                media.seek(to: time + 0.05)
            }
        )
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .clipped()
        .transition(.opacity)
    }

    // MARK: - Now Playback Controls (Lifted Higher)

    private var nowPlaybackSection: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.s) {
            progressRow

            transportRow

            bottomActions
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, NotchTheme.Space.m)
        .padding(.vertical, NotchTheme.Space.s)
        // The scrubber, transport and the heart/shuffle row are one
        // instrument; on bare black they read as three unrelated rows adrift
        // in a wide panel.
        .notchTile(radius: NotchTheme.Radius.card)
    }

    // MARK: - Media Artwork & Info Subcomponents

    private var artwork: some View {
        Group {
            // Keyed on `artworkVersion` so a track change crossfades the
            // cover instead of hard-cutting it; the stable outer container
            // keeps the open/close `matchedGeometryEffect` morph intact.
            artworkContent
                .id(media.artworkVersion)
                .transition(.opacity)
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(NotchTheme.Surface.borderStrong, lineWidth: 1)
        }
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .shadow(color: media.accent.opacity(0.38), radius: 14, y: 5)
        .animation(NotchAnimations.content, value: media.artworkVersion)
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let image = media.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let icon = media.sourceAppIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(14)
                .background(Color.white.opacity(0.08))
        } else if let active = activeAudioApp, let icon = active.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(14)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(NotchTheme.inkMuted)
                }
        }
    }

    private var artistRow: some View {
        HStack(spacing: 8) {
            Text(String(displayArtist.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(NotchTheme.surfaceHover))

            Text(displayArtist)
                .font(.notchCallout.weight(.bold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var subtitleButtons: some View {
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

    private var progressRow: some View {
        ScrubberBar(
            duration: media.track?.duration ?? 0,
            elapsed: media.displayedElapsed,
            accent: media.accent
        ) { target in
            media.seek(to: target)
        }
    }

    private var transportRow: some View {
        HStack(spacing: 28) {
            transportIcon(
                "backward.fill",
                size: 16,
                label: "Previous track",
                isEnabled: true
            ) {
                media.previousTrack()
            }

            Button {
                // The icon crossfades via contentTransition below; the press
                // feedback comes from PressableButtonStyle. No spring wrapper:
                // bounce on a frequent transport control reads as jitter.
                media.togglePlayPause()
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
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(media.isPlaying ? "Pause" : "Play")

            transportIcon(
                "forward.fill",
                size: 16,
                label: "Next track",
                isEnabled: true
            ) {
                media.nextTrack()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var bottomActions: some View {
        if !media.isBrowserVideo && media.hasTrack {
            HStack(spacing: 28) {
                transportIcon(
                    media.isShuffling ? "shuffle.circle.fill" : "shuffle",
                    size: 15,
                    label: media.isShuffling ? "Turn off shuffle" : "Shuffle",
                    tint: media.isShuffling ? .blue : nil,
                    isEnabled: true
                ) {
                    withAnimation(NotchAnimations.content) {
                        media.toggleShuffle()
                    }
                }

                transportIcon(
                    media.isFavorite ? "heart.fill" : "heart",
                    size: 15,
                    label: media.isFavorite ? "Remove from favourites" : "Add to favourites",
                    tint: media.isFavorite ? .red : nil,
                    isEnabled: media.canFavorite
                ) {
                    withAnimation(NotchAnimations.content) {
                        media.toggleFavorite()
                    }
                }

                transportIcon(
                    state.mediaShowsFullLyrics
                        ? "list.bullet.rectangle.fill"
                        : "list.bullet.rectangle",
                    size: 15,
                    label: state.mediaShowsFullLyrics ? "Hide lyrics" : "Show lyrics",
                    tint: state.mediaShowsFullLyrics ? nil : NotchTheme.inkMuted
                ) {
                    withAnimation(NotchAnimations.content) {
                        state.mediaShowsFullLyrics.toggle()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
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

    private var sectionSwitch: some View {
        HStack(spacing: 4) {
            // Discover is intentionally omitted; Audio remains available as
            // the destination of the media page's speaker button.
            ForEach(DevicesSection.allCases) { section in
                pill(
                    title: section.title,
                    symbol: section.symbol,
                    isActive: state.devicesSection == section,
                    geometryID: "sectionPill"
                ) {
                    withAnimation(NotchAnimations.content) {
                        state.devicesSection = section
                    }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .fixedSize()
        .id(state.devicesSection)
        .animation(NotchAnimations.content, value: state.devicesSection)
        .animation(NotchAnimations.content, value: state.mediaShowsFullLyrics)
    }

    private func pill(
        title: String,
        symbol: String,
        isActive: Bool,
        geometryID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.notchCallout.weight(.bold))
                    // The row carries eight of these when Audio is up; letting
                    // one wrap or truncate would break the whole capsule.
                    .fixedSize()
            }
            .foregroundStyle(isActive ? .white : NotchTheme.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                if isActive {
                    Capsule()
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: geometryID, in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
