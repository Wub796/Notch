import AppKit
import SwiftUI

/// Which screen of the Devices surface is showing.
///
/// Outside the view for the same reason `AudioScreenTab` is: `NotchState`
/// holds the selection, and it must not depend on a view type compiling.
enum DevicesSection: String, CaseIterable, Identifiable {
    case now, library, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "Now"
        case .library: "Library"
        case .audio: "Audio"
        }
    }

    var symbol: String {
        switch self {
        case .now: "music.note.list"
        case .library: "books.vertical.fill"
        case .audio: "hifispeaker.fill"
        }
    }
}

/// The Now page's fixed column heights, shared with NotchState so the slab can
/// size itself to the page without a runtime measurement — the same arrangement
/// HomeDashboardMetrics uses for the dashboard. Keep these in step with the
/// layout below.
///
/// Only Now swaps in its own budget: it is a short fixed column, while Library
/// and Audio are content-filled surfaces that legitimately want the full Audio
/// slab height. Sizing the whole tab to Now would starve those two, so the fit
/// is scoped to this one section.
enum DevicesScreenMetrics {
    /// The hero row (artwork, track info, account chip + section switch).
    static let heroRowHeight: CGFloat = 82
    /// Vertical gap between the top-level stacked rows.
    static let sectionSpacing: CGFloat = 8
    /// The centered synced-lyric line shown when lyrics are toggled on.
    static let centeredLyricsHeight: CGFloat = 46
    /// progress + transport + heart/shuffle rows, their spacing and top inset.
    static let playbackControlsHeight: CGFloat = 108
    /// Extra inset kept beneath the heart/shuffle row so the icons clear the
    /// slab's rounded bottom edge instead of sitting flush against it. The
    /// slab's structural `openContentInset` adds a little more on top of this.
    static let bottomSafePadding: CGFloat = 20

    static func naturalNowHeight(showsLyrics: Bool) -> CGFloat {
        let base = heroRowHeight + sectionSpacing + playbackControlsHeight
        return showsLyrics
            ? base + sectionSpacing + centeredLyricsHeight
            : base
    }
}

/// The Devices screen: a title row, the account chip, the section switch, and
/// whichever of the four screens is selected.
///
/// Every screen here is live account data. Library and Discover come from the
/// Spotify Web API and are empty until Spotify is connected — there is no demo
/// content behind them. Audio's own four tabs mix the two worlds deliberately:
/// Spotify Connect devices are the account's, while AirPlay, Apps and System
/// are this Mac's, read from CoreAudio.
struct DevicesScreenView: View {
    let state: NotchState
    let namespace: Namespace.ID

    private var spotify: SpotifyLibrary { state.spotify }
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
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(NotchAnimations.content, value: state.devicesSection)

            if state.devicesSection == .now && state.mediaShowsFullLyrics && !media.isBrowserVideo {
                centeredLyrics
                    .transition(.opacity)
            } else if state.devicesSection == .library {
                thinBottomBuffer
            }

            Group {
                switch state.devicesSection {
                case .now:
                    nowPlaybackSection
                case .library:
                    SpotifyLibraryScreen(state: state)
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
        .onAppear {
            spotify.refresh()
            state.appleMusic.refresh()
        }
        .onChange(of: spotify.isConnected) { _, connected in
            if connected { spotify.refresh(force: true) }
        }
    }

    // MARK: - Top Hero Row (Artwork + Title + Artist aligned with Section buttons & 3D lyrics)

    private var topHeroRow: some View {
        HStack(alignment: .top, spacing: 14) {
            // LEFT: Album Art + Track Info + Subtitle
            HStack(alignment: .center, spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
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

            // RIGHT: account and section controls only. Lyrics belong solely
            // to Now and are centered below the hero.
            HStack(spacing: 8) {
                accountChip
                sectionSwitch
            }
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

    private var thinBottomBuffer: some View {
        Capsule()
            .fill(Color.white.opacity(0.09))
            .frame(width: 58, height: 3)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    // MARK: - Now Playback Controls (Lifted Higher)

    private var nowPlaybackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            progressRow

            transportRow

            bottomActions
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Media Artwork & Info Subcomponents

    private var artwork: some View {
        Group {
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
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .matchedGeometryEffect(id: "albumArt", in: namespace)
        .shadow(color: media.accent.opacity(0.38), radius: 14, y: 5)
    }

    private var artistRow: some View {
        HStack(spacing: 6) {
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
                    isEnabled: media.canControlTransport
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

    @ViewBuilder
    private var accountChip: some View {
        if spotify.isConnected {
            HStack(spacing: 0) {
                Text(spotify.profile?.displayName ?? "Spotify")
                    .font(.notchBody.weight(.bold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
                    // The pill row beside this is eight items wide; a long
                    // display name must give way to it, not squeeze it.
                    .frame(maxWidth: 130, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)

                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 1, height: 18)

                Button {
                    SpotifyAuth.shared.signOut()
                    spotify.clear()
                    state.showToast("Logged out of Spotify", symbol: "power")
                } label: {
                    Text("Log out")
                        .font(.notchCallout.weight(.semibold))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .frame(height: 34)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
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
            HStack(spacing: 5) {
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

// MARK: - Library

/// The account's playlists as cards, in the sort the user picked. The one
/// that is playing is tinted and offers to stop rather than start.
struct SpotifyLibraryScreen: View {
    let state: NotchState

    private var spotify: SpotifyLibrary { state.spotify }
    private var appleMusic: AppleMusicLibrary { state.appleMusic }
    @State private var filterProvider: MusicProvider? = nil

    private static let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var hasAnyPlaylists: Bool {
        !spotify.playlists.isEmpty || !spotify.savedTracks.isEmpty || !appleMusic.playlists.isEmpty
    }

    private var isLoading: Bool {
        spotify.isLoadingLibrary || appleMusic.isLoading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Group {
                if !hasAnyPlaylists {
                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.regular)
                            Text("Loading your playlists & library…")
                                .font(.notchBody)
                                .foregroundStyle(NotchTheme.inkMuted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 32))
                                .foregroundStyle(NotchTheme.inkMuted)
                            Text("No playlists loaded yet.")
                                .font(.notchHeadline)
                                .foregroundStyle(NotchTheme.inkPrimary)
                            Text("Open Apple Music or connect Spotify to load and access your playlists.")
                                .font(.notchBody)
                                .foregroundStyle(NotchTheme.inkSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 340)

                            VStack(spacing: 8) {
                                HStack(spacing: 10) {
                                    if !appleMusic.isMusicRunning {
                                        Button("Open Apple Music") {
                                            appleMusic.openMusicApp()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    } else if !appleMusic.isAuthorized {
                                        Button("Grant Music Permission") {
                                            IntegrationPermissions.shared.grantMusicAccess(for: .appleMusic)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }

                                    if !spotify.isConnected {
                                        Button("Connect Spotify") {
                                            SettingsWindowController.shared.show()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    Button("Refresh Library") {
                                        spotify.refresh(force: true)
                                        appleMusic.refresh(force: true)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: Self.columns, spacing: NotchTheme.Space.m) {
                            // 1. Apple Music Playlists
                            if filterProvider == nil || filterProvider == .appleMusic {
                                ForEach(sortedAppleMusicPlaylists) { playlist in
                                    AppleMusicPlaylistCard(
                                        playlist: playlist,
                                        isPlaying: state.media.isPlaying && (state.media.sourceAppBundleID == MusicProvider.appleMusic.bundleID || NotchSettings.shared.musicProvider == .appleMusic),
                                        action: {
                                            appleMusic.play(playlistName: playlist.name)
                                        }
                                    )
                                }
                            }

                            // 2. Spotify Playlists & Saved Tracks
                            if filterProvider == nil || filterProvider == .spotify {
                                ForEach(spotify.savedTracks) { track in
                                    SavedTrackCard(
                                        track: track,
                                        artwork: spotify.image(for: track.artworkURL),
                                        action: { spotify.play(uri: track.uri) }
                                    )
                                }
                                ForEach(spotify.sortedPlaylists) { playlist in
                                    PlaylistCard(
                                        playlist: playlist,
                                        artwork: spotify.image(for: playlist.artworkURL),
                                        isPlaying: isPlaying(playlist),
                                        action: { spotify.play(uri: playlist.uri) }
                                    )
                                }
                            }
                        }
                        .padding(.bottom, 10)
                        .animation(.notchSpring, value: spotify.sortedPlaylists)
                    }
                    .notchScrollFade(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            spotify.refresh()
            appleMusic.refresh()
        }
    }

    private var sortedAppleMusicPlaylists: [AppleMusicPlaylist] {
        switch spotify.sort {
        case .name:
            return appleMusic.playlists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .owner, .recents:
            return appleMusic.playlists
        }
    }

    /// The playing playlist, by the context the account reports — falling back
    /// to what this app itself last started.
    private func isPlaying(_ playlist: SpotifyClient.Playlist) -> Bool {
        guard spotify.isPlayingRemotely || state.media.isPlaying else { return false }
        return spotify.activeContextURI == playlist.uri
    }

    private var header: some View {
        ScreenHeader("Library", subtitle: "Playlists sorted by \(spotify.sort.title)") {
            HStack(spacing: 8) {
                if !appleMusic.playlists.isEmpty && (!spotify.playlists.isEmpty || !spotify.savedTracks.isEmpty) {
                    Picker("", selection: $filterProvider) {
                        Text("All").tag(MusicProvider?.none)
                        Text("Apple Music").tag(MusicProvider?.some(.appleMusic))
                        Text("Spotify").tag(MusicProvider?.some(.spotify))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                Menu {
                    ForEach(SpotifyLibrary.LibrarySort.allCases) { option in
                        Button {
                            withAnimation(NotchAnimations.content) { spotify.sort = option }
                        } label: {
                            if spotify.sort == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text(spotify.sort.title)
                            .font(.notchBody.weight(.bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(NotchTheme.inkPrimary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Sort playlists")
            }
        }
    }
}

/// One playlist: cover, name, owner, and the button that starts it.
struct PlaylistCard: View {
    let playlist: SpotifyClient.Playlist
    let artwork: NSImage?
    let isPlaying: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name)
                    .font(.notchHeadline)
                    .foregroundStyle(isPlaying ? Color.green : NotchTheme.inkPrimary)
                    .lineLimit(1)
                Text(playlist.owner.isEmpty ? "\(playlist.trackCount) tracks" : playlist.owner)
                    .font(.notchCallout)
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(isPlaying ? Color.green.opacity(0.16) : Color.accentColor)
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.green)
                            .symbolEffect(.pulse, options: .repeating)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 38, height: 38)
                .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(isPlaying ? "Now playing" : "Play \(playlist.name)")
        }
        .padding(10)
        .notchCard(isHighlighted: isPlaying, tint: .green)
        .background {
            if isHovering, !isPlaying {
                RoundedRectangle(cornerRadius: NotchTheme.Radius.card, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .onHover { isHovering = $0 }
        .animation(NotchAnimations.content, value: isHovering)
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous))
    }
}

struct SavedTrackCard: View {
    let track: SpotifyClient.SavedTrack
    let artwork: NSImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay { Image(systemName: "music.note") }
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.notchCallout.weight(.bold)).lineLimit(1)
                    Text(track.artist).font(.notchCaption).foregroundStyle(NotchTheme.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill").foregroundStyle(.green)
            }
            .padding(10)
            .notchCard()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Play \(track.title) by \(track.artist)")
    }
}

/// Apple Music playlist card with gradient art, track count, and 1-click play button.
struct AppleMusicPlaylistCard: View {
    let playlist: AppleMusicPlaylist
    let isPlaying: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 250/255, green: 45/255, blue: 72/255),
                            Color(red: 254/255, green: 74/255, blue: 104/255),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: playlist.isSmart ? "sparkles" : "music.note.list")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.notchHeadline)
                    .foregroundStyle(isPlaying ? Color.pink : NotchTheme.inkPrimary)
                    .lineLimit(1)
                Text("\(playlist.trackCount) tracks • Apple Music")
                    .font(.notchCallout)
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(isPlaying ? Color.pink.opacity(0.18) : Color.pink)
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.pink)
                            .symbolEffect(.pulse, options: .repeating)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 38, height: 38)
                .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(isPlaying ? "Now playing" : "Play \(playlist.name)")
        }
        .padding(10)
        .notchCard(isHighlighted: isPlaying, tint: .pink)
        .background {
            if isHovering, !isPlaying {
                RoundedRectangle(cornerRadius: NotchTheme.Radius.card, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .onHover { isHovering = $0 }
        .animation(NotchAnimations.content, value: isHovering)
        .accessibilityElement(children: .combine)
    }
}
