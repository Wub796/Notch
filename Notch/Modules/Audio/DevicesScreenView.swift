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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow
            controlRow

            Group {
                switch state.devicesSection {
                case .now:
                    MediaPlayerView(state: state, namespace: namespace)
                case .library:
                    SpotifyLibraryScreen(state: state)
                case .discover:
                    SpotifyDiscoverScreen(state: state)
                case .audio:
                    AudioDevicesView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { spotify.refresh() }
        // Signing in happens in a browser, so the account arrives while this
        // screen is already up: load it the moment the token lands.
        .onChange(of: spotify.isConnected) { _, connected in
            if connected { spotify.refresh(force: true) }
        }
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(spacing: 12) {
            Button {
                state.select(.home)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(NotchTheme.surface))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Back to the dashboard")

            Text("Devices")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Account chip and section switch

    private var controlRow: some View {
        HStack(spacing: 10) {
            accountChip
            Spacer(minLength: 8)
            sectionSwitch
        }
    }

    @ViewBuilder
    private var accountChip: some View {
        if spotify.isConnected {
            HStack(spacing: 0) {
                Text(spotify.profile?.displayName ?? "Spotify")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
                } label: {
                    Text("Log out")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.inkSecondary)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .frame(height: 34)
            .background(Capsule().fill(NotchTheme.surface))
            .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        } else {
            Button {
                SpotifyAuth.shared.signIn()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .bold))
                    Text("Connect Spotify")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(Color.green.opacity(0.85)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
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
                    tint: .accentColor
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

                ForEach(AudioScreenTab.allCases) { tab in
                    pill(
                        title: tab.title,
                        symbol: tab.symbol,
                        isActive: state.audioTab == tab,
                        tint: .accentColor
                    ) {
                        withAnimation(NotchAnimations.content) { state.audioTab = tab }
                    }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(NotchTheme.surface))
        .overlay(Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 1))
        .fixedSize()
    }

    private func pill(
        title: String,
        symbol: String,
        isActive: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    // The row carries eight of these when Audio is up; letting
                    // one wrap or truncate would break the whole capsule.
                    .fixedSize()
            }
            .foregroundStyle(isActive ? .white : NotchTheme.inkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(isActive ? tint : .clear))
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
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Self.columns, spacing: 12) {
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
                }
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
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text("Playlists sorted by \(spotify.sort.title)")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }

            Spacer(minLength: 8)

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
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(isPlaying ? Color.green : NotchTheme.inkPrimary)
                    .lineLimit(1)
                Text(playlist.owner.isEmpty ? "\(playlist.trackCount) tracks" : playlist.owner)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
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
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isPlaying ? Color.green.opacity(0.10) : NotchTheme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isPlaying ? Color.green.opacity(0.35) : .white.opacity(isHovering ? 0.14 : 0.05),
                    lineWidth: 1
                )
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NotchTheme.surfaceHover)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(NotchTheme.inkMuted)
                    }
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .font(.system(size: 14, weight: .medium, design: .rounded))
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
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NotchTheme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    searchFocused ? Color.accentColor.opacity(0.6) : .white.opacity(0.07),
                    lineWidth: 1
                )
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.greeting())
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)

            VStack(alignment: .leading, spacing: 10) {
                Text("For You")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)

                if spotify.forYou.isEmpty {
                    Text(spotify.isLoadingLibrary
                         ? "Loading…"
                         : "Play something and it will show up here.")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.inkMuted)
                        .frame(height: 60)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
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
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(NotchTheme.surface)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if spotify.searchResults.isEmpty {
            Text(spotify.isSearching ? "Searching…" : "Nothing found.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(item.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
                    .font(.system(size: 16, weight: .bold, design: .rounded))
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
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
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
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NotchTheme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    device.isActive ? Color.green.opacity(0.28) : .white.opacity(0.06),
                    lineWidth: 1
                )
        }
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
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer(minLength: 8)
                    Text("\(Int((fraction * 100).rounded())) %")
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
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
        VStack(spacing: 10) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.green.opacity(0.8))

            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                SpotifyAuth.shared.signIn()
            } label: {
                Text("Connect Spotify")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.green.opacity(0.85)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NotchTheme.surface)
        }
    }
}
