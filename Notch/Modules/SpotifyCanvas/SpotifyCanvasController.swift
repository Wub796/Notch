import Foundation
import Observation

/// Keeps the current track's Spotify Canvas video on hand for the views.
///
/// It watches the player: when the track changes it resolves that track's
/// Canvas (off the main thread) and publishes the URL, or clears it when there
/// is none. Everything is gated — the feature switch, a working session, and
/// something actually playing — so a signed-out or disabled app does no work
/// and makes no network calls.
@Observable
final class SpotifyCanvasController {
    /// The Canvas video for what is playing now, if any. The views show it in
    /// place of the album art.
    private(set) var canvasURL: URL?

    private let session: SpotifyCanvasSession
    private let settings: NotchSettings
    private weak var media: MediaController?

    /// The track a published URL belongs to, so a stale fetch landing late
    /// cannot attach a video to the wrong song.
    private var currentKey: String?
    private var fetchTask: Task<Void, Never>?

    init(session: SpotifyCanvasSession, media: MediaController, settings: NotchSettings = .shared) {
        self.session = session
        self.media = media
        self.settings = settings
    }

    private func key(for track: MediaController.Track) -> String {
        "\(track.title)|\(track.artist)"
    }

    /// Whether the feature is on and there is a session to fetch with.
    private var isEnabled: Bool {
        settings.spotifyCanvasEnabled && session.hasCookie
    }

    /// Called when the player's track changes. Resolves the new track's Canvas,
    /// or clears the current one.
    func trackChanged() {
        guard isEnabled else {
            clear()
            return
        }
        guard let media, media.isPlaying, let track = media.track,
              !track.title.isEmpty, !media.isBrowserVideo
        else {
            clear()
            return
        }

        let key = key(for: track)
        // Same track (a re-anchor, an artwork refresh) — keep what we have.
        guard key != currentKey else { return }
        currentKey = key
        canvasURL = nil

        fetchTask?.cancel()
        let client = SpotifyCanvasClient(session: session)
        fetchTask = Task { [weak self] in
            let url = await client.canvasURL(
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.currentKey == key else { return }
                self.canvasURL = url
            }
        }
    }

    /// Re-evaluates the current track — after a sign-in, or when the feature is
    /// toggled — without waiting for the next track change.
    func refresh() {
        currentKey = nil
        trackChanged()
    }

    private func clear() {
        fetchTask?.cancel()
        fetchTask = nil
        currentKey = nil
        if canvasURL != nil { canvasURL = nil }
    }
}
