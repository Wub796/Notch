import Foundation

/// Turns "what's playing" into a Canvas video URL, using a session's token.
///
/// Two calls to Spotify. First a search, to turn the track's title and artist
/// into a Spotify track URI — done this way rather than reading an id off the
/// player so it works whatever the audio source is (the desktop app, a phone
/// over Spotify Connect, the web player). Then the Canvas lookup, which is a
/// protobuf endpoint: `canvaz-cache` speaks protobuf, not JSON, so the request
/// is hand-encoded and the reply hand-parsed for the one field that matters,
/// the video URL. Both are private endpoints and may change without notice.
struct SpotifyCanvasClient {
    let session: SpotifyCanvasSession

    private static let net: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    /// The Canvas video URL for the currently playing track, or nil when there
    /// is no match, no Canvas for the track, or the session cannot authorise.
    func canvasURL(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> URL? {
        guard let token = await session.token() else { return nil }
        guard let trackURI = await trackURI(
            title: title, artist: artist, album: album, duration: duration, token: token
        ) else { return nil }
        return await canvasURL(forTrackURI: trackURI, token: token)
    }

    // MARK: - Search

    private func trackURI(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        token: String
    ) async -> String? {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        // Field-scoped query so a track named like an artist does not drift the
        // match; album is left out because players report it inconsistently.
        let query = "track:\(title) artist:\(artist)"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components.url,
              let data = await authorizedBody(for: url, token: token),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tracks = (json["tracks"] as? [String: Any])?["items"] as? [[String: Any]],
              !tracks.isEmpty
        else { return nil }

        func score(_ track: [String: Any]) -> Double {
            var score = 0.0
            if let name = track["name"] as? String,
               name.caseInsensitiveCompare(title) == .orderedSame {
                score += 2
            }
            let artistNames = (track["artists"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String } ?? []
            if artistNames.contains(where: { $0.caseInsensitiveCompare(artist) == .orderedSame }) {
                score += 2
            } else if artistNames.contains(where: { $0.localizedCaseInsensitiveContains(artist) }) {
                score += 1
            }
            // Duration within a couple of seconds all but confirms the edit.
            if duration > 0, let ms = track["duration_ms"] as? Double {
                if abs(ms / 1000 - duration) < 3 { score += 2 }
                else if abs(ms / 1000 - duration) < 8 { score += 1 }
            }
            return score
        }

        let best = tracks.max { score($0) < score($1) }
        // A weak best match is worse than none: a wrong Canvas is more jarring
        // than album art. Require the title or artist to actually line up.
        guard let best, score(best) >= 2, let uri = best["uri"] as? String else { return nil }
        return uri
    }

    // MARK: - Canvas

    private func canvasURL(forTrackURI trackURI: String, token: String) async -> URL? {
        let endpoint = URL(string:
            "https://spclient.wg.spotify.com/canvaz-cache/v0/canvases")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue(SpotifyCanvasSession.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Proto.encodeCanvasRequest(trackURI: trackURI)

        guard let (data, response) = try? await Self.net.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }

        guard let raw = Proto.firstCanvasURL(in: data),
              let url = URL(string: raw),
              url.scheme == "https"
        else { return nil }
        return url
    }

    private func authorizedBody(for url: URL, token: String) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SpotifyCanvasSession.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await Self.net.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }
}

/// The sliver of protobuf the Canvas endpoint needs. Not a general codec — just
/// enough wire-format to write one request and read one field out of the reply.
///
/// Request (`EntityCanvazRequest`): a repeated `entities` field 1, each an
/// `Entity` whose field 1 is the track URI. Reply (`EntityCanvazResponse`): a
/// repeated `canvases` field 1, each a `Canvaz` whose field 2 is the video URL.
private enum Proto {
    static func encodeCanvasRequest(trackURI: String) -> Data {
        let uri = Data(trackURI.utf8)
        // Entity { entity_uri = 1 }
        var entity = Data()
        entity.append(tag(field: 1, wire: 2))
        entity.append(varint(UInt64(uri.count)))
        entity.append(uri)
        // EntityCanvazRequest { entities = 1 }
        var body = Data()
        body.append(tag(field: 1, wire: 2))
        body.append(varint(UInt64(entity.count)))
        body.append(entity)
        return body
    }

    /// Walks the response for the first `canvases[].url` (Canvaz field 2).
    static func firstCanvasURL(in data: Data) -> String? {
        var reader = Reader(data)
        while let field = reader.nextField() {
            // canvases = 1, length-delimited
            guard field.number == 1, case let .bytes(canvaz) = field.value else {
                continue
            }
            var inner = Reader(canvaz)
            while let sub = inner.nextField() {
                if sub.number == 2, case let .bytes(url) = sub.value {
                    return String(data: url, encoding: .utf8)
                }
            }
        }
        return nil
    }

    // MARK: wire helpers

    private static func tag(field: Int, wire: UInt8) -> Data {
        varint(UInt64(field) << 3 | UInt64(wire))
    }

    private static func varint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    /// A forgiving reader: unknown fields and wire types are skipped, so a
    /// reply that grows new fields still parses.
    struct Reader {
        private let data: [UInt8]
        private var index = 0

        init(_ data: Data) { self.data = [UInt8](data) }

        enum Value {
            case varint(UInt64)
            case bytes(Data)
            case fixed
        }

        struct Field {
            let number: Int
            let value: Value
        }

        mutating func nextField() -> Field? {
            guard let key = readVarint() else { return nil }
            let number = Int(key >> 3)
            let wire = UInt8(key & 0x7)
            switch wire {
            case 0:
                guard let value = readVarint() else { return nil }
                return Field(number: number, value: .varint(value))
            case 2:
                guard let length = readVarint(), let slice = read(Int(length)) else { return nil }
                return Field(number: number, value: .bytes(slice))
            case 5:
                guard read(4) != nil else { return nil }
                return Field(number: number, value: .fixed)
            case 1:
                guard read(8) != nil else { return nil }
                return Field(number: number, value: .fixed)
            default:
                return nil
            }
        }

        private mutating func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < data.count {
                let byte = data[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
                if shift >= 64 { return nil }
            }
            return nil
        }

        private mutating func read(_ count: Int) -> Data? {
            guard count >= 0, index + count <= data.count else { return nil }
            defer { index += count }
            return Data(data[index ..< index + count])
        }
    }
}
