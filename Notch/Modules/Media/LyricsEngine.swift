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

    private(set) var lines: [Line] = []
    private(set) var currentIndex: Int?
    private(set) var isSynced = false
    private(set) var isLoading = false

    private var loadedTrackKey: String?
    private var fetchTask: Task<Void, Never>?

    private static let timestampRegex = try? NSRegularExpression(
        pattern: #"\[(\d+):(\d{1,2}(?:\.\d+)?)\]"#
    )

    func load(title: String, artist: String, album: String, duration: TimeInterval) {
        let key = "\(title)|\(artist)"
        guard key != loadedTrackKey else { return }
        loadedTrackKey = key

        clearContent()
        guard !title.isEmpty else { return }
        isLoading = true

        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
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

            struct LRCLIBResponse: Decodable {
                let syncedLyrics: String?
                let plainLyrics: String?
            }

            var synced: [Line] = []
            var plain: [Line] = []
            if let url = components.url,
               let (data, _) = try? await URLSession.shared.data(from: url),
               let response = try? JSONDecoder().decode(LRCLIBResponse.self, from: data) {
                synced = Self.parseLRC(response.syncedLyrics ?? "")
                plain = Self.plainLines(response.plainLyrics ?? "")
            }

            guard !Task.isCancelled else { return }
            let resolved = synced.isEmpty ? plain : synced
            let resolvedIsSynced = !synced.isEmpty
            await MainActor.run { [weak self] in
                guard let self, self.loadedTrackKey == key else { return }
                self.lines = resolved
                self.isSynced = resolvedIsSynced
                self.currentIndex = nil
                self.isLoading = false
            }
        }
    }

    func clear() {
        loadedTrackKey = nil
        fetchTask?.cancel()
        clearContent()
    }

    private func clearContent() {
        lines = []
        currentIndex = nil
        isSynced = false
        isLoading = false
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

    // MARK: - LRC parsing

    static func parseLRC(_ text: String) -> [Line] {
        guard let regex = timestampRegex, !text.isEmpty else { return [] }

        var result: [(time: TimeInterval, text: String)] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: rawLine, range: fullRange)
            guard let last = matches.last else { continue }

            let content = nsLine
                .substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }

            // A line may carry several timestamps ("[00:12.3][01:04.9]lyric").
            for match in matches {
                let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                result.append((minutes * 60 + seconds, content))
            }
        }

        return result
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { Line(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }

    static func plainLines(_ text: String) -> [Line] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { Line(id: $0.offset, time: 0, text: $0.element) }
    }
}
