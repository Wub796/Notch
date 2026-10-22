import Foundation

/// Which of the notch's readings it should follow, when more than one app has
/// something to say.
///
/// The media surfaces show a single item, and more than one report source can
/// be live at once: a music player that is merely open (paused, or holding the
/// track it last played) alongside a browser playing a YouTube video. Every
/// rule about who wins lives here, so the closed pill, the open panel and the
/// Audio screen cannot drift apart, and so the answer can be checked from the
/// command line — `tests/media` — instead of only by watching a real notch.
///
/// Nothing here touches AppKit: the caller says what it saw and the rule is the
/// same on a Mac where neither player is installed, which is where the checks
/// run.
enum SourceArbitration {
    /// Which of the readings the notch should follow.
    enum Source: Equatable {
        /// A music player that is actually playing.
        case playingPlayer
        /// A browser item: a YouTube video, a web player.
        case browser
        /// The track a music player still holds while it is not playing.
        case idlePlayer
        /// Nothing is playing and no player has a track.
        case none
    }

    /// The order every media surface follows: the player that is *playing*,
    /// then the browser's item, then the track a paused player still holds.
    ///
    /// A player that is not playing does not own the screen. Its state script
    /// answers with its current track while it is paused, and treating that
    /// reply as ownership of the notch is what left the closed pill and the
    /// open panel showing the paused song — transport aimed at the player —
    /// while YouTube played in a browser. This is the whole of "if music isn't
    /// playing, show the YouTube item": the trigger is the play state, not
    /// whether the player still has a track.
    ///
    /// A player that *is* playing keeps the notch even against a video, because
    /// the provider is what the notch controls: a running song must not lose to
    /// a tab. And with the browser silent, a paused player's last track stays on
    /// screen rather than the notch going blank.
    static func preferredSource(
        hasPlayingPlayer: Bool, hasBrowserItem: Bool, hasIdlePlayer: Bool
    ) -> Source {
        if hasPlayingPlayer { return .playingPlayer }
        if hasBrowserItem { return .browser }
        if hasIdlePlayer { return .idlePlayer }
        return .none
    }

    /// Whether a player's push may move the playback state of what is on
    /// screen.
    ///
    /// Only the app that owns the item on screen may assert that it paused:
    /// Spotify's pause report is posted whether or not Spotify is the thing
    /// making sound, and adopting it stopped the closed notch's visualiser and
    /// flipped its play button while a YouTube video was the item on the pill.
    /// A report that says it is *playing* is allowed through from any player,
    /// because that one is a source change in progress — the player which just
    /// resumed is taking the notch back, and blocking it left it unable to.
    static func pushMayMovePlaybackState(
        sourceOnScreen: String?, pushBundleID: String, pushIsPlaying: Bool
    ) -> Bool {
        guard let sourceOnScreen else { return true }
        if sourceOnScreen == pushBundleID { return true }
        return pushIsPlaying
    }

    /// Whether a fresh browser-probe reading may take the notch from the item
    /// currently showing.
    ///
    /// The probe re-reads the browser every couple of seconds and needs to be
    /// able to replace what is on screen when something else starts playing.
    /// It also used to apply whatever it found, unconditionally — and when two
    /// pages have media (a YouTube tab the browser still holds and a Bilibili
    /// video actually running), the reading that came back was whichever page
    /// the scan reached first, usually the paused one. The playing video then
    /// stayed on the notch for a few seconds and vanished, which read as the
    /// notch refusing to follow the video that was making sound.
    ///
    /// Three questions, and the answer is yes on any of them:
    /// - the reading is *playing*: it is the item making sound, whatever else
    ///   is open, so it takes the notch;
    /// - it is the same item that is already showing, so this is its own state
    ///   moving (a pause, a seek, a new position) rather than a takeover;
    /// - nothing is playing, so a paused reading is the best there is.
    ///
    /// A reading that is paused, about a different item, while something else
    /// plays may not replace it.
    static func probeMayReplace(
        showingIsPlaying: Bool, probeIsPlaying: Bool, sameItem: Bool
    ) -> Bool {
        if probeIsPlaying { return true }
        if sameItem { return true }
        return !showingIsPlaying
    }

    /// A now-playing title with the platform suffixes stripped, so readings of
    /// the same item from two sources compare equal ("Song - YouTube" and
    /// "Song" are the same video).
    static func normalizedTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" - YouTube", " - YouTube Music"] where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }
}
