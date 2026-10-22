// Command-line checks for `PlaybackPush` and `SourceArbitration` — the parser
// behind the closed notch's real-time updates, and the rules deciding which
// report owns the screen.
//
// Both players post the same report in their own words, and only the words are
// testable without a GUI: Music's `Player State` / `Total Time` / TIFF
// `Artwork`, against Spotify's `PlaybackState` / millisecond `Duration` /
// `ArtworkURL`. Neither app has to be installed or running for these.
//
// The last group covers `MediaKeyTapPolicy` — what to do about the event tap
// that replaces the system volume and brightness HUD — for the same reason: a
// real tap cannot be disabled on demand here, and the decision about a disabled
// one is the whole of that logic.
//
// The arbitration rules are pure for the same reason: a paused Spotify and a
// playing YouTube tab cannot both be arranged on a machine without the app, so
// the decision is checked here instead of only in a live notch.
//
// Run from the workspace root — see README.md beside this file.

import Foundation

var failures = 0
var checks = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    checks += 1
    if condition {
        print("ok   \(name)")
    } else {
        failures += 1
        print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }
}

/// Music.app's `com.apple.iTunes.playerInfo`.
let music: [AnyHashable: Any] = [
    "Name": "Island in the Sun",
    "Artist": "Weezer",
    "Album": "Weezer (Green Album)",
    "Total Time": 214.5,
    "Player State": "Playing",
    "Playback Position": 12.5,
    "Artwork": Data([0x01, 0x02, 0x03]),
]

/// Spotify's `com.spotify.client.PlaybackStateChanged` — note the different
/// key, the millisecond duration and the artwork URL.
let spotify: [AnyHashable: Any] = [
    "Name": "Starboy",
    "Artist": "The Weeknd",
    "Album": "Starboy",
    "Duration": 230_000.0,
    "PlaybackState": "Paused",
    "Playback Position": 41.25,
    "ArtworkURL": "https://i.scdn.co/image/abc123",
]

// MARK: - Music

let musicPush = PlaybackPush.parse(
    userInfo: music, bundleID: "com.apple.Music", playing: true
)
check("music: title", musicPush.metadata?.title == "Island in the Sun")
check("music: artist", musicPush.metadata?.artist == "Weezer")
check("music: album", musicPush.metadata?.album == "Weezer (Green Album)")
check(
    "music: seconds stay seconds",
    musicPush.metadata?.duration == 214.5,
    "got \(musicPush.metadata?.duration ?? -1)"
)
check("music: artwork data", musicPush.artwork?.count == 3)
check("music: no artwork URL", musicPush.artworkURL == nil)
check("music: play state travels", musicPush.playing == true)
check(
    "music: position",
    PlaybackPush.position(from: music) == 12.5
)

// MARK: - Spotify

let spotifyPush = PlaybackPush.parse(
    userInfo: spotify, bundleID: "com.spotify.client", playing: false
)
check("spotify: title", spotifyPush.metadata?.title == "Starboy")
check("spotify: artist", spotifyPush.metadata?.artist == "The Weeknd")
check(
    "spotify: milliseconds become seconds",
    spotifyPush.metadata?.duration == 230,
    "got \(spotifyPush.metadata?.duration ?? -1)"
)
check(
    "spotify: artwork URL",
    spotifyPush.artworkURL?.absoluteString == "https://i.scdn.co/image/abc123"
)
check("spotify: no artwork data", spotifyPush.artwork == nil)
check("spotify: play state travels", spotifyPush.playing == false)
check(
    "spotify: position",
    PlaybackPush.position(from: spotify) == 41.25
)

// MARK: - The shapes that must not be mistaken for a track

let emptyPush = PlaybackPush.parse(
    userInfo: ["Player State": "Paused"], bundleID: "com.apple.Music",
    playing: false
)
check("no name means no track", emptyPush.metadata == nil)
check("no name still carries play state", emptyPush.playing == false)

// A player that renames a key's spacing or case is still read: this is what
// keeps one code path serving both apps instead of a key table that rots.
let respelled: [AnyHashable: Any] = [
    "name": "Track",
    " artist ": "Someone",
    "PLAYBACK_STATE": "Playing",
    "total_time": 180.0,
]
let respelledPush = PlaybackPush.parse(
    userInfo: respelled, bundleID: "com.spotify.client", playing: true
)
check("respelled: title", respelledPush.metadata?.title == "Track")
check("respelled: artist", respelledPush.metadata?.artist == "Someone")
check("respelled: duration", respelledPush.metadata?.duration == 180)
check(
    "respelled: state is readable by the caller's lookup",
    (PlaybackPush.value(respelled, ["Player State", "PlaybackState"]) as? String)
        == "Playing"
)

// A payload with no metadata must not blank a report's artwork with a
// zero-length one, and a duration of zero stays zero rather than a fraction.
check(
    "zero duration stays zero",
    PlaybackPush.seconds(0) == nil
)
check(
    "artwork count is not an artwork image",
    PlaybackPush.value(["Artwork Count": 1], ["Artwork", "ArtworkData"]) == nil
)

// MARK: - Who owns the screen

// A player that is *playing* keeps the notch even against a video: the
// provider is what the notch controls, so a running song must not lose to a
// tab.
check(
    "a playing player outranks the browser",
    SourceArbitration.preferredSource(
        hasPlayingPlayer: true, hasBrowserItem: true, hasIdlePlayer: true
    ) == .playingPlayer
)
check(
    "a playing player alone is still the source",
    SourceArbitration.preferredSource(
        hasPlayingPlayer: true, hasBrowserItem: false, hasIdlePlayer: false
    ) == .playingPlayer
)
// The request itself: with music not playing, the browser item is what the
// notch shows. The player's state script still answers with its track while it
// is paused, so it is the play state — not the reply — that decides.
check(
    "with music not playing the browser item wins",
    SourceArbitration.preferredSource(
        hasPlayingPlayer: false, hasBrowserItem: true, hasIdlePlayer: true
    ) == .browser
)
// No player track to fall back on: the browser item is the only thing there is,
// including the legacy reading that cannot report whether it is playing.
check(
    "the browser is the source when no player has a track",
    SourceArbitration.preferredSource(
        hasPlayingPlayer: false, hasBrowserItem: true, hasIdlePlayer: false
    ) == .browser
)
// With the browser silent, the track the paused player still holds stays on the
// notch rather than it going blank.
check(
    "a paused player keeps its track when no browser has an item",
    SourceArbitration.preferredSource(
        hasPlayingPlayer: false, hasBrowserItem: false, hasIdlePlayer: true
    ) == .idlePlayer
)
check(
    "nothing anywhere means nothing shows",
    SourceArbitration.preferredSource(
        hasPlayingPlayer: false, hasBrowserItem: false, hasIdlePlayer: false
    ) == .none
)

// The app that owns the item on screen may assert its own pause.
check(
    "the shown source may move the play state",
    SourceArbitration.pushMayMovePlaybackState(
        sourceOnScreen: "com.spotify.client",
        pushBundleID: "com.spotify.client",
        pushIsPlaying: false
    )
)
// Another player's pause says nothing about the video on screen.
check(
    "a background player's pause is ignored",
    !SourceArbitration.pushMayMovePlaybackState(
        sourceOnScreen: "com.google.Chrome",
        pushBundleID: "com.spotify.client",
        pushIsPlaying: false
    )
)
// …but its *resume* is a source change in progress and must land.
check(
    "a resume from another player is let through",
    SourceArbitration.pushMayMovePlaybackState(
        sourceOnScreen: "com.google.Chrome",
        pushBundleID: "com.spotify.client",
        pushIsPlaying: true
    )
)
// Nothing resolved yet: a push is the best description of the screen there is.
check(
    "with no resolved source a push speaks for the screen",
    SourceArbitration.pushMayMovePlaybackState(
        sourceOnScreen: nil,
        pushBundleID: "com.apple.Music",
        pushIsPlaying: false
    )
)

// MARK: - Which reading may take the notch
//
// The browser probe re-reads the browser every couple of seconds, and it used
// to apply whatever it found. With a paused YouTube tab open beside the video
// actually playing, the reading that came back was the tab the scan reached
// first — so the playing video held the notch for a few seconds and then lost
// it to a tab that was not making a sound.

// A reading that is playing is the item making sound, whatever else is open.
check(
    "a playing reading takes the notch from a paused one",
    SourceArbitration.probeMayReplace(
        showingIsPlaying: false, probeIsPlaying: true, sameItem: false
    )
)
// Two things making sound is a source change in progress; the newer reading
// owns the notch, exactly as a resuming player does elsewhere in these rules.
check(
    "a playing reading takes the notch from another playing one",
    SourceArbitration.probeMayReplace(
        showingIsPlaying: true, probeIsPlaying: true, sameItem: false
    )
)
// The same item reporting its own pause is a state change, not a takeover.
check(
    "the same item may report its own pause",
    SourceArbitration.probeMayReplace(
        showingIsPlaying: true, probeIsPlaying: false, sameItem: true
    )
)
// The reported failure: the paused tab must not displace the playing video.
check(
    "a paused reading may not displace a playing one",
    !SourceArbitration.probeMayReplace(
        showingIsPlaying: true, probeIsPlaying: false, sameItem: false
    )
)
// Nothing is playing: a paused reading is the best description there is.
check(
    "a paused reading may take an idle notch",
    SourceArbitration.probeMayReplace(
        showingIsPlaying: false, probeIsPlaying: false, sameItem: false
    )
)
// …and may replace one paused item with another, which is how a browser
// following a tab the user moved to still updates.
check(
    "a paused reading replaces another paused item",
    SourceArbitration.probeMayReplace(
        showingIsPlaying: false, probeIsPlaying: false, sameItem: true
    )
)

// MARK: - Making two readings of one item comparable
//
// The browser reports a page's own title and the system's now-playing channel
// reports the same item with the platform's suffix still on it. The notch has
// to see those as one item, or a pause in one channel looks like a source
// change to the other.
check(
    "a YouTube suffix is stripped",
    SourceArbitration.normalizedTitle("Island in the Sun - YouTube") == "Island in the Sun"
)
check(
    "the longer YouTube Music suffix is stripped whole",
    SourceArbitration.normalizedTitle("Island in the Sun - YouTube Music") == "Island in the Sun"
)
check(
    "a title with no suffix is left alone",
    SourceArbitration.normalizedTitle("Island in the Sun") == "Island in the Sun"
)

// MARK: - The media-key tap's health check
//
// The tap behind the notch's own volume and brightness HUD cannot be built,
// disabled or invalidated on demand, so what is checked is the decision about a
// tap in each of those states. That decision is the whole of the recovery
// logic, and its absence is what let a tap the system had switched off stay off
// for the rest of a session — with the system's own HUD back on screen and
// nothing anywhere saying why.

let settle: TimeInterval = 3

func tapAction(
    wanted: Bool = true,
    trusted: Bool = true,
    hasTap: Bool = true,
    enabled: Bool,
    age: TimeInterval = 600,
    rearmAttempted: Bool = false
) -> MediaKeyTapAction {
    MediaKeyTapPolicy.action(
        wanted: wanted,
        trusted: trusted,
        hasTap: hasTap,
        enabled: enabled,
        ageSinceArmed: age,
        settleTime: settle,
        rearmAttempted: rearmAttempted
    )
}

check("an enabled tap is left alone", tapAction(enabled: true) == .healthy)
check("with no tap at all one is installed", tapAction(hasTap: false, enabled: false) == .install)
// A tap that was armed a moment ago is not necessarily enabled yet: the run loop
// serving it has not started, and rebuilding here would tear down a good tap.
check("a tap that has only just been armed is given a moment", tapAction(enabled: false, age: 1) == .none)
// The reported failure: healthy for hours, then switched off by the system.
check(
    "a tap the system disabled mid-session is re-armed",
    tapAction(enabled: false, age: 600) == .rearm
)
// `tapEnable` on an invalidated port reports success and changes nothing, so a
// second disappointed check has to replace the port rather than ask again.
check(
    "a tap that ignored its re-arm is rebuilt",
    tapAction(enabled: false, age: 600, rearmAttempted: true) == .rebuild
)
check(
    "switching HUD replacement off takes the tap down",
    tapAction(wanted: false, enabled: true) == .teardown
)
// Accessibility can be revoked in System Settings while the app runs.
check(
    "a revoked permission takes the tap down rather than leaving it half-alive",
    tapAction(trusted: false, enabled: true) == .teardown
)
// The permission arriving late is the launch-time case: a tap refused at launch
// has to be installed on the next check, without a relaunch.
check(
    "a permission that arrives later installs the tap",
    tapAction(hasTap: false, enabled: false) == .install
)

print("")
print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
