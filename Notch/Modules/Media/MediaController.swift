import AppKit
import Observation
import SwiftUI

/// System-wide now-playing state. Primary source is MediaRemote (push-based
/// notifications, zero polling while collapsed); when that is unavailable it
/// falls back to querying Music.app over Apple Events — but only while the
/// notch is expanded.
@Observable
final class MediaController {
    struct Track: Equatable {
        var title = ""
        var artist = ""
        var album = ""
        var duration: TimeInterval = 0
    }

    private(set) var track: Track?
    private(set) var artwork: NSImage?

    /// Normalized metadata consumed by clients that need one source-independent
    /// media value. The legacy properties below remain the UI's source of truth.
    var normalizedTrack: NotchMediaTrack? {
        guard let track else { return nil }
        return NotchMediaTrack(
            title: track.title,
            artist: track.artist,
            album: track.album,
            artwork: artwork,
            duration: track.duration,
            currentPosition: currentElapsed,
            isPlaying: isPlaying,
            mediaSource: normalizedSource
        )
    }

    private var normalizedSource: NotchMediaSource {
        switch sourceAppBundleID {
        case MusicProvider.spotify.bundleID:
            return .spotify
        case "com.apple.Music":
            return .appleMusic
        default:
            return .genericSystem
        }
    }
    private(set) var isPlaying = false {
        didSet {
            guard isPlaying != oldValue else { return }
            onPlaybackStateChange?(isPlaying)
        }
    }

    /// Fired when playback starts or stops, so things that cost something to
    /// run — the real-time output meter — only run while there is audio.
    var onPlaybackStateChange: ((Bool) -> Void)?

    /// Legible accent derived from the current artwork; tints the scrubber,
    /// play button, lyrics highlight, and the collapsed equalizer.
    private(set) var accent: Color = .white
    private var accentSourceHash: Int?

    /// Elapsed seconds at `anchorDate`; the live position is extrapolated so
    /// no timer is needed to keep it accurate.
    private var elapsedAnchor: TimeInterval = 0
    private var anchorDate = Date()

    /// UI-facing playback position, refreshed by a lightweight timer that only
    /// runs while the notch is expanded.
    private(set) var displayedElapsed: TimeInterval = 0

    let lyrics = LyricsEngine()

    /// Emits the same normalized value used by the UI whenever metadata or
    /// playback position changes. Position ticks are local and never perform
    /// IPC or disk work.
    var onNormalizedTrackChange: ((NotchMediaTrack?) -> Void)?

    /// Queue and artist detail from Spotify, when it is connected. Empty
    /// otherwise — nothing else on macOS exposes a playback queue.
    private(set) var queue: [SpotifyClient.QueueItem] = []
    private(set) var followersLabel: String?

    /// The next track, for the player's Up Next card.
    var upNext: SpotifyClient.QueueItem? { queue.first }

    private var lastSpotifyLookup: String?

    /// Fired when a genuinely new track replaces a previous one — drives the
    /// collapsed-notch sneak peek.
    var onTrackChange: ((Track) -> Void)?

    /// Current synced lyric line surfaced in the collapsed notch while
    /// playing (Sapphire-style lyric live activity).
    private(set) var collapsedLyricLine: String?

    /// The app the audio is coming from (Spotify, Music, Safari…).
    private(set) var sourceAppName: String?
    private(set) var sourceAppIcon: NSImage?
    private var sourceAppPID: Int32 = 0
    private(set) var sourceAppBundleID: String?

    /// True while the current metadata came from a YouTube/web-video probe.
    /// This is deliberately exposed so every media surface uses the same
    /// source-priority rule instead of independently guessing from app names.
    private(set) var isBrowserVideo = false

    /// The adapter's mediaType for the current source ("...TypeMusic" vs
    /// "...TypeAudio"), so callers can tell music from generic audio. Only
    /// set on the perl-bridge path.
    private(set) var sourceMediaType: String?

    var selectedProvider: MusicProvider {
        NotchSettings.shared.musicProvider
    }

    /// True when the current now-playing source is allowed by the selected
    /// provider (always true for Automatic).
    private func providerAllowsCurrentSource() -> Bool {
        switch selectedProvider {
        case .automatic:
            return true
        case .appleMusic, .spotify:
            guard let sourceAppBundleID else { return true }
            return sourceAppBundleID == selectedProvider.bundleID
        }
    }

    /// True once MediaRemote has been found to answer every query with
    /// nothing. macOS 15.4 gated the now-playing entry points for apps
    /// without an entitlement Apple no longer issues; the symbols still
    /// resolve and the calls still succeed, they just return empty (the
    /// console logs "Operation not permitted"), so the only way to detect it
    /// is to ask and notice the silence.
    private(set) var isSystemNowPlayingRestricted = false

    /// Consecutive empty MediaRemote replies received while a player the
    /// Apple Events fallback can read was running.
    private var consecutiveEmptyReplies = 0
    private static let emptyRepliesBeforeDemotion = 3

    private let bridge = MediaRemoteBridge.shared
    /// The bundled perl-bridge adapter (see MediaRemoteAdapter) when present
    /// and verified — it replaces the dlopen bridge as the MediaRemote source
    /// because it keeps working on macOS 15.4+, where direct calls are gated
    /// and answer with silence.
    private let adapter = MediaRemoteAdapter()
    private var useAdapter = false
    private var adapterRestartAttempts = 0
    private var useMediaRemote: Bool
    private var mediaRemoteRetryWork: DispatchWorkItem?
    private var progressTimer: Timer?
    private var fallbackTimer: Timer?
    private var lyricActivityTimer: Timer?
    private var pendingClearWork: DispatchWorkItem?
    private var browserProbeTimer: Timer?
    private var isActive = false
    private var mediaNotificationObservers: [NSObjectProtocol] = []

    /// True while the shown track came from the browser fallback. MediaRemote
    /// can't see browsers on gated macOS, so an empty reply while this is set
    /// must not blank the track — the browser probe owns keeping it honest.
    private var isShowingBrowserSnapshot = false

    var hasTrack: Bool {
        track != nil
    }

    /// Transport controls are always enabled to send universal playback commands.
    var canControlTransport: Bool {
        true
    }

    /// Live position, extrapolated from the last anchor.
    ///
    /// Clamped to the track's length. Without the clamp the extrapolation runs
    /// straight past the end — MediaRemote's timestamp is when the info was
    /// captured, not when it was read, so between updates the position can
    /// overshoot by a long way. That is what made the remaining time read
    /// 0:00 well before the track ended and the scrubber sit pinned at full.
    var currentElapsed: TimeInterval {
        guard let track else { return 0 }
        let raw = isPlaying
            ? elapsedAnchor + Date().timeIntervalSince(anchorDate)
            : elapsedAnchor
        guard track.duration > 0 else { return max(raw, 0) }
        return min(max(raw, 0), track.duration)
    }

    init() {
        useMediaRemote = false
        if MediaRemoteAdapter.isBundled {
            // Adapter first: verify off the main thread, then either take the
            // adapter as the MediaRemote source or fall back to the dlopen
            // bridge. Waiting for the verdict keeps the two sources from
            // racing each other at launch.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let functional = MediaRemoteAdapter.verifyFunctional()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if functional {
                        self.armAdapter()
                    } else {
                        self.armDirectBridge()
                    }
                }
            }
        } else {
            armDirectBridge()
        }

        // Read whatever is playing straight away, off the main thread so a
        // slow-to-answer player cannot hold up launch. Without this the notch
        // showed nothing until it was first opened: MediaRemote is push-based
        // and sends nothing until something changes, and where it is gated the
        // Apple Events path only ran while the notch was expanded.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.probePlayersAtLaunch(attemptsLeft: 4)
        }
    }

    /// The dlopen MediaRemoteBridge as the source. Used when the perl-bridge
    /// adapter is not bundled or fails its entitlement test.
    private func armDirectBridge() {
        useAdapter = false
        guard bridge.isAvailable && bridge.supportsQueries else { return }
        useMediaRemote = true
        bridge.registerForNotifications()
        let center = NotificationCenter.default
        mediaNotificationObservers = [
            center.addObserver(
                forName: MediaRemoteBridge.infoDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refreshFromMediaRemote()
            },
            center.addObserver(
                forName: MediaRemoteBridge.isPlayingDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refreshFromMediaRemote()
            },
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.iTunes.playerInfo"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshFromMediaRemote()
            },
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshFromMediaRemote()
            }
        ]
        refreshFromMediaRemote()
    }

    /// The perl-bridge adapter as the source: verified functional, so its
    /// stream owns now-playing delivery and the dlopen bridge stays dormant.
    private func armAdapter() {
        useAdapter = true
        useMediaRemote = true
        isSystemNowPlayingRestricted = false
        adapterRestartAttempts = 0
        adapter.onInfo = { [weak self] info in
            self?.applyAdapterInfo(info)
        }
        adapter.onTerminated = { [weak self] in
            self?.handleAdapterTerminated()
        }
        adapter.startStream()
    }

    /// Launch-time probe, with retries, so a track that was already playing
    /// before the notch launched shows up the moment the app opens rather
    /// than after the first track change.
    ///
    /// One attempt misses too easily: a player can be slow to answer its
    /// first Apple Event, and the Automation consent prompt may still be in
    /// the air (a probe must never be what raises it, so an ungranted bundle
    /// is retried rather than abandoned — the retry picks up the grant). The
    /// probe also checks both known players, not only the fallback, so a
    /// Spotify track on a Mac where MediaRemote is gated is caught too.
    /// Retries stop as soon as any source has produced a track.
    private func probePlayersAtLaunch(attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }

        // Both players the Apple Events path can read, each with its own app
        // name. Only one will be running at a time on a real Mac, but checking
        // both costs a single process-lookup each and covers the case where
        // the user is playing the provider that isn't the fallback.
        let candidates: [(appName: String, bundleID: String)] = [
            ("Music", "com.apple.Music"),
            ("Spotify", MusicProvider.spotify.bundleID)
        ]

        for candidate in candidates {
            guard NSRunningApplication
                .runningApplications(withBundleIdentifier: candidate.bundleID)
                .isEmpty == false
            else { continue }
            // Only when consent is already on file: a probe at launch must
            // not be what raises the Automation dialog.
            guard IntegrationPermissions.isAutomationAllowed(candidate.bundleID) else {
                continue
            }
            guard let snapshot = snapshotFrom(appName: candidate.appName) else { continue }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.track == nil else { return }
                self.apply(snapshot)
            }
            return
        }

        // No player answered — check the browsers for web media (YouTube,
        // etc.). Consent-gated exactly like the players: a launch probe must
        // never be what raises the Automation dialog.
        if let browserSnap = browserYouTubeSnapshot(avoidPrompt: true) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.track == nil else { return }
                self.apply(browserSnap)
            }
            return
        }

        // Nothing playing (or the player is still starting up) — retry while
        // nothing has been picked up yet.
        scheduleLaunchProbeRetry(attemptsLeft: attemptsLeft)
    }

    private func scheduleLaunchProbeRetry(attemptsLeft: Int) {
        guard attemptsLeft > 1 else { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 2
        ) { [weak self] in
            guard let self else { return }
            // Anything already picked up — by MediaRemote or an earlier
            // probe — ends the launch probe.
            guard self.track == nil, !self.isPlaying else { return }
            self.probePlayersAtLaunch(attemptsLeft: attemptsLeft - 1)
        }
    }

    /// Reads the state of a named player, or nil when it has nothing to say.
    /// Like `appleScriptSnapshot` but for an arbitrary app name rather than
    /// only the fallback — used by the launch probe to check both known
    /// players.
    private func snapshotFrom(appName: String) -> Snapshot? {
        guard let script = NSAppleScript(source: stateScript(for: appName)) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let raw = result.stringValue, raw != "stopped" else { return nil }

        let parts = raw.components(separatedBy: "||")
        guard parts.count >= 6 else { return nil }

        var newTrack = Track()
        newTrack.title = parts[0]
        newTrack.artist = parts[1]
        newTrack.album = parts[2]
        newTrack.duration = Self.seconds(fromAppleScript: parts[3])

        return Snapshot(
            track: newTrack,
            elapsed: TimeInterval(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0,
            isPlaying: parts[5] == "playing"
        )
    }

    // MARK: - Lifecycle

    /// Called when the notch expands/collapses. All timers live inside this
    /// window so the collapsed notch burns zero background CPU.
    func setActive(_ active: Bool) {
        isActive = active
        mediaRemoteRetryWork?.cancel()
        mediaRemoteRetryWork = nil
        progressTimer?.invalidate()
        progressTimer = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        browserProbeTimer?.invalidate()
        browserProbeTimer = nil
        defer { updateLyricActivityTimer() }

        guard active else {
            // Closed, the wings and the lyric line still need to know when the
            // song changes. MediaRemote pushes that on its own; the Apple
            // Events path has to ask, so it keeps a slow poll rather than
            // going dark until the notch is opened again.
            if !useMediaRemote, wantsCollapsedMediaUpdates {
                fallbackTimer = Timer.scheduledTimer(
                    withTimeInterval: 4.0, repeats: true
                ) { [weak self] _ in
                    self?.refreshFromAppleScript()
                }
            }
            return
        }

        if useMediaRemote {
            refreshFromMediaRemote()
            // Browser metadata is independent of MediaRemote and must also be
            // refreshed whenever the Audio/media surface becomes visible.
            probeBrowserForPlayingMedia(avoidPrompt: false)
            // While the notch is open and MediaRemote is the source, a
            // browser-derived track needs a probe of its own to stay honest:
            // MediaRemote never answers for browsers, so nothing else would
            // tell us when the tab closes or the video changes.
            browserProbeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.tickBrowserProbe()
            }
            tickBrowserProbe()
            // On Macs where MediaRemote is gated, its answers are silence and
            // the demotion counter only advances one refresh per open — music
            // that was already playing took several open/close rounds to appear.
            // One AppleScript probe per open closes that gap: if the fallback
            // player answers with something playing while MediaRemote says
            // nothing, demote on the spot and show the track.
            probeFallbackIfMediaRemoteSilent()
        } else {
            refreshFromAppleScript()
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.refreshFromAppleScript()
            }
        }

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tickProgress()
        }
        tickProgress()
    }

    /// Whether the closed notch is showing anything that depends on the
    /// current track. Nothing is polled for a notch that shows neither.
    private var wantsCollapsedMediaUpdates: Bool {
        let settings = NotchSettings.shared
        guard settings.showMediaWings || settings.lyricActivityEnabled else { return false }
        return automationIsAllowed()
    }

    /// TCC lookups are cheap but not free, and this is asked on every open and
    /// close, so the answer is held for half a minute.
    private func automationIsAllowed() -> Bool {
        let bundleID = fallbackBundleID
        if let cached = automationAllowedCache,
           cached.bundleID == bundleID,
           Date().timeIntervalSince(cached.checked) < 30 {
            return cached.allowed
        }
        let allowed = IntegrationPermissions.isAutomationAllowed(bundleID)
        automationAllowedCache = (bundleID, allowed, Date())
        return allowed
    }

    private var automationAllowedCache: (bundleID: String, allowed: Bool, checked: Date)?

    /// The collapsed lyric activity needs its own tick — it runs only while
    /// a track is actually playing with the setting enabled and the notch
    /// closed, so the idle notch still costs nothing.
    func updateLyricActivityTimer() {
        let wanted = NotchSettings.shared.lyricActivityEnabled
            && isPlaying
            && hasTrack
            && !isBrowserVideo
            && !isActive

        if wanted {
            guard lyricActivityTimer == nil else { return }
            lyricActivityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.tickCollapsedLyric()
            }
            tickCollapsedLyric()
        } else {
            lyricActivityTimer?.invalidate()
            lyricActivityTimer = nil
            if collapsedLyricLine != nil {
                collapsedLyricLine = nil
            }
        }
    }

    private func tickCollapsedLyric() {
        guard isPlaying, !isBrowserVideo, lyrics.isSynced, !lyrics.lines.isEmpty else {
            if collapsedLyricLine != nil {
                collapsedLyricLine = nil
            }
            return
        }
        lyrics.updateCurrentLine(for: currentElapsed)
        let line = lyrics.currentIndex.map { lyrics.lines[$0].text }
        if line != collapsedLyricLine {
            collapsedLyricLine = line
        }
    }

    private func tickProgress() {
        displayedElapsed = currentElapsed
        onNormalizedTrackChange?(normalizedTrack)
        guard isPlaying, !isBrowserVideo else { return }
        lyrics.updateCurrentLine(for: displayedElapsed)
    }

    // MARK: - Transport controls

    func togglePlayPause() {
        let newState = !isPlaying
        isPlaying = newState
        if newState {
            anchorDate = Date()
        } else {
            elapsedAnchor = currentElapsed
            anchorDate = Date()
        }
        displayedElapsed = currentElapsed
        // Stop the collapsed lyric timer immediately on an optimistic pause;
        // the player callback remains authoritative for resuming. Without
        // this, a delayed MediaRemote update leaves lyrics advancing while the
        // actual player is paused.
        updateLyricActivityTimer()

        // 1. Browser media (YouTube, web videos)
        if isBrowserVideo || isShowingBrowserSnapshot {
            toggleBrowserPlayback()
            return
        }

        // 2. Specific Selected Provider
        if let provider = selectedProvider.appleScriptAppName {
            if selectedProvider == .spotify,
               SpotifyAuth.shared.state == .signedIn,
               NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
                Task {
                    if let token = await SpotifyAuth.shared.validAccessToken() {
                        if newState {
                            await SpotifyClient.resume(token: token)
                        } else {
                            await SpotifyClient.pause(token: token)
                        }
                    }
                }
                return
            }
            runProviderCommand(appName: provider, command: newState ? "play" : "pause")
            return
        }

        // 3. Automatic provider detection
        if let bundle = sourceAppBundleID {
            if bundle == MusicProvider.spotify.bundleID {
                runProviderCommand(appName: "Spotify", command: newState ? "play" : "pause")
                return
            } else if bundle == MusicProvider.appleMusic.bundleID {
                runProviderCommand(appName: "Music", command: newState ? "play" : "pause")
                return
            } else if Self.browserTargets.contains(where: { $0.bundleID == bundle }) {
                toggleBrowserPlayback()
                return
            }
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
            runProviderCommand(appName: "Spotify", command: newState ? "play" : "pause")
            return
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.appleMusic.bundleID).isEmpty {
            runProviderCommand(appName: "Music", command: newState ? "play" : "pause")
            return
        }

        if SpotifyAuth.shared.state == .signedIn {
            Task {
                if let token = await SpotifyAuth.shared.validAccessToken() {
                    if newState {
                        await SpotifyClient.resume(token: token)
                    } else {
                        await SpotifyClient.pause(token: token)
                    }
                }
            }
            return
        }

        if useAdapter {
            adapter.sendCommand(.togglePlayPause)
        } else if useMediaRemote {
            bridge.send(.togglePlayPause)
        } else {
            SystemMediaKeySender.togglePlayPause()
        }
    }

    func nextTrack() {
        if isBrowserVideo || isShowingBrowserSnapshot {
            nextBrowserTrack()
            return
        }

        if let provider = selectedProvider.appleScriptAppName {
            if selectedProvider == .spotify,
               SpotifyAuth.shared.state == .signedIn,
               NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
                Task {
                    if let token = await SpotifyAuth.shared.validAccessToken() {
                        await SpotifyClient.next(token: token)
                    }
                }
                return
            }
            runProviderCommand(appName: provider, command: "next track")
            return
        }

        if let bundle = sourceAppBundleID {
            if bundle == MusicProvider.spotify.bundleID {
                runProviderCommand(appName: "Spotify", command: "next track")
                return
            } else if bundle == MusicProvider.appleMusic.bundleID {
                runProviderCommand(appName: "Music", command: "next track")
                return
            } else if Self.browserTargets.contains(where: { $0.bundleID == bundle }) {
                nextBrowserTrack()
                return
            }
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
            runProviderCommand(appName: "Spotify", command: "next track")
            return
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.appleMusic.bundleID).isEmpty {
            runProviderCommand(appName: "Music", command: "next track")
            return
        }

        if SpotifyAuth.shared.state == .signedIn {
            Task {
                if let token = await SpotifyAuth.shared.validAccessToken() {
                    await SpotifyClient.next(token: token)
                }
            }
            return
        }

        if useAdapter {
            adapter.sendCommand(.nextTrack)
        } else if useMediaRemote {
            bridge.send(.nextTrack)
        } else {
            SystemMediaKeySender.nextTrack()
        }
    }

    func previousTrack() {
        if isBrowserVideo || isShowingBrowserSnapshot {
            previousBrowserTrack()
            return
        }

        if let provider = selectedProvider.appleScriptAppName {
            if selectedProvider == .spotify,
               SpotifyAuth.shared.state == .signedIn,
               NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
                Task {
                    if let token = await SpotifyAuth.shared.validAccessToken() {
                        await SpotifyClient.previous(token: token)
                    }
                }
                return
            }
            runProviderCommand(appName: provider, command: "previous track")
            return
        }

        if let bundle = sourceAppBundleID {
            if bundle == MusicProvider.spotify.bundleID {
                runProviderCommand(appName: "Spotify", command: "previous track")
                return
            } else if bundle == MusicProvider.appleMusic.bundleID {
                runProviderCommand(appName: "Music", command: "previous track")
                return
            } else if Self.browserTargets.contains(where: { $0.bundleID == bundle }) {
                previousBrowserTrack()
                return
            }
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
            runProviderCommand(appName: "Spotify", command: "previous track")
            return
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.appleMusic.bundleID).isEmpty {
            runProviderCommand(appName: "Music", command: "previous track")
            return
        }

        if SpotifyAuth.shared.state == .signedIn {
            Task {
                if let token = await SpotifyAuth.shared.validAccessToken() {
                    await SpotifyClient.previous(token: token)
                }
            }
            return
        }

        if useAdapter {
            adapter.sendCommand(.previousTrack)
        } else if useMediaRemote {
            bridge.send(.previousTrack)
        } else {
            SystemMediaKeySender.previousTrack()
        }
    }

    /// Jumps playback to an absolute position (scrubber drag or lyric tap).
    func seek(to seconds: TimeInterval) {
        let upperBound = (track?.duration ?? 0) > 0 ? track!.duration : seconds
        let clamped = max(0, min(seconds, upperBound))

        elapsedAnchor = clamped
        anchorDate = Date()
        displayedElapsed = clamped
        lyrics.updateCurrentLine(for: clamped)

        if isBrowserVideo || isShowingBrowserSnapshot {
            seekBrowser(to: clamped)
            return
        }

        if let provider = selectedProvider.appleScriptAppName {
            if selectedProvider == .spotify,
               SpotifyAuth.shared.state == .signedIn,
               NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
                Task {
                    if let token = await SpotifyAuth.shared.validAccessToken() {
                        await SpotifyClient.seek(positionMs: Int(clamped * 1000), token: token)
                    }
                }
                return
            }
            runProviderCommand(appName: provider, command: "set player position to \(Int(clamped))")
            return
        }

        if let bundle = sourceAppBundleID {
            if bundle == MusicProvider.spotify.bundleID {
                runProviderCommand(appName: "Spotify", command: "set player position to \(Int(clamped))")
                return
            } else if bundle == MusicProvider.appleMusic.bundleID {
                runProviderCommand(appName: "Music", command: "set player position to \(Int(clamped))")
                return
            }
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
            runProviderCommand(appName: "Spotify", command: "set player position to \(Int(clamped))")
            return
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.appleMusic.bundleID).isEmpty {
            runProviderCommand(appName: "Music", command: "set player position to \(Int(clamped))")
            return
        }

        if SpotifyAuth.shared.state == .signedIn {
            Task {
                if let token = await SpotifyAuth.shared.validAccessToken() {
                    await SpotifyClient.seek(positionMs: Int(clamped * 1000), token: token)
                }
            }
            return
        }

        if useAdapter {
            adapter.seek(to: clamped)
        } else if useMediaRemote, bridge.canSeek {
            bridge.setElapsedTime(clamped)
        } else {
            runMusicCommand("set player position to \(Int(clamped))")
        }
    }

    private func toggleBrowserPlayback() {
        for browser in Self.browserTargets {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { continue }
            let js = "(function(){var p=document.querySelector('#movie_player');if(p&&p.getPlayerState){if(p.getPlayerState()===1){p.pauseVideo();return 'paused';}else{p.playVideo();return 'playing';}}var v=document.querySelector('video');if(v){if(v.paused){v.play();return 'playing';}else{v.pause();return 'paused';}}return 'none';})();"
            let scriptSource: String
            if browser.isChromium {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to title of t
                            if u contains "youtube.com" or u contains "youtu.be" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    tell t
                                        return (execute javascript "\(js)") as text
                                    end tell
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            } else {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to name of t
                            if u contains "youtube.com" or u contains "youtu.be" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    return (do JavaScript "\(js)" in t) as text
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            }

            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                let result = script.executeAndReturnError(&error)
                if error == nil, let res = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                   res == "playing" || res == "paused" {
                    return
                }
            }
        }
        SystemMediaKeySender.togglePlayPause()
    }

    private func nextBrowserTrack() {
        for browser in Self.browserTargets {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { continue }
            let js = "(function(){var nextBtn=document.querySelector('.ytp-next-button')||document.querySelector('button.next-button')||document.querySelector('tp-yt-paper-icon-button.next-button');if(nextBtn){nextBtn.click();return 'clicked';}return 'none';})();"
            let scriptSource: String
            if browser.isChromium {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to title of t
                            if u contains "youtube.com" or u contains "youtu.be" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    tell t
                                        return (execute javascript "\(js)") as text
                                    end tell
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            } else {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to name of t
                            if u contains "youtube.com" or u contains "youtu.be" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    return (do JavaScript "\(js)" in t) as text
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            }

            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                let result = script.executeAndReturnError(&error)
                if error == nil, let res = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), res == "clicked" {
                    return
                }
            }
        }
        SystemMediaKeySender.nextTrack()
    }

    private func previousBrowserTrack() {
        for browser in Self.browserTargets {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { continue }
            let js = "(function(){var prevBtn=document.querySelector('.ytp-prev-button')||document.querySelector('button.previous-button')||document.querySelector('tp-yt-paper-icon-button.previous-button');if(prevBtn){prevBtn.click();return 'clicked';}var v=document.querySelector('video');if(v){v.currentTime=0;return 'reset';}return 'none';})();"
            let scriptSource: String
            if browser.isChromium {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to title of t
                            if u contains "youtube.com" or u contains "youtu.be" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    tell t
                                        return (execute javascript "\(js)") as text
                                    end tell
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            } else {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to name of t
                            if u contains "youtube.com" or u contains "youtu.be" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    return (do JavaScript "\(js)" in t) as text
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            }

            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                let result = script.executeAndReturnError(&error)
                if error == nil, let res = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), res == "clicked" || res == "reset" {
                    return
                }
            }
        }
        SystemMediaKeySender.previousTrack()
    }

    private func seekBrowser(to seconds: TimeInterval) {
        for browser in Self.browserTargets {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { continue }
            let js = "(function(){var p=document.querySelector('#movie_player');if(p&&p.seekTo){p.seekTo(\(seconds),true);return 'seeked';}var v=document.querySelector('video');if(v){v.currentTime=\(seconds);return 'seeked';}return 'none';})();"
            let scriptSource: String
            if browser.isChromium {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to title of t
                            if u contains "youtube.com" or u contains "youtu.be" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    tell t
                                        return (execute javascript "\(js)") as text
                                    end tell
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            } else {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to name of t
                            if u contains "youtube.com" or u contains "youtu.be" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    return (do JavaScript "\(js)" in t) as text
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            }

            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                _ = script.executeAndReturnError(&error)
            }
        }
    }

    /// Drives the selected provider directly. `tell application` launches the
    /// app if it isn't running, so picking a provider and pressing play really
    /// starts that player.
    // MARK: - Shuffle and favourite

    /// Both of these were local `@State` in the player view: the heart and the
    /// shuffle glyph changed colour and did nothing at all. They talk to the
    /// player now — shuffle through Apple Events, which every supported player
    /// understands, and the heart through whatever the current player actually
    /// has (Music has `loved`; Spotify's saved-songs library is Web API only).
    private(set) var isShuffling = false
    private(set) var isFavorite = false

    /// The app these two controls talk to: whatever is actually playing when
    /// that is a player with an Apple Events vocabulary, and the configured
    /// provider otherwise. Without this the heart aimed at Music while
    /// Spotify was the thing making sound.
    private var controlBundleID: String {
        if let source = sourceAppBundleID,
           source == "com.apple.Music" || source == MusicProvider.spotify.bundleID {
            return source
        }
        return fallbackBundleID
    }

    private var controlAppName: String {
        controlBundleID == MusicProvider.spotify.bundleID ? "Spotify" : "Music"
    }

    private var controlAppIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: controlBundleID).isEmpty
    }

    /// Whether the heart can do anything for the player that is playing.
    var canFavorite: Bool {
        guard hasTrack else { return false }
        if controlBundleID == MusicProvider.spotify.bundleID {
            return SpotifyAuth.shared.state == .signedIn
        }
        return controlBundleID == "com.apple.Music"
    }

    func toggleShuffle() {
        let appName = controlAppName
        let isMusic = controlBundleID == "com.apple.Music"
        let property = isMusic ? "shuffle enabled" : "shuffling"
        let wanted = !isShuffling
        isShuffling = wanted

        runScript("tell application \"\(appName)\" to set \(property) to \(wanted)") { [weak self] ok in
            guard !ok else { return }
            // The player refused — put the control back where it was rather
            // than leaving it showing a state that is not real.
            self?.isShuffling = !wanted
        }
    }

    func toggleFavorite() {
        guard canFavorite else { return }
        let wanted = !isFavorite
        isFavorite = wanted

        if controlBundleID == "com.apple.Music" {
            let appName = controlAppName
            runScript(
                "tell application \"\(appName)\" to set loved of current track to \(wanted)"
            ) { [weak self] ok in
                guard !ok else { return }
                self?.isFavorite = !wanted
            }
            return
        }

        Task { [weak self] in
            guard let token = await SpotifyAuth.shared.validAccessToken(),
                  let id = await SpotifyClient.playback(token: token)?.trackID,
                  await SpotifyClient.setSaved(wanted, trackID: id, token: token)
            else {
                await MainActor.run { [weak self] in self?.isFavorite = !wanted }
                return
            }
        }
    }

    /// Reads both states for the track that just started, so the controls show
    /// the player's truth rather than whatever they were left on.
    private func refreshShuffleAndFavorite() {
        let appName = controlAppName
        let isMusic = controlBundleID == "com.apple.Music"
        let property = isMusic ? "shuffle enabled" : "shuffling"
        let lovedScript = isMusic
            ? "tell application \"\(appName)\" to return (loved of current track) as text"
            : nil
        let shuffleScript = "tell application \"\(appName)\" to return \(property) as text"
        let running = controlAppIsRunning
        let allowed = IntegrationPermissions.isAutomationAllowed(controlBundleID)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard running, allowed else { return }
            let shuffle = Self.scriptString(shuffleScript) == "true"
            let loved = lovedScript.map { Self.scriptString($0) == "true" }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isShuffling != shuffle { self.isShuffling = shuffle }
                if let loved, self.isFavorite != loved { self.isFavorite = loved }
            }
        }

        guard !isMusic else { return }
        Task { [weak self] in
            guard let token = await SpotifyAuth.shared.validAccessToken(),
                  let id = await SpotifyClient.playback(token: token)?.trackID
            else { return }
            let saved = await SpotifyClient.isSaved(trackID: id, token: token)
            await MainActor.run { [weak self] in
                guard let self, self.isFavorite != saved else { return }
                self.isFavorite = saved
            }
        }
    }

    /// One fire-and-forget script, off the main thread, reporting whether it
    /// ran without an error.
    private func runScript(_ source: String, completion: @escaping (Bool) -> Void) {
        guard controlAppIsRunning else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let ok = error == nil
            DispatchQueue.main.async { completion(ok) }
        }
    }

    private static func scriptString(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Transport over Apple Events, off the main thread.
    ///
    /// `executeAndReturnError` is a synchronous Apple Event with a long
    /// default timeout: run it on the main thread and a player that is busy
    /// launching, or stuck, freezes the whole UI mid-click. Nothing here needs
    /// its result, so it goes to a background queue and the state is re-read
    /// afterwards.
    private func runProviderCommand(appName: String, command: String) {
        let bundleID = appName == "Spotify" ? MusicProvider.spotify.bundleID : "com.apple.Music"
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty

        let source = "tell application \"\(appName)\" to \(command)"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)

            if error != nil {
                DispatchQueue.main.async {
                    if command == "playpause" || command == "pause" || command == "play" {
                        SystemMediaKeySender.togglePlayPause()
                    } else if command == "next track" {
                        SystemMediaKeySender.nextTrack()
                    } else if command == "previous track" {
                        SystemMediaKeySender.previousTrack()
                    }
                }
            }

            // Players need a short beat (200ms) to settle into the new state before we read it back.
            usleep(200_000)
            let snapshot = self?.appleScriptSnapshot()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let snapshot {
                    self.pendingClearWork?.cancel()
                    self.pendingClearWork = nil
                    self.apply(snapshot)
                } else if !isRunning {
                    self.clearTrackAfterGrace()
                }
            }
        }
    }

    // MARK: - MediaRemote source

    private func refreshFromMediaRemote() {
        // With the adapter active the stream is the source; there is nothing
        // to ask the dlopen bridge (which is gated on this macOS anyway).
        guard useMediaRemote, !useAdapter else { return }
        bridge.nowPlayingInfo { [weak self] info in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if info.isEmpty {
                    // MediaRemote has nothing to say. While a browser-derived
                    // track is showing, that silence is expected — browsers are
                    // exactly what gated MediaRemote can't see — so don't
                    // blank it here. Otherwise probe the browser directly
                    // before concluding nothing is playing.
                    if self.isShowingBrowserSnapshot { return }
                    self.handleEmptyMediaRemoteReply()
                    return
                }

                let title = (info[MediaRemoteBridge.InfoKey.title] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let isBrowser = self.sourceAppBundleID.map { bundle in Self.browserTargets.contains(where: { $0.bundleID == bundle }) } ?? false

                // If MediaRemote reports for a browser without a title, defer to the browser probe.
                if isBrowser && title.isEmpty {
                    return
                }

                if isBrowser {
                    self.isShowingBrowserSnapshot = true
                    self.isBrowserVideo = true
                } else {
                    self.isShowingBrowserSnapshot = false
                    self.isBrowserVideo = false
                }

                guard self.providerAllowsCurrentSource() else {
                    // A different app is playing than the one selected — show
                    // nothing until the chosen provider takes over.
                    self.apply([:])
                    return
                }
                self.apply(info)
            }
        }
        bridge.nowPlayingApplicationPID { [weak self] pid in
            DispatchQueue.main.async { [weak self] in
                self?.updateSourceApp(pid: pid)
            }
        }
        bridge.isPlaying { [weak self] playing in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // A browser-derived track plays on the browser's own schedule;
                // gated MediaRemote reports false for it and must not flip the
                // transport state.
                guard !self.isShowingBrowserSnapshot else { return }
                guard self.providerAllowsCurrentSource() else {
                    if self.isPlaying { self.isPlaying = false }
                    return
                }
                if self.isPlaying != playing {
                    // Re-anchor so extrapolation pauses/resumes correctly.
                    self.elapsedAnchor = self.currentElapsed
                    self.anchorDate = Date()
                    self.isPlaying = playing
                    self.updateLyricActivityTimer()
                }
            }
        }
    }

    /// Now-playing updates from the perl-bridge adapter (its stream handler).
    /// Mirrors what the direct-bridge refresh does with the same info keys,
    /// plus the PID and media type the adapter's payload carries.
    private func applyAdapterInfo(_ info: [String: Any]) {
        guard useAdapter else { return }
        if info.isEmpty {
            // Empty full-state payload after real data = the player went
            // away. A browser-derived track must not be blanked by it — the
            // browser probe owns keeping that honest — same as the
            // direct-bridge path.
            if isShowingBrowserSnapshot {
                return
            }

            handleEmptyMediaRemoteReply()
            return
        }
        if let pid = info[MediaRemoteAdapter.Key.processIdentifier] as? Int {
            updateSourceApp(pid: Int32(pid))
        }

        let title = (info[MediaRemoteBridge.InfoKey.title] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isBrowser = sourceAppBundleID.map { bundle in Self.browserTargets.contains(where: { $0.bundleID == bundle }) } ?? false

        // If MediaRemote reports for a browser without a title, defer to the browser probe.
        if isBrowser && title.isEmpty {
            return
        }

        if isBrowser {
            isShowingBrowserSnapshot = true
            isBrowserVideo = true
            lyrics.clear()
            collapsedLyricLine = nil
        } else {
            isShowingBrowserSnapshot = false
            isBrowserVideo = false
        }

        sourceMediaType = info[MediaRemoteAdapter.Key.mediaType] as? String
        guard providerAllowsCurrentSource() else {
            apply([:])
            return
        }
        apply(info)
    }

    /// The adapter's stream process died on its own. Restart once — a
    /// transient kill should not cost the source — then give up on MediaRemote
    /// for this session and demote to the Apple Events path, the same fallback
    /// the gated direct bridge ends up on.
    private func handleAdapterTerminated() {
        guard useAdapter else { return }
        adapterRestartAttempts += 1
        if adapterRestartAttempts <= 1 {
            adapter.startStream()
        } else {
            demoteToAppleEvents()
        }
    }

    private func apply(_ info: [String: Any]) {
        guard !info.isEmpty else {
            noteEmptyMediaRemoteReply()
            // Not cleared on the spot: players go quiet for a moment between
            // tracks, and blanking the panel there is what made the
            // "can't see other players" notice flash between songs.
            clearTrackAfterGrace()
            return
        }

        consecutiveEmptyReplies = 0
        pendingClearWork?.cancel()
        pendingClearWork = nil

        var newTrack = Track()
        var rawTitle = info[MediaRemoteBridge.InfoKey.title] as? String ?? ""
        if rawTitle.hasSuffix(" - YouTube") {
            rawTitle = String(rawTitle.dropLast(" - YouTube".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if rawTitle.hasSuffix(" - YouTube Music") {
            rawTitle = String(rawTitle.dropLast(" - YouTube Music".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        newTrack.title = rawTitle
        newTrack.artist = info[MediaRemoteBridge.InfoKey.artist] as? String ?? ""
        newTrack.album = info[MediaRemoteBridge.InfoKey.album] as? String ?? ""
        newTrack.duration = info[MediaRemoteBridge.InfoKey.duration] as? TimeInterval ?? 0

        let isBrowser = sourceAppBundleID.map { bundle in Self.browserTargets.contains(where: { $0.bundleID == bundle }) } ?? false
        if isBrowser {
            isShowingBrowserSnapshot = true
            isBrowserVideo = true
            if newTrack.album.isEmpty { newTrack.album = "YouTube" }
            if newTrack.artist.isEmpty { newTrack.artist = "YouTube" }
        }

        if let elapsed = info[MediaRemoteBridge.InfoKey.elapsedTime] as? TimeInterval {
            elapsedAnchor = elapsed
            anchorDate = info[MediaRemoteBridge.InfoKey.timestamp] as? Date ?? Date()
        }

        let playbackRate: Double?
        if let rate = info[MediaRemoteBridge.InfoKey.playbackRate] as? Double {
            playbackRate = rate
        } else if let playing = info[MediaRemoteAdapter.Key.playing] as? Bool {
            playbackRate = playing ? 1 : 0
        } else {
            playbackRate = nil
        }
        if let playbackRate {
            let playing = playbackRate > 0
            if playing != isPlaying {
                if !playing {
                    elapsedAnchor = currentElapsed
                    anchorDate = Date()
                } else {
                    anchorDate = Date()
                }
                isPlaying = playing
                updateLyricActivityTimer()
            }
        }

        if let data = info[MediaRemoteBridge.InfoKey.artworkData] as? Data {
            artwork = NSImage(data: data)
            updateAccentIfNeeded(for: data)
        }

        updateTrackIfChanged(newTrack)
        onNormalizedTrackChange?(normalizedTrack)
    }

    /// An empty MediaRemote reply is ambiguous: either nothing is playing, or
    /// this macOS refuses to say. Only replies received while a player the
    /// fallback can actually read is running count towards demotion — an
    /// empty reply with no such player running is just silence, and switching
    /// away from MediaRemote then would lose every other source for nothing.
    private func noteEmptyMediaRemoteReply() {
        guard useMediaRemote, fallbackAppIsRunning else { return }
        consecutiveEmptyReplies += 1
        guard consecutiveEmptyReplies >= Self.emptyRepliesBeforeDemotion else { return }

        demoteToAppleEvents()
    }

    /// MediaRemote reported nothing. On macOS 15.4+ its now-playing entry
    /// points are gated for third-party apps and answer with silence even
    /// while a browser is blasting YouTube — so ask the player and the
    /// browser directly instead of declaring nothing is playing.
    private func handleEmptyMediaRemoteReply() {
        // A probe while the notch is closed must never be what raises the
        // Automation dialog; one while the user is looking at the notch may —
        // without consent the browser snapshot can never work, and the prompt
        // is how consent is obtained.
        probeBrowserForPlayingMedia(avoidPrompt: !isActive)
        apply([:])
    }

    /// One off-main probe for the selected player and then the browsers, on
    /// an empty MediaRemote reply. The player outranks the browser — the
    /// provider is what the notch controls — so a playing Spotify/Music track
    /// demotes the source on the spot instead of losing to a YouTube tab.
    private func probeBrowserForPlayingMedia(avoidPrompt: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // With avoidPrompt, consent is pre-checked before any script
            // runs, mirroring the launch probe's rule. With the notch open,
            // running the script against a consented-or-undetermined app is
            // exactly how the Automation prompt gets raised.
            let snapshot: Snapshot?
            if avoidPrompt, !self.automationIsAllowed() {
                snapshot = self.browserYouTubeSnapshot(avoidPrompt: true)
            } else {
                snapshot = self.appleScriptSnapshot()
                    ?? self.browserYouTubeSnapshot(avoidPrompt: avoidPrompt)
            }
            guard let snapshot else { return }
            let isPlayer = snapshot.bundleID == self.fallbackBundleID

            DispatchQueue.main.async { [weak self] in
                guard let self, self.useMediaRemote else { return }
                if isPlayer {
                    // The selected player is playing but MediaRemote couldn't
                    // see it — demote so the Apple Events path owns it from
                    // here on (it also starts its 2s polling).
                    self.demoteToAppleEvents()
                } else {
                    // YouTube is intentionally allowed to replace stale
                    // player metadata in the visible media tabs.
                    self.pendingClearWork?.cancel()
                    self.pendingClearWork = nil
                    self.isShowingBrowserSnapshot = true
                    self.isBrowserVideo = true
                }
                if isPlayer {
                    self.apply(snapshot)
                } else {
                    self.applyBrowserSnapshot(snapshot)
                }
            }
        }
    }

    /// Keeps a browser-derived track honest while the notch is open and
    /// MediaRemote is the source: re-reads the browser every couple of
    /// seconds, updating the track when the video changes and clearing it
    /// when the tab closes. MediaRemote never answers for browsers, so
    /// without this a closed tab would leave a ghost track on screen.
    private func tickBrowserProbe() {
        // The timer only exists while the notch is open and MediaRemote is the
        // source. It probes the browser every couple of seconds regardless of
        // what is currently showing: gated MediaRemote never answers for
        // browsers, so an open notch with a YouTube video running would
        // otherwise sit on "Nothing Playing" forever — nothing would ever
        // establish the browser track. avoidPrompt tracks isActive so the
        // first open can raise the Automation consent prompt for the browser;
        // a real player's track outranks a YouTube tab.
        guard useMediaRemote else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = self?.browserYouTubeSnapshot(avoidPrompt: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let snapshot else {
                    // Browser went away (tab closed) — clear only a track that
                    // actually came from the browser probe.
                    if self.isShowingBrowserSnapshot {
                        self.finishClearingTrack()
                    }
                    return
                }
                // YouTube is the preferred visible source in the media tabs.
                // A browser result replaces stale Music/Spotify metadata while
                // the video is playing, rather than waiting for the old track
                // to disappear first.
                self.isShowingBrowserSnapshot = true
                self.isBrowserVideo = true
                self.pendingClearWork?.cancel()
                self.pendingClearWork = nil
                self.applyBrowserSnapshot(snapshot)
            }
        }
    }

    private func applyBrowserSnapshot(_ snapshot: Snapshot) {
        isShowingBrowserSnapshot = true
        isBrowserVideo = true
        sourceAppName = snapshot.appName
        sourceAppBundleID = snapshot.bundleID
        sourceAppPID = 0
        if let artworkURL = snapshot.artworkURL {
            loadBrowserArtwork(from: artworkURL)
        }
        apply(snapshot)
        // `apply(_:)` deliberately updates the common source fields, so
        // restore the browser identity after it has finished. Otherwise the
        // next MediaRemote/app refresh can make the UI fall back to Music.
        isShowingBrowserSnapshot = true
        isBrowserVideo = true
        sourceAppName = snapshot.appName
        sourceAppBundleID = snapshot.bundleID
    }

    private func loadBrowserArtwork(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isShowingBrowserSnapshot else { return }
                self.artwork = image
                self.updateAccentIfNeeded(for: data)
                self.onNormalizedTrackChange?(self.normalizedTrack)
            }
        }.resume()
    }

    /// One AppleScript probe when the notch opens, covering the gated-
    /// MediaRemote case: the fallback player reports a playing track while
    /// the system source has returned silence. That combination is the
    /// macOS 15.4 gate, so the source is demoted on the spot and the track
    /// shows immediately instead of after several more empty replies.
    private func probeFallbackIfMediaRemoteSilent() {
        // Only worth asking when nothing is being shown, the fallback player
        // is actually running, and MediaRemote has already answered at least
        // once with silence (guards against demoting during a momentary gap
        // on a healthy system).
        guard useMediaRemote,
              (track == nil || !isPlaying),
              consecutiveEmptyReplies >= 1,
              fallbackAppIsRunning,
              automationIsAllowed()
        else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let snapshot = self?.appleScriptSnapshot(), snapshot.isPlaying else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.useMediaRemote else { return }
                self.demoteToAppleEvents()
                self.apply(snapshot)
            }
        }
    }

    /// Switches the source from MediaRemote to the Apple Events path and
    /// rebuilds its timers.
    private func demoteToAppleEvents() {
        if useAdapter {
            useAdapter = false
            adapter.stop()
        }
        useMediaRemote = false
        isSystemNowPlayingRestricted = true
        consecutiveEmptyReplies = Self.emptyRepliesBeforeDemotion
        pendingClearWork?.cancel()
        pendingClearWork = nil
        if isActive {
            setActive(true)
        }
    }

    /// Why nothing is showing, when nothing is showing — so the player says
    /// what is actually wrong instead of claiming nothing is playing.
    var emptyStateReason: String? {
        guard track == nil else { return nil }
        // With the perl-bridge adapter, system-wide now-playing works even on
        // gated macOS — nothing is restricted, so no explanation is owed.
        if useAdapter { return nil }
        if isSystemNowPlayingRestricted {
            return "macOS restricts system-wide now-playing for third-party apps on "
                + "this version. Notch reads \(fallbackAppName) and browsers "
                + "directly; other players can't be seen."
        }
        if !bridge.isAvailable {
            return "System-wide now-playing isn't available here. Notch reads "
                + "\(fallbackAppName) directly."
        }
        return nil
    }

    /// Resolves the now-playing app from its PID, once per change.
    private func updateSourceApp(pid: Int32) {
        // While a browser-derived track is showing, MediaRemote's idea of the
        // now-playing app (often stale or gated) must not override the browser
        // the snapshot came from.
        if isShowingBrowserSnapshot { return }
        guard pid != sourceAppPID else { return }
        sourceAppPID = pid
        guard pid > 0,
              let app = NSRunningApplication(processIdentifier: pid_t(pid))
        else {
            sourceAppName = nil
            sourceAppIcon = nil
            sourceAppBundleID = nil
            return
        }
        sourceAppName = app.localizedName
        sourceAppIcon = app.icon
        sourceAppBundleID = app.bundleIdentifier
        // Re-pull metadata now that the source identity is known (info can
        // arrive before the pid), so the provider filter sees the right app.
        refreshFromMediaRemote()
    }

    /// Extracts the artwork accent off the main thread, once per unique image.
    private func updateAccentIfNeeded(for artworkData: Data) {
        let hash = artworkData.hashValue
        guard hash != accentSourceHash else { return }
        accentSourceHash = hash

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let image = NSImage(data: artworkData) else { return }
            let color = NotchTheme.accent(from: image)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.accentSourceHash == hash else { return }
                withAnimation(.notchSpring) {
                    self.accent = color
                }
            }
        }
    }

    /// Pulls the queue and the artist's follower count once per track.
    private func refreshSpotifyDetail(for track: Track) {
        let key = track.title + "\u{1}" + track.artist
        guard key != lastSpotifyLookup else { return }
        lastSpotifyLookup = key

        Task { [weak self] in
            guard let token = await SpotifyAuth.shared.validAccessToken() else {
                await MainActor.run { [weak self] in
                    self?.queue = []
                    self?.followersLabel = nil
                }
                return
            }

            var items = await SpotifyClient.queue(token: token)
            if let first = items.first {
                var withArt = first
                withArt.artwork = await SpotifyClient.artwork(for: first)
                items[0] = withArt
            }
            // Immutable snapshot so the concurrent MainActor closure captures
            // a let, not a mutable var — Swift 6 forbids the latter.
            let queue = items
            let followers = await SpotifyClient.followers(forArtist: track.artist, token: token)

            await MainActor.run { [weak self] in
                guard let self, self.lastSpotifyLookup == key else { return }
                self.queue = queue
                self.followersLabel = followers.map {
                    "Followers: " + Self.compactCount($0)
                }
            }
        }
    }

    /// "245.3K", the way the reference renders its counts.
    private static func compactCount(_ value: Int) -> String {
        switch value {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return String(format: "%.1fK", Double(value) / 1_000)
        default: return String(format: "%.1fM", Double(value) / 1_000_000)
        }
    }

    private func updateTrackIfChanged(_ newTrack: Track) {
        let previous = track
        guard newTrack != previous else {
            onNormalizedTrackChange?(normalizedTrack)
            return
        }
        track = newTrack.title.isEmpty ? nil : newTrack

        // Announce track-to-track changes, not the initial pickup at launch.
        if let current = track, previous != nil, current.title != previous?.title {
            onTrackChange?(current)
        }
        if let track {
            if NotchSettings.shared.fetchLyrics && !isBrowserVideo {
                lyrics.load(
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration
                )
            } else {
                lyrics.clear()
            }
            refreshSpotifyDetail(for: track)
            refreshShuffleAndFavorite()
        } else {
            lyrics.clear()
            artwork = nil
            accent = .white
            accentSourceHash = nil
            queue = []
            followersLabel = nil
            lastSpotifyLookup = nil
        }
        onNormalizedTrackChange?(normalizedTrack)
    }

    // MARK: - Apple Events fallback (the selected provider)

    /// App name and bundle used by the AppleScript fallback: the chosen
    /// provider, or Music/Spotify dynamically for Automatic.
    private var fallbackAppName: String {
        switch selectedProvider {
        case .appleMusic:
            return "Music"
        case .spotify:
            return "Spotify"
        case .automatic:
            if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
                return "Music"
            }
            if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
                return "Spotify"
            }
            return "Music"
        }
    }

    private var fallbackBundleID: String {
        switch selectedProvider {
        case .appleMusic:
            return "com.apple.Music"
        case .spotify:
            return MusicProvider.spotify.bundleID
        case .automatic:
            if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
                return "com.apple.Music"
            }
            if !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty {
                return MusicProvider.spotify.bundleID
            }
            return "com.apple.Music"
        }
    }

    private func stateScript(for appName: String) -> String {
        """
        tell application "\(appName)"
            try
                if player state is stopped then return "stopped"
                set t to current track
                return (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & \
        (duration of t as text) & "||" & (player position as text) & "||" & (player state as text)
            on error
                return "stopped"
            end try
        end tell
        """
    }

    private var fallbackAppIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: fallbackBundleID).isEmpty
    }

    private struct BrowserTarget {
        let name: String
        let bundleID: String
        let isChromium: Bool
    }

    private struct YouTubeMediaState {
        let title: String
        let youtuber: String
        let thumbnailURL: String
        let progress: Double
        let duration: TimeInterval
    }

    private static let browserTargets: [BrowserTarget] = [
        BrowserTarget(name: "Safari", bundleID: "com.apple.Safari", isChromium: false),
        BrowserTarget(name: "Google Chrome", bundleID: "com.google.Chrome", isChromium: true),
        BrowserTarget(name: "Google Chrome Canary", bundleID: "com.google.Chrome.canary", isChromium: true),
        BrowserTarget(name: "Arc", bundleID: "company.thebrowser.Browser", isChromium: true),
        BrowserTarget(name: "Brave Browser", bundleID: "com.brave.Browser", isChromium: true),
        BrowserTarget(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", isChromium: true),
        BrowserTarget(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", isChromium: true),
        BrowserTarget(name: "Orion", bundleID: "com.kagi.kagisafari", isChromium: false),
        BrowserTarget(name: "Opera", bundleID: "com.operasoftware.Opera", isChromium: true),
        BrowserTarget(name: "Opera GX", bundleID: "com.operasoftware.OperaGX", isChromium: true),
        BrowserTarget(name: "Zen Browser", bundleID: "app.zen-browser.zen", isChromium: false),
        BrowserTarget(name: "Chromium", bundleID: "org.chromium.Chromium", isChromium: true)
    ]

    private static func extractYouTubeVideoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !v.isEmpty {
            return v
        }

        if urlString.contains("youtu.be/") {
            if let id = url.pathComponents.dropFirst().first, !id.isEmpty {
                return id.components(separatedBy: "?").first?.components(separatedBy: "&").first?.components(separatedBy: "#").first
            }
        }

        let pathComponents = url.pathComponents
        for prefix in ["shorts", "embed", "live", "v"] {
            if let idx = pathComponents.firstIndex(of: prefix), idx + 1 < pathComponents.count {
                let candidate = pathComponents[idx + 1]
                if !candidate.isEmpty {
                    return candidate.components(separatedBy: "?").first?.components(separatedBy: "&").first?.components(separatedBy: "#").first
                }
            }
        }

        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return Bool(value) }
        return nil
    }

    private func browserYouTubeSnapshot(avoidPrompt: Bool) -> Snapshot? {
        for browser in Self.browserTargets {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else {
                continue
            }
            // A background probe must not be what raises the Automation
            // prompt; only the interactive probe (notch open) may.
            if avoidPrompt,
               !IntegrationPermissions.isAutomationAllowed(browser.bundleID) {
                continue
            }

            // The DOM script is what carries the real payload: the rendered
            // title (no " - YouTube" suffix), the channel name, the video ID
            // for the thumbnail, and the live currentTime/duration for the
            // progress bar. Chromium exposes it through `execute javascript`;
            // Safari through `do JavaScript`, falling back to the tab-title
            // path when "Allow JavaScript from Apple Events" is off.
            let js = "(function(){try{var title=(document.querySelector('h1.ytd-watch-metadata')||document.querySelector('h1')).innerText||document.title;var channel=(document.querySelector('#upload-info #channel-name a')||document.querySelector('ytd-channel-name a')).innerText||'';var p=document.querySelector('#movie_player');var d=p&&p.getDuration?p.getDuration():0;var c=p&&p.getCurrentTime?p.getCurrentTime():0;var id=p&&p.getVideoData?p.getVideoData().video_id:'';var playing=false;try{playing=p&&p.getPlayerState?p.getPlayerState()===1:(function(){var v=document.querySelector('video');return !!v&&!v.paused&&!v.ended;})();}catch(e){}return JSON.stringify({title:title,youtuber:channel,thumbnail:id?'https://img.youtube.com/vi/'+id+'/maxresdefault.jpg':'',progress:d>0?c/d:0,duration:d,playing:playing});}catch(e){return '';}})();"

            let scriptSource: String
            if browser.isChromium {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to title of t
                            if u contains "youtube.com/watch" or u contains "youtu.be" or u contains "music.youtube.com" or u contains "youtube.com/shorts" or u contains "youtube.com/live" or u contains "youtube.com/embed" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    tell t
                                        return (execute javascript "\(js)") as text
                                    end tell
                                on error
                                    return n & "||" & u
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            } else {
                scriptSource = """
                tell application "\(browser.name)"
                    if (count of windows) is 0 then return ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to name of t
                            if u contains "youtube.com/watch" or u contains "youtu.be" or u contains "music.youtube.com" or u contains "youtube.com/shorts" or u contains "youtube.com/live" or u contains "youtube.com/embed" or n contains " - YouTube" or n contains "YouTube Music" then
                                try
                                    return (do JavaScript "\(js)" in t) as text
                                on error
                                    return n & "||" & u
                                end try
                            end if
                        end repeat
                    end repeat
                    return ""
                end tell
                """
            }

            var error: NSDictionary?
            guard let script = NSAppleScript(source: scriptSource) else { continue }
            let result = script.executeAndReturnError(&error)
            guard error == nil, let raw = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                continue
            }

            // The DOM script returns JSON on its own — no "||" separator —
            // so the legacy tab-title path must only run when the reply is
            // not JSON. (The old guard demanded "||", which silently threw
            // away every Chromium reply and left "Nothing Playing" on screen
            // while YouTube played.)
            if let data = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let jsTitle = json["title"] as? String,
               !jsTitle.isEmpty {
                let channel = json["youtuber"] as? String ?? "YouTube"
                let thumbnail = json["thumbnail"] as? String ?? ""
                let progress = Self.doubleValue(json["progress"])
                    .map { min(max($0, 0), 1) } ?? 0
                let duration = max(Self.doubleValue(json["duration"]) ?? 0, 0)

                var track = Track()
                track.title = jsTitle
                track.artist = channel
                track.album = "YouTube"
                track.duration = duration
                return Snapshot(
                    track: track,
                    elapsed: progress * duration,
                    duration: duration,
                    isPlaying: Self.boolValue(json["playing"]) ?? false,
                    bundleID: browser.bundleID,
                    appName: browser.name,
                    artworkURL: thumbnail.isEmpty ? nil : URL(string: thumbnail),
                    isBrowser: true
                )
            }

            // Legacy tab-title path: "Title - YouTube||https://…".
            guard raw.contains("||") else { continue }
            let parts = raw.components(separatedBy: "||")
            guard parts.count >= 2 else { continue }

            var title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let urlString = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            if title.hasSuffix(" - YouTube") {
                title = String(title.dropLast(" - YouTube".count))
            } else if title.hasSuffix(" - YouTube Music") {
                title = String(title.dropLast(" - YouTube Music".count))
            }

            var artist = "YouTube"
            if title.contains(" - ") {
                let split = title.components(separatedBy: " - ")
                if split.count >= 2 {
                    artist = split[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    title = split[1...].joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            var artworkURL: URL?
            if let videoID = Self.extractYouTubeVideoID(from: urlString) {
                artworkURL = URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
                // A watch-page tab title is just "Title - YouTube" — no
                // channel. Pull the real channel name from the video so the
                // player shows who made it, not the platform.
                if artist == "YouTube", let channel = channelName(for: videoID) {
                    artist = channel
                }
            }

            var track = Track()
            track.title = title
            track.artist = artist
            track.album = "YouTube"
            return Snapshot(
                track: track,
                elapsed: 0,
                duration: 0,
                isPlaying: false,
                bundleID: browser.bundleID,
                appName: browser.name,
                artworkURL: artworkURL,
                isBrowser: true
            )
        }
        return nil
    }

    /// Channel names for video IDs already looked up, so the periodic browser
    /// probe never re-fetches what it has already seen.
    private var channelCache: [String: String] = [:]
    private static let channelCacheLock = NSLock()

    /// The channel name for a video, via YouTube's oEmbed endpoint (a small
    /// JSON document carrying `author_name`). Returns nil when the fetch fails
    /// — consent walls, rate limiting, offline — and the player then shows
    /// "YouTube" as the artist rather than the channel. Blocking on a cold
    /// miss, so it is only ever called off the main thread, and cached so the
    /// 2s probe never refetches.
    private func channelName(for videoID: String) -> String? {
        Self.channelCacheLock.lock()
        let cached = channelCache[videoID]
        Self.channelCacheLock.unlock()
        if let cached { return cached }

        let watchURL = "https://www.youtube.com/watch?v=\(videoID)"
        guard let url = URL(string: "https://www.youtube.com/oembed?url=\(watchURL)&format=json")
        else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        // The URLRequest overloads of Data(contentsOf:) no longer exist in the
        // current SDK, so fetch synchronously via URLSession instead. Only ever
        // called off the main thread (this is a blocking cold-miss fetch); the
        // semaphore is the happens-before edge that makes the captured write safe.
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            fetched = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + request.timeoutInterval)
        guard let data = fetched else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              let name = json["author_name"] as? String,
              !name.isEmpty
        else { return nil }

        Self.channelCacheLock.lock()
        channelCache[videoID] = name
        Self.channelCacheLock.unlock()
        return name
    }

    /// One reading of the player's state, or nil when it has nothing to say.
    /// Blocking, so it is only called from a background queue or from the
    /// fallback timer, which already runs while the notch is open.
    private struct Snapshot {
        var track: Track
        var elapsed: TimeInterval
        var duration: TimeInterval = 0
        var isPlaying: Bool
        var bundleID: String?
        var appName: String?
        var artworkURL: URL?
        /// True for browser snapshots: MediaRemote can't see or confirm them,
        /// they carry no real playback position, and their artwork is a URL.
        var isBrowser = false
    }

    private func appleScriptSnapshot() -> Snapshot? {
        var targets: [(appName: String, bundleID: String)] = []
        if let bundle = sourceAppBundleID {
            if bundle == MusicProvider.spotify.bundleID {
                targets = [("Spotify", MusicProvider.spotify.bundleID), ("Music", "com.apple.Music")]
            } else if bundle == "com.apple.Music" {
                targets = [("Music", "com.apple.Music"), ("Spotify", MusicProvider.spotify.bundleID)]
            }
        }
        if targets.isEmpty {
            if selectedProvider == .spotify {
                targets = [("Spotify", MusicProvider.spotify.bundleID)]
            } else if selectedProvider == .appleMusic {
                targets = [("Music", "com.apple.Music")]
            } else {
                targets = [("Spotify", MusicProvider.spotify.bundleID), ("Music", "com.apple.Music")]
            }
        }

        for target in targets {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).isEmpty else { continue }
            if let script = NSAppleScript(source: stateScript(for: target.appName)) {
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if error == nil, let raw = result.stringValue, raw != "stopped" {
                    let parts = raw.components(separatedBy: "||")
                    if parts.count >= 6, !parts[0].isEmpty {
                        var newTrack = Track()
                        newTrack.title = parts[0]
                        newTrack.artist = parts[1]
                        newTrack.album = parts[2]
                        newTrack.duration = Self.seconds(fromAppleScript: parts[3])

                        return Snapshot(
                            track: newTrack,
                            elapsed: TimeInterval(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0,
                            duration: newTrack.duration,
                            isPlaying: parts[5] == "playing",
                            bundleID: target.bundleID,
                            appName: target.appName,
                            artworkURL: nil
                        )
                    }
                }
            }
        }

        // 2. Check running browsers for YouTube/web media. Runs regardless of
        // the selected provider: the provider choice is about which player the
        // notch *controls*, and a browser playing in the foreground is still
        // the thing making sound. The selected player already had first crack
        // above; the browser is only asked when it has nothing to say.
        // Consent-gated: a background probe must never be what raises the
        // Automation prompt.
        if let browserSnap = browserYouTubeSnapshot(avoidPrompt: true) {
            return browserSnap
        }

        return nil
    }

    private func apply(_ snapshot: Snapshot) {
        isShowingBrowserSnapshot = snapshot.isBrowser
        isBrowserVideo = snapshot.isBrowser
        if snapshot.isBrowser {
            lyrics.clear()
            collapsedLyricLine = nil
        }
        if !snapshot.isPlaying && isPlaying {
            elapsedAnchor = currentElapsed
            anchorDate = Date()
        } else if snapshot.duration > 0 {
            // The DOM-based browser snapshot reports real currentTime/duration,
            // so anchor on it and let extrapolation glide between 2s polls.
            elapsedAnchor = snapshot.elapsed
            anchorDate = Date()
        } else if snapshot.isBrowser {
            // Legacy browser snapshots carry no real position (elapsed is 0);
            // re-anchoring on every poll — the 2s probe re-applies the same
            // snapshot — would snap the progress bar back to zero repeatedly.
            // Count forward from the last anchor; only a new video resets it.
            if snapshot.track != track {
                elapsedAnchor = 0
                anchorDate = Date()
            }
        } else {
            elapsedAnchor = snapshot.elapsed
            anchorDate = Date()
        }
        isPlaying = snapshot.isPlaying
        onNormalizedTrackChange?(normalizedTrack)

        let isNewTrack = snapshot.track != track
        updateTrackIfChanged(snapshot.track)
        onNormalizedTrackChange?(normalizedTrack)
        updateLyricActivityTimer()

        if let bundleID = snapshot.bundleID {
            sourceAppBundleID = bundleID
            sourceAppName = snapshot.appName ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            sourceAppIcon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon
        } else if sourceAppName == nil,
           let app = NSRunningApplication
               .runningApplications(withBundleIdentifier: fallbackBundleID).first {
            sourceAppName = app.localizedName
            sourceAppIcon = app.icon
            sourceAppBundleID = fallbackBundleID
        }

        // Artwork only matters when the track actually changed — re-downloading
        // the YouTube thumbnail on every 2s probe poll would be a network
        // request every couple of seconds for the same video.
        if snapshot.duration > 0, let current = track, current.duration != snapshot.duration {
            var updated = current
            updated.duration = snapshot.duration
            track = updated
        }

        if let artworkURL = snapshot.artworkURL, isNewTrack {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                if let data = try? Data(contentsOf: artworkURL), let image = NSImage(data: data) {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.isShowingBrowserSnapshot,
                          self.track?.title == snapshot.track.title,
                          self.track?.artist == snapshot.track.artist
                    else { return }
                    self.artwork = image
                    self.updateAccentIfNeeded(for: data)
                    self.onNormalizedTrackChange?(self.normalizedTrack)
                }
                }
            }
        } else if isNewTrack {
            loadFallbackArtwork()
        }
    }

    /// Reads the player's state on a background queue and applies it on the
    /// main one.
    ///
    /// This runs from a timer every couple of seconds; done inline it is a
    /// blocking Apple Event on the main thread at that cadence, which is a
    /// stutter at best and a beachball whenever the player is slow to answer.
    private func refreshFromAppleScript() {
        guard !isReadingAppleScript else { return }
        isReadingAppleScript = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = self?.appleScriptSnapshot()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isReadingAppleScript = false

                guard let snapshot else {
                    self.clearTrackAfterGrace()
                    return
                }
                self.pendingClearWork?.cancel()
                self.pendingClearWork = nil
                self.apply(snapshot)
            }
        }
    }

    /// One read in flight at a time: a slow player must not let the timer
    /// stack requests behind it.
    private var isReadingAppleScript = false

    /// Waits a beat before blanking the player.
    ///
    /// A player between tracks reports nothing for a moment, and clearing on
    /// the first empty reading made the panel flash its "nothing playing"
    /// state — including the MediaRemote explanation — every time a song
    /// changed. Holding the last track briefly rides that out.
    private func clearTrackAfterGrace() {
        guard track != nil, pendingClearWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingClearWork = nil

            guard !self.useMediaRemote else {
                // MediaRemote has already said there is nothing playing, and
                // it says so again the moment there is. Nothing to re-ask.
                self.finishClearingTrack()
                return
            }

            // Re-ask off the main thread: a player that is slow to answer must
            // not be able to stall the UI, which is what running the script
            // inline here did. The nested closures capture the strong `self`
            // established by the guard above (they are transient, so holding
            // it strongly cannot create a cycle).
            DispatchQueue.global(qos: .userInitiated).async {
                let stillNothing = self.appleScriptSnapshot() == nil
                DispatchQueue.main.async {
                    guard stillNothing else { return }
                    self.finishClearingTrack()
                }
            }
        }
        pendingClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func finishClearingTrack() {
        isShowingBrowserSnapshot = false
        isBrowserVideo = false
        track = nil
        artwork = nil
        isPlaying = false
        sourceAppBundleID = nil
        sourceMediaType = nil
        updateTrackIfChanged(Track())
        updateLyricActivityTimer()
    }

    /// Track length from an AppleScript reply, in seconds.
    ///
    /// Music reports `duration` in seconds and Spotify reports it in
    /// milliseconds, with nothing in the reply to say which — so a Spotify
    /// track came through as roughly a thousand times too long, which is why
    /// the remaining time read like the length of the whole queue. Anything
    /// longer than six hours is taken as milliseconds; no song is that long,
    /// and the ambiguity only exists in that range.
    private static func seconds(fromAppleScript raw: String) -> TimeInterval {
        let value = TimeInterval(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard value > 0 else { return 0 }
        return value > 6 * 60 * 60 ? value / 1_000 : value
    }

    /// Pulls cover art from the player itself.
    ///
    /// Music returns the bytes directly; Spotify only exposes a URL, so that
    /// one is fetched. Both run off the main thread — an Apple Event to a busy
    /// player can take a while to come back.
    private func loadFallbackArtwork() {
        let appName = fallbackAppName
        let isSpotify = selectedProvider == .spotify
            || fallbackBundleID == MusicProvider.spotify.bundleID
        let expected = track

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
                guard let self, self.track == expected else { return }
                self.artwork = image
                if let data {
                    self.updateAccentIfNeeded(for: data)
                } else {
                    self.accent = .white
                    self.accentSourceHash = nil
                }
            }
        }
    }

    deinit {
        mediaNotificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        progressTimer?.invalidate()
        fallbackTimer?.invalidate()
        lyricActivityTimer?.invalidate()
        browserProbeTimer?.invalidate()
        adapter.stop()
    }

    private func runMusicCommand(_ command: String) {
        guard fallbackAppIsRunning,
              let script = NSAppleScript(source: "tell application \"\(fallbackAppName)\" to \(command)")
        else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            DispatchQueue.main.async {
                self?.refreshFromAppleScript()
            }
        }
    }
}
