import Foundation
import Observation

/// Fetches synchronized (LRC) lyrics for the current track from the free
/// LRCLIB catalog, parses the timestamps, and tracks which line is live so
/// the view can auto-scroll.
@Observable
final class LyricsEngine {
    struct Line: Identifiable, Equatable {
        let id: Int
        let time: TimeInterval
        let text: String
    }

    /// One line as the closed notch shows it: its text and the span it is
    /// sung over.
    struct LiveLine: Equatable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    private(set) var lines: [Line] = []
    private(set) var currentIndex: Int?
    private(set) var isSynced = false
    private(set) var isLoading = false

    /// Where instrumental passages begin: the blank or non-vocal lines an LRC
    /// file carries between verses. Not kept as lines — they would be empty
    /// rows in the scrolling list — but each one ends whatever was sung before.
    private(set) var breaks: [TimeInterval] = []

    var currentLine: Line? {
        guard let currentIndex, lines.indices.contains(currentIndex) else { return nil }
        return lines[currentIndex]
    }

    private var loadedTrackKey: String?
    private var fetchTask: Task<Void, Never>?

    private static let timestampRegex = try? NSRegularExpression(
        pattern: #"\[(\d+):(\d{1,2}(?:\.\d+)?)\]"#
    )

    /// LRCLIB asks clients to identify themselves; anonymous traffic is rate
    /// limited harder.
    private static let userAgent = "Notch/1.0 (macOS menu bar utility)"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()

    func load(title: String, artist: String, album: String, duration: TimeInterval) {
        let key = "\(title)|\(artist)"
        guard key != loadedTrackKey else { return }
        loadedTrackKey = key

        fetchTask?.cancel()
        clearContent()
        guard !title.isEmpty else { return }
        isLoading = true

        fetchTask = Task { [weak self] in
            let result = await Self.fetchLyrics(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.loadedTrackKey == key else { return }
                self.lines = result.lines
                self.breaks = result.breaks
                self.isSynced = result.isSynced
                self.currentIndex = nil
                self.isLoading = false
            }
        }
    }

    func clear() {
        loadedTrackKey = nil
        fetchTask?.cancel()
        fetchTask = nil
        clearContent()
    }

    private func clearContent() {
        lines = []
        breaks = []
        currentIndex = nil
        isSynced = false
        isLoading = false
    }

    /// The line being sung right now, and the span it is sung over — what the
    /// closed notch's one-line activity draws. nil when nothing is being sung.
    ///
    /// Deliberately not `currentLine`. In the scrolling list, keeping the last
    /// sung line highlighted is correct: it marks where you are in the song.
    /// Under the closed notch there is no list to mark a place in, so a line
    /// has to go away once it has been sung.
    ///
    /// LRC carries only start times, so a line's end is inferred: the next line
    /// or instrumental marker, or — when the next line is a long way off —
    /// about as long as the line takes to sing. The old rule held every line
    /// until the next one (up to 8s) and threw the break markers away, so a
    /// lyric sat on the notch through instrumental passages. Lines sung back to
    /// back are bridged, so the row does not blink out between them.
    func liveLine(at time: TimeInterval) -> LiveLine? {
        guard isSynced, !lines.isEmpty else { return nil }
        guard let index = lines.lastIndex(where: { $0.time <= time }) else { return nil }

        let line = lines[index]
        let nextLine = index + 1 < lines.count ? lines[index + 1].time : .infinity
        let nextBreak = breaks.first { $0 > line.time } ?? .infinity

        var end = line.time + Self.singingDuration(for: line.text)
        if nextLine - end < Self.bridgeGap { end = nextLine }
        end = min(end, nextLine, nextBreak)

        guard time < end else { return nil }
        return LiveLine(text: line.text, start: line.time, end: end)
    }

    /// A gap shorter than this between one line ending and the next starting
    /// is a breath, not a pause in the singing.
    private static let bridgeGap: TimeInterval = 1.5

    /// Roughly how long a line takes to sing: about half a second a word, with
    /// a floor so a one-word line can still be read and a ceiling so a long
    /// outro cannot hold the last line on screen.
    static func singingDuration(for text: String) -> TimeInterval {
        let words = text.split(whereSeparator: \.isWhitespace).count
        // Scripts written without spaces between words count by character.
        let units = max(words, Int((Double(text.count) / 5).rounded()))
        return min(max(1.2 + Double(units) * 0.45, 2.5), 7)
    }

    /// Called on each playback tick; moves the highlighted line to the last
    /// timestamp at or before the playhead.
    func updateCurrentLine(for time: TimeInterval) {
        guard isSynced, !lines.isEmpty else { return }
        let index = lines.lastIndex { $0.time <= time }
        if index != currentIndex {
            currentIndex = index
        }
    }

    // MARK: - Networking

    private struct Payload: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?

        var hasContent: Bool {
            !(syncedLyrics ?? "").isEmpty || !(plainLyrics ?? "").isEmpty
        }
    }

    /// The catalog is queried in three passes, because a single `/api/get`
    /// almost never hits: it needs the title, the artist **and** the duration
    /// to line up, and players report titles with all sorts of suffixes
    /// ("… - Remastered 2011", "… (feat. X)"). Nothing here threw before —
    /// LRCLIB answers a miss with `200`-shaped JSON that decoded cleanly into
    /// an all-`nil` payload, so every lookup silently produced no lyrics.
    private static func fetchLyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> (lines: [Line], breaks: [TimeInterval], isSynced: Bool) {
        let cleanTitle = cleaned(title)
        let cleanArtist = cleaned(artist)

        var payload = await get(title: title, artist: artist, album: album, duration: duration)

        if payload == nil, cleanTitle != title || cleanArtist != artist {
            payload = await get(title: cleanTitle, artist: cleanArtist, album: "", duration: duration)
        }

        if payload == nil {
            payload = await search(title: cleanTitle, artist: cleanArtist, duration: duration)
        }

        if payload == nil, !cleanArtist.isEmpty {
            // Last resort: title only. Compilations and live cuts are filed
            // under a different artist string than the player reports.
            payload = await search(title: cleanTitle, artist: "", duration: duration)
        }

        guard let payload else { return ([], [], false) }

        let synced = parseLRC(payload.syncedLyrics ?? "")
        if !synced.lines.isEmpty { return (synced.lines, synced.breaks, true) }
        return (plainLines(payload.plainLyrics ?? ""), [], false)
    }

    /// Exact lookup. Returns nil for anything that is not a usable hit — a
    /// 404, a body without lyrics, or a transport failure.
    private static func get(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> Payload? {
        guard !title.isEmpty else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var query = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if !album.isEmpty {
            query.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration > 0 {
            query.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components.queryItems = query
        guard let data = await body(for: components.url) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.hasContent
        else { return nil }
        return payload
    }

    /// Fuzzy lookup. Picks the closest duration among the results that
    /// actually carry synced lyrics, falling back to plain ones.
    private static func search(
        title: String,
        artist: String,
        duration: TimeInterval
    ) async -> Payload? {
        guard !title.isEmpty else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        var query = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            query.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components.queryItems = query

        guard let data = await body(for: components.url),
              let results = try? JSONDecoder().decode([Payload].self, from: data)
        else { return nil }

        let usable = results.filter(\.hasContent)
        guard !usable.isEmpty else { return nil }

        func distance(_ candidate: Payload) -> Double {
            guard duration > 0, let other = candidate.duration, other > 0 else { return 999 }
            return abs(other - duration)
        }

        let synced = usable.filter { !($0.syncedLyrics ?? "").isEmpty }
        let pool = synced.isEmpty ? usable : synced
        // More than a few seconds off is a different edit of the song — a
        // radio edit, a longer intro — whose timestamps would run early or late
        // the whole way through. 15s let those through, and the lyrics never
        // lined up with what was playing.
        let best = pool.min { distance($0) < distance($1) }
        if let best, duration > 0, distance(best) > 4, distance(best) != 999 { return nil }
        return best
    }

    /// One request, with the status code actually checked.
    private static func body(for url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return data
    }

    /// Strips the decoration players hang off titles and artists, which is
    /// what makes the exact lookup miss: "Song (feat. X) - Remastered 2011"
    /// is filed in the catalog as "Song", and "A, B & C" as "A".
    static func cleaned(_ value: String) -> String {
        var text = value
        for pattern in [
            #"\s*[\(\[](feat|ft|with|prod)\.?[^\)\]]*[\)\]]"#,
            #"\s*[\(\[][^\)\]]*(remaster|remastered|deluxe|mono|stereo|version|edit|live|bonus|explicit)[^\)\]]*[\)\]]"#,
            #"\s*-\s*(\d{4}\s*)?(remaster|remastered|deluxe|mono|stereo|radio edit|single version|live)[^-]*$"#,
        ] {
            text = text.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Multiple artists: the catalog files a track under the first one.
        if let separator = text.range(of: #"\s*(,|&|;|\sfeat\.?\s|\sft\.?\s|\sx\s)"#,
                                      options: [.regularExpression, .caseInsensitive]) {
            let head = String(text[text.startIndex..<separator.lowerBound])
            if head.count >= 2 { text = head }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - LRC parsing

    static func parseLRC(_ text: String) -> (lines: [Line], breaks: [TimeInterval]) {
        guard let regex = timestampRegex, !text.isEmpty else { return ([], []) }

        var result: [(time: TimeInterval, text: String)] = []
        var breaks: [TimeInterval] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: rawLine, range: fullRange)
            guard let last = matches.last else { continue }

            let content = nsLine
                .substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            // A timestamp with nothing sung after it marks where an
            // instrumental passage starts. These used to be dropped for having
            // no text, which left the previous line up through the whole break.
            let isVocal = !content.isEmpty && !isNonVocal(content)

            // A line may carry several timestamps ("[00:12.3][01:04.9]lyric").
            for match in matches {
                let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                let time = minutes * 60 + seconds
                if isVocal {
                    result.append((time, content))
                } else {
                    breaks.append(time)
                }
            }
        }

        let lines = result
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { Line(id: $0.offset, time: $0.element.time, text: $0.element.text) }
        return (lines, breaks.sorted())
    }

    /// Placeholder lines that stand for no singing at all: music notes, and the
    /// "(Instrumental)" / "[Music]" markers some catalog entries use.
    static func isNonVocal(_ text: String) -> Bool {
        let decoration = CharacterSet(charactersIn: "♪♫♬🎵🎶()[]*-–—….").union(.whitespaces)
        let stripped = text.trimmingCharacters(in: decoration)
        if stripped.isEmpty { return true }
        return ["instrumental", "music", "interlude", "solo", "guitar solo", "intro", "outro"]
            .contains(stripped.lowercased())
    }

    static func plainLines(_ text: String) -> [Line] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { Line(id: $0.offset, time: 0, text: $0.element) }
    }
}
