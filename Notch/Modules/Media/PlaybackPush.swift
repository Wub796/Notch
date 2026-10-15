import Foundation

/// One player's playback report, read out of whichever keys it uses.
///
/// Music and Spotify post the same report with different spellings — `Player
/// State` / `Total Time` against `PlaybackState` / `Duration`, a duration in
/// seconds against one in milliseconds — so the fields are matched without
/// case, spaces or underscores rather than through a per-player key table that
/// would go stale the first time either player renamed one.
///
/// Deliberately free of AppKit and of `MediaController`, so both players'
/// payload shapes can be exercised directly by the command-line checks (see
/// `tests/media/README.md`) instead of only inside the running app.
struct PlaybackPush: Equatable {
    /// What the player says it is playing.
    struct Metadata: Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
    }

    var bundleID: String
    /// The report's own play state, when it carried one.
    var playing: Bool?
    var metadata: Metadata?
    /// Music posts the cover itself.
    var artwork: Data?
    /// Spotify posts a URL to fetch.
    var artworkURL: URL?

    /// Reads one notification's payload. `playing` is the play state the caller
    /// has already resolved, and travels with the report so the adopting side
    /// does not have to parse it twice.
    static func parse(
        userInfo: [AnyHashable: Any], bundleID: String, playing: Bool?
    ) -> PlaybackPush {
        var push = PlaybackPush(bundleID: bundleID, playing: playing)
        let title = (value(userInfo, ["Name", "Title"]) as? String) ?? ""
        if !title.isEmpty {
            push.metadata = Metadata(
                title: title,
                artist: (value(userInfo, ["Artist", "ArtistName"]) as? String) ?? "",
                album: (value(userInfo, ["Album", "AlbumName"]) as? String) ?? "",
                duration: seconds(value(userInfo, ["Total Time", "Duration"])) ?? 0
            )
        }
        push.artwork = value(userInfo, ["Artwork", "ArtworkData"]) as? Data
        if let raw = value(
            userInfo, ["ArtworkURL", "ArtworkUrl", "ArtworkLocation"]
        ) as? String {
            push.artworkURL = URL(string: raw)
        }
        return push
    }

    /// The position a player's distributed playback notification carries.
    ///
    /// These notifications are the one push-based position source that works
    /// without consent, and they arrive on exactly the events that move the
    /// playhead — play, pause, track change and seek — so this is the app's
    /// chance to be exactly right at each of them. Spotify's key is
    /// `Playback Position`; reading only `Position`/`Player Position` meant the
    /// real position was dropped on every one of those events, leaving the
    /// extrapolated clock — which is what made a pause freeze at nothing, a
    /// resume keep a stale position, and a seek leave the lyrics where they
    /// were until something else happened to correct them.
    static func position(from userInfo: [AnyHashable: Any]) -> TimeInterval? {
        guard let raw = value(
            userInfo, ["Playback Position", "Position", "Player Position"]
        ) else { return nil }
        if let raw = raw as? Double { return raw }
        if let raw = raw as? NSNumber { return raw.doubleValue }
        return nil
    }

    /// Case-, space- and underscore-insensitive lookup: `Player State` and
    /// `PlaybackState` are the same field spelled by two different players.
    static func value(
        _ userInfo: [AnyHashable: Any], _ names: [String]
    ) -> Any? {
        let wanted = Set(names.map(normalizedKey))
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            if wanted.contains(normalizedKey(key)) { return value }
        }
        return nil
    }

    static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// A duration in seconds. The players disagree about the unit as well as
    /// the name — Spotify counts `Duration` in milliseconds — so anything past
    /// a couple of hours' worth of seconds is read as milliseconds.
    static func seconds(_ value: Any?) -> TimeInterval? {
        let raw: Double?
        if let number = value as? Double {
            raw = number
        } else if let number = value as? NSNumber {
            raw = number.doubleValue
        } else if let text = value as? String {
            raw = Double(text)
        } else {
            raw = nil
        }
        guard let raw, raw > 0 else { return nil }
        return raw > 10_000 ? raw / 1000 : raw
    }
}
