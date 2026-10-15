import AppKit
import Observation
import SwiftUI

/// The cover on screen, and everything about getting it there.
///
/// Lifted out of `MediaController`, which was carrying the cover's lifecycle
/// next to the playback clock, the source arbitration and the transport
/// commands. This is one concern — one image, the URL it came from, a bounded
/// number of reads for a cover that has not arrived, and the accent read out of
/// it — and none of it is about playback.
///
/// It knows nothing about players beyond the three questions it asks its host:
/// which app owns the track on screen, whether that track is still the one on
/// screen, and whether a browser is on screen. The first is what keeps a read
/// aimed at the player that reported the track instead of at the configured
/// provider.
@Observable
final class CoverArtwork {

    /// What the store needs from the media source that owns it.
    ///
    /// Deliberately three questions and no state: the answers are live, and
    /// that matters — a read lands seconds after it starts, and whether it is
    /// still wanted is a question about the moment it lands, not the moment it
    /// was started.
    protocol Host: AnyObject {
        /// The player whose cover is worth reading for the track on screen, or
        /// nil when that track belongs to something the Apple Events path
        /// cannot read.
        var coverOwnerBundleID: String? { get }
        /// The track on screen, so a read that lands after the song has moved
        /// on is dropped.
        var coverReadTrack: MediaController.Track? { get }
        /// Whether a browser snapshot is on screen — the only time a probe
        /// thumbnail is the right image.
        var showsBrowserSnapshot: Bool { get }
    }

    /// The image itself, or nil for nothing to show.
    private(set) var image: NSImage?

    /// Bumped whenever a genuinely *different* artwork image replaces the
    /// current one. Views key their artwork crossfade on this value, so the
    /// 2s browser probe re-downloading the same thumbnail (and MediaRemote
    /// re-pushing the same data) does not re-trigger the crossfade. Only a
    /// real change in the image does.
    private(set) var version = 0

    /// Legible accent derived from the current artwork; tints the scrubber,
    /// play button, lyrics highlight, and the collapsed equalizer.
    private(set) var accent: Color = .white
    private var accentSourceHash: Int?

    /// The bytes the current image came from, so a re-push of the same cover is
    /// recognised as no change.
    private var lastData: Data?

    /// The browser artwork URL the current image came from, or the one already
    /// tried.
    ///
    /// The browser probe runs every second while a media surface is showing
    /// and hands over the same `hqdefault.jpg` URL every time. Without this,
    /// each tick started a fresh download of a thumbnail that had not changed
    /// — thousands of requests an hour for one video — and each one was a main
    /// queue hop on the way back. It also pins an in-flight read to the item it
    /// was started for: a result is applied only while its URL is still the
    /// current one, which is what the old title-and-artist comparison was for.
    private var loadedBrowserURL: URL?

    /// How many times the current track's cover has already been asked for, so
    /// a reader that keeps answering nothing is retried a few times and then
    /// left alone rather than polled for the rest of the song.
    private var readAttempts = 0
    private var pendingRead: DispatchWorkItem?
    private static let readLimit = 3
    private static let readDelay: TimeInterval = 3

    @ObservationIgnored weak var host: Host?

    deinit {
        pendingRead?.cancel()
    }

    // MARK: - What the media source tells it

    /// A new item is on screen.
    ///
    /// Its cover is read from scratch — the previous image's URL is not this
    /// one's, and the read budget is its own — and a read is armed, because a
    /// new track's cover is not always in the report that announced it. Music
    /// posts the new song the moment it starts, and a *streamed* track's album
    /// art is fetched after playback begins; MediaRemote's first update for a
    /// song is the same. Reading a cover only when a payload happened to carry
    /// one is why the previous song's art stayed up until a manual skip: a skip
    /// and a play from the app both produce a complete report, an automatic
    /// advance between tracks does not.
    ///
    /// A cover that does arrive cancels the armed read (see `set`), so the
    /// ordinary case costs nothing.
    func trackDidChange() {
        loadedBrowserURL = nil
        readAttempts = 0
        pendingRead?.cancel()
        pendingRead = nil
        guard host?.coverReadTrack != nil, host?.coverOwnerBundleID != nil else { return }
        armRead()
    }

    /// Nothing is playing: the cover and its accent go with the track.
    func clear() {
        set(nil, data: nil)
        accent = .white
        accentSourceHash = nil
    }

    /// The cover a player pushed with its report. A fetch that lands after the
    /// track has moved on is dropped, so the closed notch can never wear the
    /// previous song's cover.
    func apply(_ push: PlaybackPush, expected: MediaController.Track) {
        if let data = push.artwork, let image = NSImage(data: data) {
            set(image, data: data)
            return
        }
        guard let url = push.artworkURL else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.host?.coverReadTrack == expected else { return }
                self.set(image, data: data)
            }
        }.resume()
    }

    /// The cover bytes a MediaRemote reply carried.
    func apply(remoteArtwork data: Data) {
        set(NSImage(data: data), data: data)
    }

    /// Reads a browser item's thumbnail, once per URL.
    ///
    /// The probe hands over the same URL on every tick, so a URL whose image is
    /// already on screen is not downloaded again — one request per video
    /// instead of one per poll, which for a closed notch watching a video was
    /// fifty a minute. A read that comes back with nothing forgets the URL, so
    /// the next tick genuinely re-reads it: the retry for this path is the poll
    /// that is already running, and it heals a thumbnail that was not ready the
    /// first time.
    func apply(browserArtwork url: URL) {
        // Also the in-flight check: the probe path asks for the same URL from
        // both the snapshot application and the open, in the same tick.
        guard url != loadedBrowserURL else { return }
        loadedBrowserURL = url
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else {
                DispatchQueue.main.async { [weak self] in
                    // Not this item's thumbnail any more: nothing to re-read.
                    guard let self, self.loadedBrowserURL == url else { return }
                    // Forgotten rather than retried here: this path has the
                    // browser probe behind it, which comes back in a second or
                    // two and reads the URL again — a retry of its own would be
                    // a second request for the same thing.
                    self.loadedBrowserURL = nil
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.host?.showsBrowserSnapshot == true,
                      self.loadedBrowserURL == url
                else { return }
                self.set(image, data: data)
            }
        }.resume()
    }

    /// Reads the cover from the player that owns the track on screen. A no-op
    /// when that app is not one the notch can read.
    func readFromOwningPlayer() {
        guard let owner = host?.coverOwnerBundleID else { return }
        readCover(fromPlayer: owner)
    }

    // MARK: - The image

    /// Replaces the artwork, bumping `version` only when the image data
    /// genuinely changes. Same-data re-sets (the 2s browser probe re-downloading
    /// the same thumbnail, MediaRemote re-pushing the same payload) keep the
    /// version so the views' crossfade fires only on a real artwork change.
    /// When no data is available (the AppleScript fallback) the image instance
    /// itself is the change signal.
    ///
    /// Passing nothing clears the cover, which is what a *deliberate* clear
    /// wants (no track at all) and is never what a failed read wants — see
    /// `armRead`.
    private func set(_ image: NSImage?, data: Data?) {
        // A cover arrived — whether or not it differs from the one already on
        // screen — so the read that was waiting for one is done. Cancelling on
        // a *change* alone left a read armed for the second song of an album,
        // whose art is the same bytes as the first's.
        if image != nil {
            pendingRead?.cancel()
            pendingRead = nil
            readAttempts = 0
        }
        // Extracted before the change test, and off the main thread: a cover
        // that is already on screen still has to tint one if the accent was
        // reset under it.
        if let data {
            updateAccentIfNeeded(for: data)
        }
        let changed = data.map { $0 != lastData } ?? (image !== self.image)
        guard changed else { return }
        lastData = data
        self.image = image
        version += 1
    }

    /// Extracts the artwork accent off the main thread, once per unique image.
    private func updateAccentIfNeeded(for data: Data) {
        let hash = data.hashValue
        guard hash != accentSourceHash else { return }
        accentSourceHash = hash

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let image = NSImage(data: data) else { return }
            let color = NotchTheme.accent(from: image)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.accentSourceHash == hash else { return }
                withAnimation(.notchSpring) {
                    self.accent = color
                }
            }
        }
    }

    // MARK: - Reads that come back with nothing

    /// Arms a read of the current track's cover, a few seconds out.
    ///
    /// Armed from two places: a track change whose report arrived without a
    /// cover, and a cover read that came back with nothing. Artwork used to be
    /// fetched exactly once per track change and never again, so a reader that
    /// was merely slow — Music still pulling the album down, Spotify answering
    /// before its artwork URL is live, a thumbnail fetched while the network
    /// was reconnecting — left the media surfaces showing the *previous* song's
    /// cover, or none at all, for the whole of the new one. Worse, the player
    /// path treated an empty answer as a real result and cleared a cover it had
    /// just been showing.
    ///
    /// A cover arriving cancels the armed read, so this is the mechanism for
    /// "no cover yet" and not a poll: it fires only when a cover is genuinely
    /// missing, at most `readLimit` times per track.
    private func armRead() {
        guard readAttempts < Self.readLimit else { return }
        readAttempts += 1
        pendingRead?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.host?.coverReadTrack != nil else { return }
            self.pendingRead = nil
            self.readFromOwningPlayer()
        }
        pendingRead = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readDelay, execute: work)
    }

    /// Pulls cover art from a player.
    ///
    /// Music returns the bytes directly; Spotify only exposes a URL, so that
    /// one is fetched. Both run off the main thread — an Apple Event to a busy
    /// player can take a while to come back.
    ///
    /// `bundleID` is the player to ask, and it is not always the configured
    /// provider: see `readFromOwningPlayer`.
    private func readCover(fromPlayer bundleID: String) {
        let isSpotify = bundleID == MusicProvider.spotify.bundleID
        let appName = isSpotify ? "Spotify" : "Music"
        let expected = host?.coverReadTrack

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var image: NSImage?
            var data: Data?

            if isSpotify {
                let script = NSAppleScript(
                    source: "tell application \"\(appName)\" to return artwork url of current track"
                )
                var error: NSDictionary?
                if let raw = script?.executeAndReturnError(&error).stringValue,
                   let url = URL(string: raw),
                   let fetched = try? Data(contentsOf: url) {
                    data = fetched
                    image = NSImage(data: fetched)
                }
            } else {
                let script = NSAppleScript(
                    source: "tell application \"\(appName)\" to "
                        + "return (get raw data of artwork 1 of current track)"
                )
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error),
                   let raw = descriptor.data as Data?,
                   !raw.isEmpty {
                    data = raw
                    image = NSImage(data: raw)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.host?.coverReadTrack == expected else { return }
                guard let data, let image else {
                    // Nothing came back — the player was busy, still loading the
                    // album, or refused the read. That is not a track without a
                    // cover, and it must not be treated as one: this used to
                    // fall through to `set(nil, nil)`, which blanked the cover
                    // the media surfaces were showing and then never asked again
                    // for the rest of the song. The read is retried instead, and
                    // whatever is on screen stays until a better cover replaces
                    // it.
                    self.armRead()
                    return
                }
                self.set(image, data: data)
            }
        }
    }
}
