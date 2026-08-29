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
