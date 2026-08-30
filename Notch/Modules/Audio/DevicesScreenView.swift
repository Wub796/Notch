import AppKit
import SwiftUI

/// Which screen of the Devices surface is showing.
///
/// Outside the view for the same reason `AudioScreenTab` is: `NotchState`
/// holds the selection, and it must not depend on a view type compiling.
enum DevicesSection: String, CaseIterable, Identifiable {
    case now, library, discover, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "Now"
        case .library: "Library"
        case .discover: "Discover"
        case .audio: "Audio"
        }
    }

    var symbol: String {
        switch self {
        case .now: "music.note.list"
        case .library: "books.vertical.fill"
        case .discover: "magnifyingglass"
        case .audio: "hifispeaker.fill"
        }
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
            topHeroRow

            Group {
                switch state.devicesSection {
                case .now:
                    nowPlaybackSection
                case .library:
                    SpotifyLibraryScreen(state: state)
                case .discover:
                    SpotifyDiscoverScreen(state: state)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { spotify.refresh() }
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

                        liveAudioBadge
                    }

                    artistRow

                    subtitleButtons
                }
            }

            Spacer(minLength: 8)

            // RIGHT: Section buttons & 3D lyrics directly underneath Library & Discover
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 8) {
                    accountChip
                    sectionSwitch
                }

                ThreeDLyricsView(
                    lyrics: media.lyrics,
                    accent: media.accent,
                    onSelect: { time in
                        media.seek(to: time + 0.05)
                    }
                )
                .frame(maxWidth: 290, alignment: .trailing)
            }
        }
        .frame(height: 78)
    }

    // MARK: - Now Playback Controls (Lifted Higher)

    private var nowPlaybackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            progressRow

            if state.mediaShowsFullLyrics {
                LyricsView(lyrics: media.lyrics, accent: media.accent) { time in
                    media.seek(to: time + 0.05)
                }
                .frame(height: 85)
                .transition(.opacity)
            }

            transportRow

            bottomActions
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Media Artwork & Info Subcomponents

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
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

            transportIcon(state.audio.currentSymbol, size: 15, label: "Switch audio output") {
                // cycleToNextDevice is a no-op with fewer than two devices
                // (and the system can refuse the switch), so confirm only when
                // the output actually changed.
                let before = state.audio.currentDeviceID
                state.audio.cycleToNextDevice()
                guard state.audio.currentDeviceID != before else { return }
                let name = state.audio.devices
                    .first { $0.id == state.audio.currentDeviceID }?.name
                state.showToast("Output: \(name ?? "Default")", symbol: state.audio.currentSymbol)
            }
        }
        .frame(maxWidth: .infinity)
    }

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

    /// A live readout of what CoreAudio says is playing.
    @ViewBuilder
    private var liveAudioBadge: some View {
        let playing = state.audioApps.apps.filter(\.isPlaying)

        if state.audioApps.isAnyAudioPlaying || !playing.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative, options: .repeating)

                Text(Self.playingLabel(playing))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Color.green.opacity(0.14)))
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .accessibilityLabel("Audio playing")
            .accessibilityValue(Self.playingLabel(playing))
        }
    }

    private static func playingLabel(_ playing: [AudioAppMonitor.App]) -> String {
        switch playing.count {
        case 0: "Audio playing"
        case 1: playing[0].name
        default: "\(playing[0].name) +\(playing.count - 1)"
        }
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

    /// One capsule holding the four sections, and — when Audio is up — the
    /// four output tabs after a divider, exactly as the reference nests them.
    private var sectionSwitch: some View {
        HStack(spacing: 4) {
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

            if state.devicesSection == .audio {
                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 4)
                    .transition(.opacity)

                ForEach(AudioScreenTab.allCases) { tab in
                    pill(
                        title: tab.title,
                        symbol: tab.symbol,
                        isActive: state.audioTab == tab,
                        geometryID: "audioPill"
                    ) {
                        withAnimation(NotchAnimations.content) { state.audioTab = tab }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .fixedSize()
    }

    /// The selected capsule is one view that moves between the pills rather
    /// than a fill switching off here and on there — the difference between a
    /// switch that slides and one that blinks.
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

    private static let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !spotify.isConnected {
                SpotifyConnectPrompt(
                    message: "Connect Spotify to browse your playlists here."
                )
            } else if spotify.playlists.isEmpty {
                Text(spotify.isLoadingLibrary ? "Loading your library…" : "No playlists yet.")
                    .font(.notchBody)
                    .foregroundStyle(NotchTheme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Self.columns, spacing: NotchTheme.Space.m) {
                        ForEach(spotify.sortedPlaylists) { playlist in
                            PlaylistCard(
                                playlist: playlist,
                                artwork: spotify.image(for: playlist.artworkURL),
                                isPlaying: isPlaying(playlist),
                                action: { spotify.play(uri: playlist.uri) }
                            )
                        }
                    }
                    .padding(.bottom, 4)
                    .animation(.notchSpring, value: spotify.sortedPlaylists)
                }
                .notchScrollFade(12)
            }
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

// MARK: - Discover

/// Search across Spotify, over a shelf of what the account actually played
/// recently mixed with its own playlists.
struct SpotifyDiscoverScreen: View {
    let state: NotchState

    @FocusState private var searchFocused: Bool

    private var spotify: SpotifyLibrary { state.spotify }

    private static let resultColumns = [
        GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField

            if !spotify.isConnected {
                SpotifyConnectPrompt(
                    message: "Connect Spotify to search and see what you've been playing."
                )
            } else if spotify.query.trimmingCharacters(in: .whitespaces).count >= 2 {
                results
            } else {
                shelf
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchTheme.inkMuted)

            TextField("Search songs, artists, albums…", text: Binding(
                get: { spotify.query },
                set: { spotify.query = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.notchBody.weight(.medium))
            .foregroundStyle(NotchTheme.inkPrimary)
            .focused($searchFocused)
            .disabled(!spotify.isConnected)

            if !spotify.query.isEmpty {
                Button {
                    spotify.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(NotchTheme.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Capsule().fill(Color.white.opacity(searchFocused ? 0.12 : 0.06)))
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.greeting())
                .font(.notchDisplay)
                .foregroundStyle(NotchTheme.inkPrimary)

            VStack(alignment: .leading, spacing: 10) {
                Text("For You")
                    .font(.notchHeadline)
                    .foregroundStyle(NotchTheme.inkPrimary)

                if spotify.forYou.isEmpty {
                    Text(spotify.isLoadingLibrary
                         ? "Loading…"
                         : "Play something and it will show up here.")
                        .font(.notchCallout)
                        .foregroundStyle(NotchTheme.inkMuted)
                        .frame(height: 60)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: NotchTheme.Space.l) {
                            ForEach(spotify.forYou) { item in
                                DiscoverTile(
                                    item: item,
                                    artwork: spotify.image(for: item.artworkURL),
                                    action: { spotify.play(uri: item.uri) }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .notchScrollFadeHorizontal(10)
                }
            }
            .padding(NotchTheme.Space.l)
            .notchCard()
        }
    }

    @ViewBuilder
    private var results: some View {
        if spotify.searchResults.isEmpty {
            Text(spotify.isSearching ? "Searching…" : "Nothing found.")
                .font(.notchBody)
                .foregroundStyle(NotchTheme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Self.resultColumns, alignment: .leading, spacing: 14) {
                    ForEach(spotify.searchResults) { item in
                        DiscoverTile(
                            item: item,
                            artwork: spotify.image(for: item.artworkURL),
                            action: { spotify.play(uri: item.uri) }
                        )
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    /// The reference greets by time of day; so does this.
    static func greeting(at date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 0 ..< 5: "Good night"
        case 5 ..< 12: "Good morning"
        case 12 ..< 18: "Good afternoon"
        default: "Good evening"
        }
    }
}

/// One card on a Discover shelf or in a search result grid.
struct DiscoverTile: View {
    let item: SpotifyClient.Item
    let artwork: NSImage?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    if let artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                            .fill(NotchTheme.surfaceHover)
                        Image(systemName: item.kind == .artist ? "person.fill" : "music.note")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }

                    if isHovering {
                        Circle()
                            .fill(.black.opacity(0.55))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .transition(.opacity)
                    }
                }
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous))

                Text(item.title)
                    .font(.notchBody.weight(.bold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
            }
            .frame(width: 108, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .animation(NotchAnimations.content, value: isHovering)
        .accessibilityLabel("Play \(item.title) by \(item.subtitle)")
    }
}

// MARK: - Spotify Connect device card

/// A Connect device: its name and whether it is the active one, over the wide
/// volume bar the reference puts under it. The bar is draggable and the value
/// is the device's own, not this Mac's output level.
struct SpotifyDeviceCard: View {
    let device: SpotifyClient.Device
    let onSelect: () -> Void
    let onVolume: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(device.isActive ? Color.green : NotchTheme.inkSecondary)
                    .frame(width: 30)

                Text(device.name)
                    .font(.notchHeadline)
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if device.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .accessibilityLabel("Active device")
                } else {
                    Button(action: onSelect) {
                        Text("Switch")
                            .font(.notchCallout.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .background(Capsule().fill(Color.accentColor))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Move playback to \(device.name)")
                }
            }

            if device.supportsVolume {
                SpotifyVolumeBar(
                    percent: device.volumePercent ?? 0,
                    onChange: onVolume
                )
            } else {
                Text("This device doesn't accept volume changes from Spotify.")
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkMuted)
            }
        }
        .padding(NotchTheme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard(isHighlighted: device.isActive, tint: .green)
    }
}

/// The wide blue volume bar: the label and the reading sit inside the fill,
/// and dragging anywhere along it sets the level.
struct SpotifyVolumeBar: View {
    let percent: Int
    let onChange: (Double) -> Void

    @State private var dragFraction: Double?

    private var fraction: Double {
        dragFraction ?? min(max(Double(percent) / 100, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NotchTheme.surfaceHover)

                Capsule()
                    .fill(Color.accentColor)
                    // A minimum so the label never sits on a bare track at 0.
                    .frame(width: max(width * fraction, 120))

                HStack(spacing: 8) {
                    Text("Volume")
                        .font(.notchHeadline)
                    Spacer(minLength: 8)
                    Text("\(Int((fraction * 100).rounded())) %")
                        .font(.notchHeadline.monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
            }
            .frame(height: 52)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        dragFraction = min(max(value.location.x / width, 0), 1)
                        onChange(dragFraction ?? 0)
                    }
                    .onEnded { _ in
                        if let dragFraction { onChange(dragFraction) }
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 52)
        .animation(.easeOut(duration: 0.15), value: percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Device volume")
        .accessibilityValue("\(percent) percent")
    }
}

/// Shown wherever a screen needs the account and there isn't one.
struct SpotifyConnectPrompt: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.green)

            Text(message)
                .font(.notchBody)
                .foregroundStyle(NotchTheme.inkPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Connect your Spotify account in Settings to sync playlists, recent listening, and Spotify Connect.")
                .font(.notchFootnote)
                .foregroundStyle(NotchTheme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                SettingsWindowController.shared.show()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                    Text("Open Media Settings")
                        .font(.notchCaption.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(Capsule().fill(Color.green.opacity(0.85)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.vertical, 20)
        .padding(.horizontal, NotchTheme.Space.l)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NotchTheme.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
