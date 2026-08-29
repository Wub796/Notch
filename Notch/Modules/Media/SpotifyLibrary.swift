import AppKit
import Foundation
import Observation

/// The account side of Spotify: who is signed in, their playlists, their
/// Connect devices, and what to play next.
///
/// Kept apart from `MediaController`, which follows whatever is playing on
/// this Mac through MediaRemote or Apple Events and has no account at all.
/// This one only ever exists when the user has connected Spotify, and every
/// screen it feeds is empty until it does — nothing here has a placeholder
/// mode, because a fake device list is worse than an honest empty one.
@Observable
final class SpotifyLibrary {
    enum LibrarySort: String, CaseIterable, Identifiable {
        case recents, name, owner

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recents: "Recents"
            case .name: "Name"
            case .owner: "Owner"
            }
        }
    }

    private(set) var profile: SpotifyClient.Profile?
    private(set) var playlists: [SpotifyClient.Playlist] = []
    private(set) var devices: [SpotifyClient.Device] = []
    private(set) var forYou: [SpotifyClient.Item] = []
    private(set) var searchResults: [SpotifyClient.Item] = []

    private(set) var isLoadingLibrary = false
    private(set) var isLoadingDevices = false
    private(set) var isSearching = false
    private(set) var lastError: String?

    /// What the account is playing, wherever it is playing. The Library marks
    /// the playlist that is on from this rather than from local now-playing —
    /// the music may be coming out of a phone in another room.
    private(set) var activeContextURI: String?
    private(set) var isPlayingRemotely = false

    var sort: LibrarySort = .recents {
        didSet { NotchSettings.shared.spotifyLibrarySort = sort.rawValue }
    }

    /// The Discover query. Held here rather than in the view so switching
    /// tabs does not throw away what was typed.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    /// Downloaded covers, keyed by URL. `@Observable` sees the assignment, so
    /// a card redraws as soon as its image lands.
    ///
    /// Bounded: a long session that scrolls through search results would
    /// otherwise hold every cover it ever drew for the life of the app. The
    /// oldest are dropped once the cache is full — they cost one request to
    /// fetch again, and only if they are looked at again.
    private(set) var images: [String: NSImage] = [:]
    private var imageOrder: [String] = []
    private var imageTasks: Set<String> = []

    private static let imageCacheLimit = 120

    private var searchTask: Task<Void, Never>?
    private var lastLibraryLoad = Date.distantPast

    init() {
        if let stored = NotchSettings.shared.spotifyLibrarySort,
           let restored = LibrarySort(rawValue: stored) {
            sort = restored
        }
    }

    /// Playlists in the order the current sort asks for. Recents is the API's
    /// own order, which is what Spotify itself shows.
    var sortedPlaylists: [SpotifyClient.Playlist] {
        switch sort {
        case .recents:
            playlists
        case .name:
            playlists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .owner:
            playlists.sorted {
                $0.owner.localizedCaseInsensitiveCompare($1.owner) == .orderedAscending
            }
        }
    }

    var isConnected: Bool {
        SpotifyAuth.shared.state == .signedIn
    }

    // MARK: - Loading

    /// Everything the screen needs, in one pass. Cheap to call again: the
    /// library is only re-fetched if it is more than a minute stale, while
    /// devices and history — which change while you watch — always refresh.
    func refresh(force: Bool = false) {
        guard isConnected else {
            clear()
            return
        }

        Task { [weak self] in
            guard let token = await SpotifyAuth.shared.validAccessToken() else {
                await MainActor.run { [weak self] in
                    self?.lastError = "Spotify sign-in expired. Reconnect in Settings."
                }
                return
            }

            let staleLibrary = await MainActor.run { [weak self] () -> Bool in
                guard let self else { return false }
                return force || Date().timeIntervalSince(self.lastLibraryLoad) > 60
            }

            if staleLibrary {
                await MainActor.run { [weak self] in self?.isLoadingLibrary = true }

                async let profile = SpotifyClient.profile(token: token)
                async let playlists = SpotifyClient.playlists(token: token)
                async let history = SpotifyClient.recentlyPlayed(token: token)
                let loaded = await (profile, playlists, history)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.profile = loaded.0 ?? self.profile
                    if !loaded.1.isEmpty { self.playlists = loaded.1 }
                    self.forYou = Self.shelf(history: loaded.2, playlists: loaded.1)
                    self.isLoadingLibrary = false
                    self.lastLibraryLoad = Date()
                    self.lastError = nil
                }
            }

            await self?.loadDevices(token: token)
        }
    }

    /// Just the Connect devices. Polled while the Spotify audio tab is open,
    /// because a phone appearing or a speaker waking is not pushed to us.
    func refreshDevices() {
        guard isConnected else { return }
        Task { [weak self] in
            guard let token = await SpotifyAuth.shared.validAccessToken() else { return }
            await self?.loadDevices(token: token)
        }
    }

    private func loadDevices(token: String) async {
        await MainActor.run { [weak self] in
            guard let self, self.devices.isEmpty else { return }
            self.isLoadingDevices = true
        }

        async let devices = SpotifyClient.devices(token: token)
        async let playback = SpotifyClient.playback(token: token)
        let loaded = await (devices, playback)

        await MainActor.run { [weak self] in
            guard let self else { return }
            self.devices = loaded.0
            self.activeContextURI = loaded.1?.contextURI
            self.isPlayingRemotely = loaded.1?.isPlaying ?? false
            self.isLoadingDevices = false
        }
    }

    func clear() {
        profile = nil
        playlists = []
        devices = []
        forYou = []
        searchResults = []
        images = [:]
        imageOrder = []
        activeContextURI = nil
        lastLibraryLoad = .distantPast
    }

    /// The For You shelf: what was actually played recently, with the
    /// account's own playlists mixed in behind it. Both are real; neither is
    /// a recommendation Spotify would not give you itself.
    private static func shelf(
        history: [SpotifyClient.Item],
        playlists: [SpotifyClient.Playlist]
    ) -> [SpotifyClient.Item] {
        let fromPlaylists = playlists.prefix(6).map { playlist in
            SpotifyClient.Item(
                id: playlist.id,
                title: playlist.name,
                subtitle: playlist.owner,
                artworkURL: playlist.artworkURL,
                uri: playlist.uri,
                kind: .playlist
            )
        }

        var shelf: [SpotifyClient.Item] = []
        var seen = Set<String>()
        // Alternate so the row is neither all covers nor all playlists.
        for index in 0 ..< max(history.count, fromPlaylists.count) {
            if history.indices.contains(index), seen.insert(history[index].id).inserted {
                shelf.append(history[index])
            }
            if fromPlaylists.indices.contains(index),
               seen.insert(fromPlaylists[index].id).inserted {
                shelf.append(fromPlaylists[index])
            }
        }
        return Array(shelf.prefix(12))
    }

    // MARK: - Search

    /// Debounced: typing a title should not be one request per keystroke.
    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled,
                  let token = await SpotifyAuth.shared.validAccessToken()
            else { return }
            let results = await SpotifyClient.search(text, token: token)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.query.trimmingCharacters(in: .whitespacesAndNewlines) == text
                else { return }
                self.searchResults = results
                self.isSearching = false
            }
        }
    }

    // MARK: - Playback

    /// Starts a playlist, album or track. Reports back through `lastError`
    /// rather than silently doing nothing: "no active device" is the usual
    /// reason, and the user can only fix it if they are told.
    func play(uri: String, deviceID: String? = nil) {
        act { [weak self] token in
            let target = deviceID ?? self?.devices.first(where: \.isActive)?.id
            let started = await SpotifyClient.play(
                contextURI: uri, deviceID: target, token: token
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                if started {
                    self.activeContextURI = uri
                    self.isPlayingRemotely = true
                    self.lastError = nil
                } else {
                    self.lastError = self.devices.isEmpty
                        ? "No Spotify device is available. Open Spotify somewhere first."
                        : "Spotify wouldn't start that — Premium is required for remote playback."
                }
            }
        }
    }

    func transfer(to device: SpotifyClient.Device) {
        act { [weak self] token in
            let moved = await SpotifyClient.transferPlayback(
                to: device.id, play: true, token: token
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                if moved {
                    self.devices = self.devices.map { existing in
                        SpotifyClient.Device(
                            id: existing.id,
                            name: existing.name,
                            type: existing.type,
                            isActive: existing.id == device.id,
                            volumePercent: existing.volumePercent,
                            supportsVolume: existing.supportsVolume
                        )
                    }
                    self.lastError = nil
                } else {
                    self.lastError = "Couldn't move playback to \(device.name)."
                }
            }
            await self?.loadDevices(token: token)
        }
    }

    /// Device volume, 0...1. The local value moves immediately so the bar
    /// tracks the drag; Spotify is told once the value settles.
    func setVolume(_ fraction: Double, for device: SpotifyClient.Device) {
        let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
        devices = devices.map { existing in
            guard existing.id == device.id else { return existing }
            return SpotifyClient.Device(
                id: existing.id,
                name: existing.name,
                type: existing.type,
                isActive: existing.isActive,
                volumePercent: percent,
                supportsVolume: existing.supportsVolume
            )
        }

        volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled,
                  let token = await SpotifyAuth.shared.validAccessToken()
            else { return }
            await SpotifyClient.setVolume(percent: percent, deviceID: device.id, token: token)
        }
    }

    private var volumeTask: Task<Void, Never>?

    private func act(_ body: @escaping (String) async -> Void) {
        Task { [weak self] in
            guard let token = await SpotifyAuth.shared.validAccessToken() else {
                await MainActor.run { [weak self] in
                    self?.lastError = "Spotify sign-in expired. Reconnect in Settings."
                }
                return
            }
            await body(token)
        }
    }

    // MARK: - Artwork

    /// The cover for a URL, fetched once and kept. Returns nil the first time
    /// and starts the download; the view redraws when it arrives.
    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        let key = url.absoluteString
        if let cached = images[key] { return cached }
        guard !imageTasks.contains(key) else { return nil }
        imageTasks.insert(key)

        Task { [weak self] in
            let loaded = await SpotifyClient.image(at: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.imageTasks.remove(key)
                guard let loaded else { return }
                self.images[key] = loaded
                self.imageOrder.append(key)
                while self.imageOrder.count > Self.imageCacheLimit {
                    let oldest = self.imageOrder.removeFirst()
                    self.images.removeValue(forKey: oldest)
                }
            }
        }
        return nil
    }
}
