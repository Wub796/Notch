import AppKit
import Foundation

/// The slice of Spotify's Web API the player uses: what is queued next, and
/// how many followers the current artist has.
///
/// Two things in the reference cannot come from here, and are not faked:
/// per-track play counts and an artist's *monthly listeners* are not in the
/// Web API at all — they are figures the Spotify client gets from a private
/// endpoint. Follower count is the closest published equivalent, and track
/// popularity (0–100) is the closest to a play count.
struct SpotifyClient {
    struct QueueItem: Equatable, Identifiable {
        let id: String
        let title: String
        let artist: String
        let artworkURL: URL?
        var artwork: NSImage?
    }

    private static let base = URL(string: "https://api.spotify.com/v1")!

    // MARK: - Queue

    private struct QueueResponse: Decodable {
        let queue: [Track]

        struct Track: Decodable {
            let id: String?
            let name: String
            let artists: [Artist]
            let album: Album

            struct Artist: Decodable { let name: String }
            struct Album: Decodable {
                let images: [Image]
                struct Image: Decodable { let url: String }
            }
        }
    }

    /// What is coming up. Returns an empty list rather than an error when
    /// nothing is playing, which is the common case.
    static func queue(token: String) async -> [QueueItem] {
        guard let data = await get("me/player/queue", token: token),
              let response = try? JSONDecoder().decode(QueueResponse.self, from: data)
        else { return [] }

        return response.queue.prefix(8).enumerated().map { index, track in
            QueueItem(
                id: track.id ?? "\(index)-\(track.name)",
                title: track.name,
                artist: track.artists.first?.name ?? "",
                artworkURL: track.album.images.last.flatMap { URL(string: $0.url) }
            )
        }
    }

    // MARK: - Artist

    private struct SearchResponse: Decodable {
        let artists: Artists
        struct Artists: Decodable {
            let items: [Item]
            struct Item: Decodable {
                let followers: Followers
                struct Followers: Decodable { let total: Int }
            }
        }
    }

    /// Follower count for an artist by name. Nil when the search finds
    /// nothing, so the caller can leave the line out entirely.
    static func followers(forArtist name: String, token: String) async -> Int? {
        guard !name.isEmpty,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let data = await get("search?type=artist&limit=1&q=\(encoded)", token: token),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else { return nil }
        return response.artists.items.first?.followers.total
    }

    // MARK: - Transport

    private static func get(_ path: String, token: String) async -> Data? {
        guard let url = URL(string: path, relativeTo: base) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode),
              !data.isEmpty
        else { return nil }
        return data
    }

    /// Downloads a queue item's cover.
    static func artwork(for item: QueueItem) async -> NSImage? {
        guard let url = item.artworkURL,
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - Library, devices and discovery
//
// The screens that browse Spotify rather than just follow it: the account's
// playlists, its Connect devices, and what to play next. Everything here is
// real Web API data — nothing is invented, and a call that fails returns
// nothing rather than a placeholder, so a screen is either true or empty.

extension SpotifyClient {
    // MARK: Profile

    struct Profile: Equatable {
        let id: String
        let displayName: String
    }

    private struct ProfileResponse: Decodable {
        let id: String
        let display_name: String?
    }

    static func profile(token: String) async -> Profile? {
        guard let data = await get("me", token: token),
              let response = try? JSONDecoder().decode(ProfileResponse.self, from: data)
        else { return nil }
        return Profile(
            id: response.id,
            displayName: response.display_name ?? response.id
        )
    }

    // MARK: Playlists

    struct Playlist: Identifiable, Equatable {
        let id: String
        let name: String
        let uri: String
        let owner: String
        let artworkURL: URL?
        let trackCount: Int
    }

    private struct PlaylistsResponse: Decodable {
        let items: [Item?]

        struct Item: Decodable {
            let id: String
            let name: String
            let uri: String
            let images: [Image]?
            let owner: Owner?
            let tracks: Tracks?

            struct Image: Decodable { let url: String }
            struct Owner: Decodable { let display_name: String? }
            struct Tracks: Decodable { let total: Int }
        }
    }

    /// The account's playlists in Spotify's own order, which is what its
    /// "Recents" sort means — the API returns them most-recently-touched first.
    static func playlists(token: String) async -> [Playlist] {
        guard let data = await get("me/playlists?limit=50", token: token),
              let response = try? JSONDecoder().decode(PlaylistsResponse.self, from: data)
        else { return [] }

        // Spotify sends nulls in this list for playlists the account can no
        // longer see; decoding them as optional and dropping them is the only
        // way through without failing the whole page.
        return response.items.compactMap { item in
            guard let item else { return nil }
            return Playlist(
                id: item.id,
                name: item.name,
                uri: item.uri,
                owner: item.owner?.display_name ?? "",
                artworkURL: item.images?.first.flatMap { URL(string: $0.url) },
                trackCount: item.tracks?.total ?? 0
            )
        }
    }

    // MARK: Connect devices

    struct Device: Identifiable, Equatable {
        let id: String
        let name: String
        let type: String
        let isActive: Bool
        let volumePercent: Int?
        let supportsVolume: Bool

        var symbolName: String {
            switch type.lowercased() {
            case "computer": "laptopcomputer"
            case "smartphone": "iphone"
            case "tablet": "ipad"
            case "tv", "castvideo": "tv"
            case "speaker", "castaudio": "hifispeaker.fill"
            case "avr", "stb": "av.remote.fill"
            case "automobile": "car.fill"
            default: "hifispeaker.fill"
            }
        }
    }

    private struct DevicesResponse: Decodable {
        let devices: [Item]

        struct Item: Decodable {
            let id: String?
            let name: String
            let type: String
            let is_active: Bool
            let volume_percent: Int?
            let supports_volume: Bool?
        }
    }

    static func devices(token: String) async -> [Device] {
        guard let data = await get("me/player/devices", token: token),
              let response = try? JSONDecoder().decode(DevicesResponse.self, from: data)
        else { return [] }

        return response.devices.compactMap { item in
            guard let id = item.id else { return nil }
            return Device(
                id: id,
                name: item.name,
                type: item.type,
                isActive: item.is_active,
                volumePercent: item.volume_percent,
                supportsVolume: item.supports_volume ?? (item.volume_percent != nil)
            )
        }
    }

    // MARK: Playback control

    @discardableResult
    static func setVolume(percent: Int, deviceID: String?, token: String) async -> Bool {
        let clamped = min(max(percent, 0), 100)
        var path = "me/player/volume?volume_percent=\(clamped)"
        if let deviceID { path += "&device_id=\(deviceID)" }
        return await put(path, token: token)
    }

    @discardableResult
    static func transferPlayback(to deviceID: String, play: Bool, token: String) async -> Bool {
        await put(
            "me/player",
            token: token,
            body: ["device_ids": [deviceID], "play": play]
        )
    }

    /// Starts a playlist (or any context). `deviceID` targets a specific
    /// Connect device; without one Spotify uses whatever is already active.
    @discardableResult
    static func play(contextURI: String?, deviceID: String?, token: String) async -> Bool {
        var path = "me/player/play"
        if let deviceID { path += "?device_id=\(deviceID)" }
        var body: [String: Any] = [:]
        if let contextURI {
            if contextURI.contains(":track:") {
                body["uris"] = [contextURI]
            } else {
                body["context_uri"] = contextURI
            }
        }
        return await put(path, token: token, body: body.isEmpty ? nil : body)
    }

    // MARK: Playback state

    struct Playback: Equatable {
        let contextURI: String?
        let isPlaying: Bool
        let deviceID: String?
        let trackID: String?
    }

    private struct PlaybackResponse: Decodable {
        let is_playing: Bool?
        let context: Context?
        let device: Device?
        let item: Item?

        struct Context: Decodable { let uri: String? }
        struct Device: Decodable { let id: String? }
        struct Item: Decodable { let id: String? }
    }

    /// What the account is playing, wherever it is playing. `nil` when nothing
    /// is — Spotify answers that with `204 No Content` and an empty body.
    static func playback(token: String) async -> Playback? {
        guard let data = await get("me/player", token: token),
              let response = try? JSONDecoder().decode(PlaybackResponse.self, from: data)
        else { return nil }
        return Playback(
            contextURI: response.context?.uri,
            isPlaying: response.is_playing ?? false,
            deviceID: response.device?.id,
            trackID: response.item?.id
        )
    }

    // MARK: Saved songs

    /// Whether the track is in the account's Liked Songs.
    static func isSaved(trackID: String, token: String) async -> Bool {
        guard let data = await get("me/tracks/contains?ids=\(trackID)", token: token),
              let flags = try? JSONDecoder().decode([Bool].self, from: data)
        else { return false }
        return flags.first ?? false
    }

    /// Adds or removes the track from Liked Songs.
    @discardableResult
    static func setSaved(_ saved: Bool, trackID: String, token: String) async -> Bool {
        await write(
            "me/tracks?ids=\(trackID)",
            method: saved ? "PUT" : "DELETE",
            token: token,
            body: nil
        )
    }

    // MARK: Discovery

    struct Item: Identifiable, Equatable {
        enum Kind: String { case track, album, playlist, artist }

        let id: String
        let title: String
        let subtitle: String
        let artworkURL: URL?
        let uri: String
        let kind: Kind
    }

    private struct RecentlyPlayedResponse: Decodable {
        let items: [Entry]

        struct Entry: Decodable {
            let track: Track

            struct Track: Decodable {
                let id: String?
                let uri: String
                let name: String
                let artists: [Artist]
                let album: Album

                struct Artist: Decodable { let name: String }
                struct Album: Decodable {
                    let images: [Image]?
                    struct Image: Decodable { let url: String }
                }
            }
        }
    }

    /// Recently played tracks, de-duplicated: the raw feed repeats a track
    /// once per listen, which fills a shelf with the same cover four times.
    static func recentlyPlayed(token: String) async -> [Item] {
        guard let data = await get("me/player/recently-played?limit=30", token: token),
              let response = try? JSONDecoder().decode(RecentlyPlayedResponse.self, from: data)
        else { return [] }

        var seen = Set<String>()
        var items: [Item] = []
        for entry in response.items {
            let track = entry.track
            let key = track.id ?? track.uri
            guard seen.insert(key).inserted else { continue }
            items.append(
                Item(
                    id: key,
                    title: track.name,
                    subtitle: track.artists.first?.name ?? "",
                    artworkURL: track.album.images?.first.flatMap { URL(string: $0.url) },
                    uri: track.uri,
                    kind: .track
                )
            )
        }
        return items
    }

    private struct CatalogSearchResponse: Decodable {
        let tracks: Page<TrackItem>?
        let albums: Page<AlbumItem>?
        let playlists: Page<PlaylistItem>?
        let artists: Page<ArtistItem>?

        struct Page<Element: Decodable>: Decodable { let items: [Element?] }
        struct Image: Decodable { let url: String }

        struct TrackItem: Decodable {
            let id: String?
            let uri: String
            let name: String
            let artists: [Named]
            let album: AlbumRef
            struct AlbumRef: Decodable { let images: [Image]? }
        }
        struct AlbumItem: Decodable {
            let id: String?
            let uri: String
            let name: String
            let artists: [Named]
            let images: [Image]?
        }
        struct PlaylistItem: Decodable {
            let id: String?
            let uri: String
            let name: String
            let images: [Image]?
            let owner: Owner?
            struct Owner: Decodable { let display_name: String? }
        }
        struct ArtistItem: Decodable {
            let id: String?
            let uri: String
            let name: String
            let images: [Image]?
        }
        struct Named: Decodable { let name: String }
    }

    /// One search across the four kinds the reference offers, interleaved so
    /// the first row is not all tracks.
    static func search(_ query: String, token: String) async -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let data = await get(
                  "search?q=\(encoded)&type=track,album,playlist,artist&limit=6",
                  token: token
              ),
              let response = try? JSONDecoder().decode(CatalogSearchResponse.self, from: data)
        else { return [] }

        let tracks = (response.tracks?.items ?? []).compactMap { item -> Item? in
            guard let item else { return nil }
            return Item(
                id: item.id ?? item.uri,
                title: item.name,
                subtitle: item.artists.first?.name ?? "",
                artworkURL: item.album.images?.first.flatMap { URL(string: $0.url) },
                uri: item.uri,
                kind: .track
            )
        }
        let albums = (response.albums?.items ?? []).compactMap { item -> Item? in
            guard let item else { return nil }
            return Item(
                id: item.id ?? item.uri,
                title: item.name,
                subtitle: item.artists.first?.name ?? "Album",
                artworkURL: item.images?.first.flatMap { URL(string: $0.url) },
                uri: item.uri,
                kind: .album
            )
        }
        let playlists = (response.playlists?.items ?? []).compactMap { item -> Item? in
            guard let item else { return nil }
            return Item(
                id: item.id ?? item.uri,
                title: item.name,
                subtitle: item.owner?.display_name ?? "Playlist",
                artworkURL: item.images?.first.flatMap { URL(string: $0.url) },
                uri: item.uri,
                kind: .playlist
            )
        }
        let artists = (response.artists?.items ?? []).compactMap { item -> Item? in
            guard let item else { return nil }
            return Item(
                id: item.id ?? item.uri,
                title: item.name,
                subtitle: "Artist",
                artworkURL: item.images?.first.flatMap { URL(string: $0.url) },
                uri: item.uri,
                kind: .artist
            )
        }

        // Round-robin, so each kind is represented near the top.
        var interleaved: [Item] = []
        let columns = [tracks, playlists, albums, artists]
        let depth = columns.map(\.count).max() ?? 0
        for index in 0..<depth {
            for column in columns where column.indices.contains(index) {
                interleaved.append(column[index])
            }
        }
        return interleaved
    }

    // MARK: Images

    static func image(at url: URL) async -> NSImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else { return nil }
        return NSImage(data: data)
    }

    // MARK: Transport

    /// `PUT` with an optional JSON body. Spotify answers these with `204 No
    /// Content`, so success is the status code and nothing else.
    private static func put(
        _ path: String,
        token: String,
        body: [String: Any]? = nil
    ) async -> Bool {
        await write(path, method: "PUT", token: token, body: body)
    }

    private static func write(
        _ path: String,
        method: String,
        token: String,
        body: [String: Any]? = nil
    ) async -> Bool {
        guard let url = URL(string: path, relativeTo: base) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return (200 ..< 300).contains(http.statusCode)
    }
}
