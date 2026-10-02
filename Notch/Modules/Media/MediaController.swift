import AppKit
import Observation
import SwiftUI
import os

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

    private(set) var track: Track? {
        didSet {
            guard track != oldValue else { return }
            // The collapsed lyric line hangs off the track: the moment one
            // arrives, the activity that draws it has to be reconsidered.
            // (Calling this only from the playback paths is what left the
            // line missing until the notch had been opened and closed once.)
            // A new song also means the clock is anchored to whatever position
            // the player reported for the *previous* one, so it is re-read now.
            invalidatePlaybackReconcile()
            updateLyricActivityTimer()
        }
    }
    private(set) var artwork: NSImage?

    private(set) var isPlaying = false {
        didSet {
            guard isPlaying != oldValue else { return }
            // Resuming is the one moment the anchor is known to be stale: the
            // clock was frozen at the pause, and the player may have moved on
            // since (a seek, or a pause the stream never pushed).
            invalidatePlaybackReconcile()
            onPlaybackStateChange?(isPlaying)
            updateLyricActivityTimer()
        }
    }

    /// Fired when playback starts or stops, so things that cost something to
    /// run — the real-time output meter — only run while there is audio.
    var onPlaybackStateChange: ((Bool) -> Void)?

    /// Legible accent derived from the current artwork; tints the scrubber,
    /// play button, lyrics highlight, and the collapsed equalizer.
    private(set) var accent: Color = .white
    private var accentSourceHash: Int?

    /// Bumped whenever a genuinely *different* artwork image replaces the
    /// current one. Views key their artwork crossfade on this value, so the
    /// 2s browser probe re-downloading the same thumbnail (and MediaRemote
    /// re-pushing the same data) does not re-trigger the crossfade. Only a
    /// real change in the image does.
    private(set) var artworkVersion = 0
    private var lastArtworkData: Data?

    /// Elapsed seconds at `anchorDate`; the live position is extrapolated so
    /// no timer is needed to keep it accurate.
    private var elapsedAnchor: TimeInterval = 0
    private var anchorDate = Date()

    /// UI-facing playback position, refreshed by a lightweight timer that only
    /// runs while the notch is expanded.
    private(set) var displayedElapsed: TimeInterval = 0

    let lyrics = LyricsEngine()

    /// Fired when a genuinely new track replaces a previous one — drives the
    /// collapsed-notch sneak peek.
    var onTrackChange: ((Track) -> Void)?

    /// The synced lyric line surfaced in the collapsed notch while playing,
    /// with the span it is sung over (Sapphire-style lyric live activity).
    private(set) var collapsedLyric: LyricsEngine.LiveLine?

    /// The app the audio is coming from (Spotify, Music, Safari…).
    private(set) var sourceAppName: String?
    private(set) var sourceAppIcon: NSImage?
    private var sourceAppPID: Int32 = 0
    private(set) var sourceAppBundleID: String?
    /// The specific browser media page, when the now-playing item came from
    /// YouTube.
    private(set) var sourceMediaURL: URL?

    /// True while the current metadata came from a YouTube/web-video probe.
    /// This is deliberately exposed so every media surface uses the same
    /// source-priority rule instead of independently guessing from app names.
    private(set) var isBrowserVideo = false {
        didSet {
            guard isBrowserVideo != oldValue else { return }
            // Video never gets a lyric line, so a switch to (or away from) a
            // browser video changes whether the activity should run at all.
            updateLyricActivityTimer()
        }
    }

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
    /// nothing. macOS 15.4 gated the now-playing entry points for apps without
    /// an entitlement Apple no longer issues; the symbols still resolve and the
    /// calls still succeed, they just return empty (the console logs
    /// "Operation not permitted"), so the only way to detect it is to ask and
    /// notice the silence.
    private var isSystemNowPlayingRestricted = false

    /// Consecutive empty MediaRemote replies received while a player the
    /// Apple Events fallback can read was running.
    private var consecutiveEmptyReplies = 0
    private static let emptyRepliesBeforeDemotion = 3

    /// Every `NSAppleScript` execution in this class runs here, and nowhere
    /// else.
    ///
    /// `NSAppleScript` is not thread-safe, and these used to run on the global
    /// *concurrent* queue — so two probes landing together (the 1s browser
    /// tick and a transport read-back, say) executed scripts on two threads at
    /// once. A serial queue gives Apple Events one consistent thread, and it
    /// also stops a slow player from fanning out blocked threads: the work
    /// queues instead of multiplying.
    private static let scriptQueue = DispatchQueue(
        label: "com.notch.applescript", qos: .userInitiated
    )

    /// The observable state a snapshot read depends on, captured on the main
    /// thread before any of it is handed to `scriptQueue`.
    ///
    /// The snapshot functions used to read `sourceAppBundleID`,
    /// `selectedProvider` and `isMusicConnectedOrActive` straight off `self`
    /// while running on a background queue — reads of `@Observable` storage
    /// racing the main thread's writes.
    struct ScriptInputs {
        var sourceBundleID: String?
        var provider: MusicProvider
        var musicOwnsSession: Bool
    }

    /// Captures the inputs above. Main thread only.
    private func captureScriptInputs() -> ScriptInputs {
        ScriptInputs(
            sourceBundleID: sourceAppBundleID,
            provider: selectedProvider,
            musicOwnsSession: isMusicConnectedOrActive
        )
    }

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

    /// How far ahead of the playhead the closed notch looks for its lyric. A
    /// line shown exactly on its timestamp reads late: it still has to fade
    /// in, and the eye lands on it a beat after the voice does.
    private static let lyricLead: TimeInterval = 0.3
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

        setupDistributedPlaybackObservers()

        // Read whatever is playing straight away, off the main thread so a
        // slow-to-answer player cannot hold up launch. Without this the notch
        // showed nothing until it was first opened: MediaRemote is push-based
        // and sends nothing until something changes, and where it is gated the
        // Apple Events path only ran while the notch was expanded.
        let inputs = captureScriptInputs()
        Self.scriptQueue.async { [weak self] in
            self?.probePlayersAtLaunch(attemptsLeft: 4, inputs: inputs)
        }
    }

    private func setupDistributedPlaybackObservers() {
        let center = DistributedNotificationCenter.default()
        let handler: (Notification) -> Void = { [weak self] notification in
            self?.handleDistributedPlaybackNotification(notification)
        }
        mediaNotificationObservers.append(
            center.addObserver(
                forName: Notification.Name("com.apple.iTunes.playerInfo"),
                object: nil,
                queue: .main,
                using: handler
            )
        )
        mediaNotificationObservers.append(
            center.addObserver(
                forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                object: nil,
                queue: .main,
                using: handler
            )
        )
    }

    private func handleDistributedPlaybackNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let rawState = (userInfo["Player State"] as? String)?.lowercased() ?? ""
        let position = Self.playbackPosition(from: userInfo)

        if !rawState.isEmpty {
            let playing = rawState == "playing"
            guard acceptPlaybackReport(playing) else { return }
            if !playing {
                let pausedAt = position ?? currentElapsed
                elapsedAnchor = pausedAt
                anchorDate = Date()
                displayedElapsed = pausedAt
            } else {
                if let position {
                    elapsedAnchor = position
                }
                anchorDate = Date()
                displayedElapsed = currentElapsed
            }
            isPlaying = playing
            updateLyricActivityTimer()
        }
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
    private static func playbackPosition(from userInfo: [AnyHashable: Any]) -> TimeInterval? {
        for key in ["Playback Position", "Position", "Player Position"] {
            if let value = userInfo[key] as? Double { return value }
            if let value = userInfo[key] as? NSNumber { return value.doubleValue }
        }
        return nil
    }

    /// The dlopen MediaRemoteBridge as the source. Used when the perl-bridge
    /// adapter is not bundled or fails its entitlement test.
    private func armDirectBridge() {
        useAdapter = false
        guard bridge.isAvailable && bridge.supportsQueries else { return }
        useMediaRemote = true
        bridge.registerForNotifications()
        let center = NotificationCenter.default
        mediaNotificationObservers.append(
            center.addObserver(
                forName: MediaRemoteBridge.infoDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refreshFromMediaRemote()
            }
        )
        mediaNotificationObservers.append(
            center.addObserver(
                forName: MediaRemoteBridge.isPlayingDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refreshFromMediaRemote()
            }
        )
        refreshFromMediaRemote()
    }

    /// The perl-bridge adapter as the source: verified functional, so its
    /// stream owns now-playing delivery and the dlopen bridge stays dormant.
    private func armAdapter() {
        useAdapter = true
        useMediaRemote = true
        isSystemNowPlayingRestricted = false
        adapterRestartAttempts = 0
        if Self.syncLogEnabled {
            let allowed = automationIsAllowed()
            let adapterActive = useAdapter
            let fallback = fallbackBundleID
            Self.syncLog?.notice("SYNCLOG init adapter=\(adapterActive ? 1 : 0, privacy: .public) allowed=\(allowed ? 1 : 0, privacy: .public) fallback=\(fallback, privacy: .public)")
        }
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
    private func probePlayersAtLaunch(attemptsLeft: Int, inputs: ScriptInputs) {
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
        if let browserSnap = browserYouTubeSnapshot(
            avoidPrompt: true, musicOwnsSession: inputs.musicOwnsSession
        ) {
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

    /// Re-arms the launch probe.
    ///
    /// The "has anything turned up yet?" test has to happen on the main thread:
    /// `track` and `isPlaying` are `@Observable` storage the main thread
    /// writes, and this used to read both from a background queue. The next
    /// attempt's inputs are captured in the same hop.
    private func scheduleLaunchProbeRetry(attemptsLeft: Int) {
        guard attemptsLeft > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            // Anything already picked up — by MediaRemote or an earlier
            // probe — ends the launch probe.
            guard self.track == nil, !self.isPlaying else { return }
            let inputs = self.captureScriptInputs()
            Self.scriptQueue.async { [weak self] in
                self?.probePlayersAtLaunch(attemptsLeft: attemptsLeft - 1, inputs: inputs)
            }
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

    /// Whether the media surfaces that are on screen right now need live
    /// updates.
    ///
    /// This is separate from `isActive` on purpose. `isActive` means "the
    /// panel is open and the data-heavy modules are awake"; it gates the fast
    /// 10Hz progress tick, the 1s browser probe and the aggressive playback
    /// reconcile. But the Home tab's player and the closed notch's wings are
    /// drawn *without* the panel being open, and they were reading whatever
    /// the last open left behind — a paused track stayed "playing" and a skip
    /// did not land until the notch was next opened. Marking the media
    /// surfaces visible lets them keep a slower heartbeat while still costing
    /// nothing when the notch is idle and nothing media-related is showing.
    private var isVisible = false

    /// Sets both media gates at once and rebuilds the timers to match.
    ///
    /// `active` is the panel being open — the state that earns the fast
    /// cadence; `visible` is any media surface being on screen (the open
    /// panel, the Home tab on a closed notch, or the wings), which earns the
    /// slower heartbeat. They are passed together because they always change
    /// together and rebuilding the timers twice for one change would double
    /// the immediate probes.
    func setMediaPresence(active: Bool, visible: Bool) {
        // Idempotent: the callers fire on every playback and track change, and
        // rebuilding an unchanged cadence would tear down and re-arm the
        // timers — and fire an extra immediate probe — on each of them, which
        // the probes themselves can trigger. Only an actual change rebuilds.
        guard active != isActive || visible != isVisible else { return }
        isActive = active
        isVisible = visible
        rebuildMediaTimers()
    }

    /// (Re)builds the media polling timers to match the current
    /// active/visible state.
    ///
    /// Two cadences run off the same sources. While the panel is open
    /// (`isActive`) everything runs fast, because the scrubber, the lyric
    /// list and the transport are all on screen. While a media surface is
    /// merely visible — the Home tab is the front tab on an unopened notch,
    /// or the wings are showing — the same sources run slowly, just enough to
    /// keep the title, artist, play state and artwork honest without turning
    /// an idle notch into a poller.
    ///
    /// Not *every* timer is gated here: the closed notch still shows the
    /// lyric line, so `updateLyricActivityTimer` runs while closed by
    /// definition and keeps its own 0.1s tick — see `tickCollapsedLyric`.
    private func rebuildMediaTimers() {
        // Every source the method below can arm, armed fresh. Rebuilding to a
        // clean slate is what makes the visible/active change idempotent.
        mediaRemoteRetryWork?.cancel()
        mediaRemoteRetryWork = nil
        progressTimer?.invalidate()
        progressTimer = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        browserProbeTimer?.invalidate()
        browserProbeTimer = nil
        defer { updateLyricActivityTimer() }

        let wantLive = isActive || isVisible

        // Opening the panel puts the lyric list on screen, so the position is
        // worth re-reading at once rather than at the slower closed cadence.
        if isActive { invalidatePlaybackReconcile() }

        // The elapsed-time tick drives the open scrubber, the Home progress
        // bar and the closed-notch lyric highlight. It is the one thing that
        // has to run whenever any of them is on screen, so it is gated on
        // visibility rather than on the panel being open.
        if wantLive {
            progressTimer = Timer.scheduledRepeating(every: 0.1) { [weak self] in
                self?.tickProgress()
            }
            tickProgress()
        }

        guard wantLive else {
            // Idle and closed with nothing media-related showing: the only
            // reason to poll would be to catch a track that starts on its own,
            // and there is nothing on screen to show it on — the notch wakes
            // on the push notification anyway.
            return
        }

        if useMediaRemote {
            refreshFromMediaRemote()
            // A browser probe while nothing is open must not raise the
            // Automation prompt; the panel being open is what makes a prompt
            // acceptable (it is how consent is obtained).
            probeBrowserForPlayingMedia(avoidPrompt: !isActive)
            // While MediaRemote is the source, a browser-derived track needs
            // its own probe to stay honest: MediaRemote never answers for
            // browsers, so nothing else tells us when the tab closes or the
            // video changes. Fast open, slower while the closed notch still
            // shows the wings.
            let browserInterval: TimeInterval = isActive ? 1.0 : 2.5
            browserProbeTimer = Timer.scheduledRepeating(every: browserInterval) { [weak self] in
                self?.tickBrowserProbe()
            }
            tickBrowserProbe()
            // Only worth asking on an open: the demotion gap it closes is one
            // empty reply per open, and the open is where the track appears.
            if isActive { probeFallbackIfMediaRemoteSilent() }
        } else {
            refreshFromAppleScript()
            // The Apple Events path has no push, so the closed notch keeps a
            // slow poll to notice a track change; open, it can afford to be
            // quicker.
            let fallbackInterval: TimeInterval = isActive ? 2.0 : 4.0
            fallbackTimer = Timer.scheduledRepeating(every: fallbackInterval) { [weak self] in
                self?.refreshFromAppleScript()
            }
        }
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
            lyricActivityTimer = Timer.scheduledRepeating(every: 0.1) { [weak self] in
                self?.tickCollapsedLyric()
            }
            tickCollapsedLyric()
        } else {
            lyricActivityTimer?.invalidate()
            lyricActivityTimer = nil
            if collapsedLyric != nil {
                collapsedLyric = nil
            }
        }
    }

    private func tickCollapsedLyric() {
        guard isPlaying, !isBrowserVideo, lyrics.isSynced, !lyrics.lines.isEmpty else {
            if collapsedLyric != nil {
                collapsedLyric = nil
            }
            return
        }
        let elapsed = currentElapsed
        syncLogTick()
        lyrics.updateCurrentLine(for: elapsed)
        // `liveLine`, not `currentIndex` — the closed notch shows one line
        // with nothing around it, so it has to go away when nothing is being
        // sung rather than holding the last line through a break or the outro.
        let line = lyrics.liveLine(at: elapsed + Self.lyricLead)
        if line != collapsedLyric {
            collapsedLyric = line
        }
        reconcilePlaybackIfStale()
    }

    private func tickProgress() {
        syncLogTick()
        displayedElapsed = currentElapsed
        expireStaleScrubPreview()
        // Lyric highlighting must never advance while playback is paused, or
        // while a scrub drag is previewing positions under the thumb.
        guard isPlaying, !isScrubPreviewing else { return }
        // Use the live extrapolated clock, not the stored display copy, so
        // the highlight lands on the timestamp instead of one tick behind.
        // A browser item has no lyrics, but it is the one source whose play
        // state arrives through the same now-playing channel, so it still gets
        // the reconcile — without it a missed pause or resume on YouTube had
        // nothing to correct it.
        if !isBrowserVideo {
            lyrics.updateCurrentLine(for: currentElapsed)
        }
        reconcilePlaybackIfStale()
    }

    /// Safety net against a playback-state desync. The hardware Play/Pause
    /// key pauses the player itself, and Notch only learns of it if a push
    /// notification or MediaRemote callback arrives — which can be missed
    /// (older MediaRemote paths are gated on new macOS). If that happens,
    /// `isPlaying` stays true, the elapsed time keeps extrapolating, and the
    /// lyrics keep advancing through pauses. While lyrics are actually
    /// advancing, periodically re-read the real player (throttled, off-main,
    /// never raising a consent prompt) so a pause freezes the lyrics a moment
    /// later instead of running to the end of the song.
    ///
    /// Deliberately only corrects the playback flag (and, on a pause, the
    /// frozen position) — it never goes through the full snapshot pipeline,
    /// so an unreadable player can never blank a track that is still shown.
    ///
    /// It is also the read-back for a *system* source (a browser video, a
    /// Chrome-app window): those have no DOM or scripted state to trust, so
    /// this reading is the only thing that can tell the notch their playback
    /// really stopped — or really started — while it was showing them.
    private func reconcilePlaybackIfStale() {
        // Open, the scrubber and the lyric list are both on screen and a stale
        // pause is obvious within a second or two. Closed, the only thing this
        // corrects is the one-line lyric activity, so a far slower cadence is
        // enough. While a lyric is actually on the closed notch, a missed
        // pause is visible — the words keep coming — so it is checked sooner.
        //
        // A system source has no lyric to give it away, so while it claims to
        // be playing it keeps the quicker closed cadence; once it claims to be
        // paused, only a resume can be worth catching, which the slow tail is
        // plenty for.
        let interval: TimeInterval
        if isSystemMediaSource {
            interval = isPlaying ? (isActive ? 2 : 5) : 15
        } else {
            interval = isActive ? 2 : (collapsedLyric != nil ? 5 : 15)
        }
        let due = Date().timeIntervalSince(lastPlaybackReconcile) >= interval
        // A command routed through the now-playing channel may have left the
        // optimistic flip standing while the item reads paused; that flip is
        // exactly what the read-back exists to check, so it bypasses both the
        // cadence and the "is anything playing" gate.
        let forced = readBackAfterCommand
        guard forced || isPlaying || isSystemMediaSource, !isReadingAppleScript,
              forced || due
        else { return }
        readBackAfterCommand = false
        lastPlaybackReconcile = Date()

        // Primary probe: the adapter's one-shot `get --now`. On this macOS the
        // stream pushes position updates only while playing — the pause event
        // never arrives, `isPlaying` stays true, and the extrapolated playhead
        // carried the lyrics straight through pauses (measured: 12s+ past a
        // paused Spotify). The `get` verb answers even where the pushes are
        // gated, needs no consent, and reports the playing state correctly
        // across pause/resume — and with `--now` it also reports where the
        // playhead is at query time, which is what heals the clock (see below).
        adapter.getNowPlaying { [weak self] info in
            guard let self else { return }
            guard let info else {
                self.reconcilePlaybackViaAppleScript()
                return
            }
            // Identity guard: only correct our own track. A payload for a
            // different app belongs to the source-switching machinery, not
            // this probe — without it, audio elsewhere could freeze a lyric
            // line or flip the transport of something else. Prefixes count as
            // a match, because the two sides of the same item do not always
            // spell its name the same way (a tab title carries " - YouTube").
            let reportedTitle = Self.normalizedTitle(info[MediaRemoteBridge.InfoKey.title] as? String ?? "")
            let currentTitle = self.track?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard Self.titlesAgree(reportedTitle, currentTitle) else { return }

            let reportedPlaying = (info[MediaRemoteBridge.InfoKey.playbackRate] as? Double)
                .map { $0 > 0 } ?? true
            if !reportedPlaying {
                // A pause the stream never pushed. The frozen position is this
                // side's own extrapolation: while paused the adapter's
                // estimate is the time *since* the pause, not the position it
                // stopped at, so it must not be adopted here.
                let reported = info[MediaRemoteBridge.InfoKey.elapsedTime] as? TimeInterval
                let pausedAt = (reported.flatMap { $0 > 0.5 ? $0 : nil }) ?? self.currentElapsed
                self.elapsedAnchor = pausedAt
                self.displayedElapsed = pausedAt
                self.anchorDate = Date()
                if self.isPlaying, self.acceptPlaybackReport(false) {
                    Self.syncLog?.notice("RECONCILE play 1 → 0 at e=\(pausedAt, format: .fixed(precision: 2), privacy: .public)")
                    self.isPlaying = false
                }
            } else {
                // A resume the stream never pushed. Symmetrical to the pause
                // above, and the case a system source needs most: the transport
                // icon has to stop showing a pause nobody took.
                if !self.isPlaying, self.acceptPlaybackReport(true) {
                    Self.syncLog?.notice("RECONCILE play 0 → 1 at e=\(self.currentElapsed, format: .fixed(precision: 2), privacy: .public)")
                    self.anchorDate = Date()
                    self.isPlaying = true
                    self.updateLyricActivityTimer()
                }
                if let position = Self.livePosition(from: info),
                   position > 0.5,
                   abs(position - self.currentElapsed) > 1.5 {
                    // Playing but the clock has wandered: re-anchor to the
                    // player's real position. This is the healing path for the
                    // "a bit slow" and rewind-loop symptoms — and the one that
                    // catches a launch (or track change) that was anchored to a
                    // zero/stale position, where the lyrics otherwise run a whole
                    // verse behind for the rest of the song. A browser item read
                    // from the tab title has no position at all, so this is also
                    // the first real one it sees.
                    Self.syncLog?.notice("RECONCILE drift e=\(self.currentElapsed, format: .fixed(precision: 2), privacy: .public) → \(position, format: .fixed(precision: 2), privacy: .public)")
                    self.elapsedAnchor = position
                    self.anchorDate = Date()
                    self.displayedElapsed = position
                }
            }
        }
    }

    /// Set by a transport command that was routed through the now-playing
    /// channel, so the next reconcile reads back the state that command was
    /// supposed to produce even when the item currently reads paused.
    private var readBackAfterCommand = false

    /// One read-back shortly after such a command: the optimistic flip is a
    /// guess, and the player's own answer is what the transport should show.
    private func schedulePlaybackReadBack() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.hasTrack else { return }
            self.readBackAfterCommand = true
            self.reconcilePlaybackIfStale()
        }
    }

    /// The legacy reconcile rung: an Apple Events read of the fallback player.
    /// Used when the adapter's `get` is unavailable. Never raises a consent
    /// prompt, and never blanks the track — it only corrects the play state.
    private func reconcilePlaybackViaAppleScript() {
        // Only ever about a player the notch can read directly. This rung has
        // no identity check of its own (the adapter path does), so pointed at a
        // browser video or a Chrome-app window it would adopt a *player's*
        // state for media that is not the player's.
        guard musicPlayerOwnsSource, automationIsAllowed() else { return }
        isReadingAppleScript = true

        let inputs = captureScriptInputs()
        Self.scriptQueue.async { [weak self] in
            let snapshot = self?.appleScriptSnapshot(inputs)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isReadingAppleScript = false
                guard let snapshot else { return }
                if !snapshot.isPlaying {
                    self.elapsedAnchor = snapshot.elapsed
                    self.displayedElapsed = snapshot.elapsed
                    self.anchorDate = Date()
                }
                if snapshot.isPlaying != self.isPlaying {
                    Self.syncLog?.notice("RECONCILE play \(self.isPlaying ? 1 : 0, privacy: .public) → \(snapshot.isPlaying ? 1 : 0, privacy: .public) at e=\(self.currentElapsed, format: .fixed(precision: 2), privacy: .public)")
                    guard self.acceptPlaybackReport(snapshot.isPlaying) else { return }
                    self.isPlaying = snapshot.isPlaying
                    self.updateLyricActivityTimer()
                }
            }
        }
    }

    /// When the last time we re-read the real player to catch a missed pause,
    /// or to put a wandered clock back on the playhead.
    private var lastPlaybackReconcile = Date.distantPast

    /// The freshest position a `get --now` reply carries.
    ///
    /// `elapsedTimeNow` is preferred because it is computed when the query is
    /// answered, so it describes the playhead *now*. The elapsed/timestamp
    /// pair is the fallback — it is only a position if the player actually
    /// refreshed its state recently, and Spotify leaves `elapsedTime` at zero
    /// and republishes the pair on state changes only, so a stream can hold
    /// "0 at t" from before the current position for the whole song.
    private static func livePosition(from info: [String: Any]) -> TimeInterval? {
        if let now = info[MediaRemoteBridge.InfoKey.elapsedTimeNow] as? TimeInterval,
           now > 0.5 {
            return now
        }
        return info[MediaRemoteBridge.InfoKey.elapsedTime] as? TimeInterval
    }

    /// Makes the next tick re-read the player instead of waiting out the
    /// cadence: called when the position is known to be suspect — a song just
    /// started, playback just started, or the notch just opened onto the
    /// lyric list.
    private func invalidatePlaybackReconcile() {
        lastPlaybackReconcile = .distantPast
    }

    // TEMPORARY sync-verification logging (NOTCH_SYNC_LOG=1 env or arg). Remove after testing.
    private static let syncLogEnabled = ProcessInfo.processInfo.environment["NOTCH_SYNC_LOG"] != nil
        || CommandLine.arguments.contains("NOTCH_SYNC_LOG=1")
    private static let syncLog: Logger? = syncLogEnabled ? Logger(subsystem: "com.notchapp.Notch", category: "synclog") : nil
    private var lastSyncLoggedSecond: Int = -1
    private func syncLogTick() {
        guard Self.syncLogEnabled else { return }
        let sec = Int(currentElapsed)
        guard sec != lastSyncLoggedSecond else { return }
        lastSyncLoggedSecond = sec
        let idxText = lyrics.currentIndex.map(String.init) ?? "nil"
        let lineText = lyrics.currentLine.map { "[\(String(format: "%05.2f", $0.time))] \($0.text)" } ?? "—"
        let peekText = collapsedLyric.map { "[\(String(format: "%05.2f", $0.start))]" } ?? "none"
        Self.syncLog?.notice("SYNCLOG e=\(self.currentElapsed, format: .fixed(precision: 2)) play=\(self.isPlaying ? 1 : 0, privacy: .public) idx=\(idxText, privacy: .public) peek=\(peekText, privacy: .public) line=\(lineText, privacy: .public)")
    }

    // MARK: - Transport controls

    /// Where a transport command should go. Resolved once so the four
    /// controls (play/pause, next, previous, seek) share one priority ladder
    /// instead of four copies that can drift:
    ///
    /// Every AppleScript rung is additionally gated on Apple Events consent for
    /// the app it would drive, because "the player is running" is not the same
    /// question as "the player will obey". Without consent an AppleScript
    /// command raises no prompt and changes nothing — it returns
    /// `errAEEventNotPermitted` — and the media-key fallback behind it needs a
    /// *different* grant (Accessibility). So the ladder used to spend every
    /// command on a rung that could not work and then on a fallback that could
    /// not either, while the player sat there running: the play/pause button
    /// flipped its icon and nothing else happened. Ungranted players now fall
    /// through to the MediaRemote rung, which needs no permission at all.
    ///
    /// 1. The music player that owns the session on screen, when we may script
    ///    it (by the now-playing app, then the selected provider, then
    ///    whichever player is running) — never a player that merely happens to
    ///    be open while something else is playing.
    /// 2. Browser media (YouTube, web videos) — only when no music player
    ///    is active.
    /// 3. The selected provider's own AppleScript app, when it has one.
    /// 4. Automatic detection from the now-playing app's bundle id.
    /// 5. Any running Spotify, then any running Music, as a last resort.
    /// 6. The system fallback (adapter, MediaRemote, media keys).
    private enum TransportTarget {
        case provider(appName: String, command: String)
        case browser
        case system
    }

    /// Whether Apple Events to `bundleID` are allowed. Cached and never
    /// blocking (see `AutomationConsent`), so it is safe to ask on the way
    /// through a button press.
    private func canScript(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        return IntegrationPermissions.isAutomationAllowed(bundleID)
    }

    /// Whether the item on screen belongs to a dedicated music player — the
    /// two apps the notch can drive directly. This is the question every
    /// transport rung and the provider filter actually mean by "the player
    /// owns the session"; the answer is read off the source app, so media from
    /// anywhere else (a browser video, a Chrome-app window, a video player)
    /// is never mistaken for the player's own and never has a command aimed at
    /// a player that is merely running alongside it.
    ///
    /// With no resolved source app, it answers true while nothing is on
    /// screen: that is the state in which the selected provider is the sensible
    /// target (pressing play starts it) rather than a session being hijacked.
    ///
    /// Read by the player UI too: the controls that drive an app directly
    /// (shuffle, the heart) belong to the player's own media, and must not be
    /// shown for a video the player has nothing to do with.
    var musicPlayerOwnsSource: Bool {
        guard let bundle = sourceAppBundleID else { return !hasTrack }
        return Self.musicPlayerBundleIDs.contains(bundle)
    }

    /// True while the item on screen comes from an app whose playback the notch
    /// can only observe through the now-playing channel — a browser video, a
    /// Chrome-app ("YouTube") window, any other player. Their state has to be
    /// read back rather than driven, so they earn the reconcile's faster
    /// cadence and are never handed to the Apple Events fallback.
    private var isSystemMediaSource: Bool {
        guard hasTrack else { return false }
        return isBrowserVideo || !musicPlayerOwnsSource
    }

    private func resolveTransportTarget(providerCommand: String) -> TransportTarget {
        let spotifyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.spotify.bundleID).isEmpty
        let musicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: MusicProvider.appleMusic.bundleID).isEmpty
        let spotifyScriptable = spotifyRunning && canScript(MusicProvider.spotify.bundleID)
        let musicScriptable = musicRunning && canScript(MusicProvider.appleMusic.bundleID)

        // 1. If the session on screen belongs to a music player and we are
        //    allowed to drive it, prioritize controlling that player.
        //
        //    `musicPlayerOwnsSource` is what keeps this from firing for media
        //    that is not the player's. It used to be `!isBrowserVideo` alone,
        //    which only guarded scriptable browsers — so a YouTube window
        //    (including the Chrome-app "YouTube" that macOS reports as its own
        //    now-playing client) was handed to whatever player was running and
        //    scriptable, and the notch's play/pause paused Spotify while the
        //    video kept playing.
        if musicPlayerOwnsSource, (spotifyScriptable || musicScriptable) {
            if let bundle = sourceAppBundleID {
                if bundle == MusicProvider.spotify.bundleID, spotifyScriptable {
                    return .provider(appName: "Spotify", command: providerCommand)
                } else if bundle == MusicProvider.appleMusic.bundleID, musicScriptable {
                    return .provider(appName: "Music", command: providerCommand)
                }
            }
            if selectedProvider == .spotify && spotifyScriptable {
                return .provider(appName: "Spotify", command: providerCommand)
            } else if selectedProvider == .appleMusic && musicScriptable {
                return .provider(appName: "Music", command: providerCommand)
            }
            if spotifyScriptable {
                return .provider(appName: "Spotify", command: providerCommand)
            } else if musicScriptable {
                return .provider(appName: "Music", command: providerCommand)
            }
        }

        // 2. Browser media (YouTube, web videos) — only when no music player is
        //    active, and only for a browser we are allowed to script: playing a
        //    page means Apple Events to the browser, so this rung has exactly
        //    the same problem as the players. Ungranted, it falls through to
        //    the MediaRemote rung, which drives the browser's own now-playing
        //    session without any consent.
        if isBrowserVideo || isShowingBrowserSnapshot,
           Self.browserTargets.contains(where: { browser in
               canScript(browser.bundleID)
                   && !NSRunningApplication
                       .runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
           }) {
            return .browser
        }

        // 3. Specific Selected Provider.
        //    Media that belongs to something else is never re-routed to a music
        //    player here: the selected provider is a fallback for *its own*
        //    media — starting it when nothing is playing — not a way to hand a
        //    web video or another app's item to Music/Spotify, which would fire
        //    the command at an app that is not what the user is looking at.
        //    Ungranted, the command falls through to the MediaRemote rung.
        if musicPlayerOwnsSource,
           let provider = selectedProvider.appleScriptAppName,
           canScript(selectedProvider.bundleID) {
            return .provider(appName: provider, command: providerCommand)
        }

        // 4. Automatic provider detection
        if let bundle = sourceAppBundleID {
            if bundle == MusicProvider.spotify.bundleID, canScript(bundle) {
                return .provider(appName: "Spotify", command: providerCommand)
            } else if bundle == MusicProvider.appleMusic.bundleID, canScript(bundle) {
                return .provider(appName: "Music", command: providerCommand)
            } else if Self.browserTargets.contains(where: { $0.bundleID == bundle }),
                      canScript(bundle) {
                return .browser
            }
        }

        // 5. Last resort: any running player we may script — again never for
        //    media that belongs to something else, so a web video (or a
        //    Chrome-app window) with no scriptable browser lands on the
        //    MediaRemote rung and its own now-playing session.
        if musicPlayerOwnsSource, spotifyScriptable {
            return .provider(appName: "Spotify", command: providerCommand)
        }
        if musicPlayerOwnsSource, musicScriptable {
            return .provider(appName: "Music", command: providerCommand)
        }

        return .system
    }

    /// Whether a resolved target has any chance of reaching a player.
    ///
    /// The provider and browser rungs carry their own fallbacks, and the system
    /// rung has three (the MediaRemote adapter, the dlopen bridge, a synthetic
    /// media key) — of which only the last needs a grant. With no MediaRemote
    /// source armed *and* no Accessibility trust, a command would be a no-op
    /// with nowhere to report itself, so the controls leave the UI alone
    /// instead of showing a state the player never entered.
    private func transportIsDeliverable(_ target: TransportTarget) -> Bool {
        switch target {
        case .provider, .browser: return true
        case .system: return useAdapter || useMediaRemote || AXIsProcessTrusted()
        }
    }

    /// A transport command delivered through the system now-playing channel
    /// rather than to a named app.
    ///
    /// One ladder for all three controls so they cannot drift apart: the
    /// perl-bridge adapter first (entitled, no consent needed, and what the
    /// hardware media keys amount to), the dlopen bridge on ungated macOS,
    /// then a synthetic media key — the only rung that needs Accessibility.
    /// The key is also the rung that fails silently without it, so it is
    /// deliberately last.
    private enum SystemTransport {
        case togglePlayPause
        case nextTrack
        case previousTrack
    }

    private func sendSystemTransport(_ command: SystemTransport) {
        // Whatever the command reached (or failed to reach) reports through
        // this channel, so the next second's read-back is what turns the
        // optimistic icon into the player's real state — the half of the
        // toggle a browser with JavaScript-through-AppleScript switched off
        // could previously never answer.
        schedulePlaybackReadBack()
        switch command {
        case .togglePlayPause:
            if useAdapter {
                adapter.sendCommand(.togglePlayPause)
            } else if useMediaRemote {
                bridge.send(.togglePlayPause)
            } else {
                SystemMediaKeySender.togglePlayPause()
            }
        case .nextTrack:
            if useAdapter {
                adapter.sendCommand(.nextTrack)
            } else if useMediaRemote {
                bridge.send(.nextTrack)
            } else {
                SystemMediaKeySender.nextTrack()
            }
        case .previousTrack:
            if useAdapter {
                adapter.sendCommand(.previousTrack)
            } else if useMediaRemote {
                bridge.send(.previousTrack)
            } else {
                SystemMediaKeySender.previousTrack()
            }
        }
    }

    func togglePlayPause() {
        let target = resolveTransportTarget(providerCommand: isPlaying ? "pause" : "play")
        // Resolve (and rule out) the route *before* flipping anything: the
        // optimistic state used to be the only thing a doomed command changed.
        guard transportIsDeliverable(target) else { return }

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
        // Filter conflicting playback reports until one confirms this toggle.
        armOptimisticWindow(newState)

        switch target {
        case let .provider(appName, command):
            runProviderCommand(appName: appName, command: command)
        case .browser:
            toggleBrowserPlayback()
        case .system:
            sendSystemTransport(.togglePlayPause)
        }
    }

    func nextTrack() {
        guard beginSkip() else { return }
        switch resolveTransportTarget(providerCommand: "next track") {
        case let .provider(appName, command):
            runProviderCommand(appName: appName, command: command)
        case .browser:
            nextBrowserTrack()
        case .system:
            sendSystemTransport(.nextTrack)
        }
    }

    func previousTrack() {
        guard beginSkip() else { return }
        switch resolveTransportTarget(providerCommand: "previous track") {
        case let .provider(appName, command):
            runProviderCommand(appName: appName, command: command)
        case .browser:
            previousBrowserTrack()
        case .system:
            sendSystemTransport(.previousTrack)
        }
    }

    /// Shared preamble for a skip: refuse a command that has nowhere to go,
    /// and open the optimistic window so the *pause* a player reports while
    /// it swaps tracks is not mistaken for the user pausing.
    ///
    /// A skip lands on a track that is, by definition, playing. Players push a
    /// stale now-playing diff around the switch — often the paused end-of-track
    /// state — and without the window that diff flips the transport icon and,
    /// on the browser/Apple Events paths, freezes the extrapolated clock. That
    /// is the "skipping pauses the song" symptom: the skip itself worked, but
    /// the icon (and sometimes the perceived state) read paused for a beat.
    /// The window keeps `isPlaying` true and ends as soon as a report agrees.
    private func beginSkip() -> Bool {
        guard transportIsDeliverable(resolveTransportTarget(providerCommand: "next track")) else {
            return false
        }
        armOptimisticWindow(true)
        return true
    }

    /// While true, the scrubber is being dragged and the lyric highlight is
    /// being driven by the thumb (`previewScrub`), not the playhead. The
    /// 0.1s progress tick must not fight it.
    private var isScrubPreviewing = false

    /// When the last preview event arrived. The flag must be able to clear
    /// itself: a drag that ends outside the panel collapses it mid-gesture,
    /// SwiftUI cancels the gesture, and `onEnded` never runs — an endlessly
    /// stuck flag froze the highlight at the previewed line while the song
    /// played on. One beat without a fresh event ends the preview.
    private var lastScrubEventAt: Date?
    private static let scrubPreviewStaleAfter: TimeInterval = 1.2

    /// Live scrub preview: moves the open player's lyric highlight to the
    /// position under the thumb as the drag moves, without touching playback.
    /// Real-time only — the song keeps playing from where it was.
    func previewScrub(to seconds: TimeInterval) {
        guard lyrics.isSynced, !lyrics.lines.isEmpty else { return }
        isScrubPreviewing = true
        lastScrubEventAt = Date()
        lyrics.updateCurrentLine(for: seconds)
    }

    /// Ends the preview. The highlight snaps to wherever the seek landed
    /// (`seek` writes the line itself); if the seek was refused, the next
    /// progress tick re-syncs the highlight to the untouched playhead.
    func endScrubPreview() {
        isScrubPreviewing = false
        lastScrubEventAt = nil
    }

    /// Clears the preview flag when no drag event has arrived for a beat —
    /// the gesture-cancelled case above. Cheap, and self-healing wherever
    /// the stickiness happens.
    private func expireStaleScrubPreview() {
        guard isScrubPreviewing,
              let last = lastScrubEventAt,
              Date().timeIntervalSince(last) > Self.scrubPreviewStaleAfter
        else { return }
        endScrubPreview()
    }

    /// Jumps playback to an absolute position (scrubber drag or lyric tap).
    func seek(to seconds: TimeInterval) {
        // Clamp to the track's length when known; otherwise allow any
        // non-negative position (the player clamps on its side).
        let duration = track?.duration ?? 0
        let clamped = duration > 0 ? max(0, min(seconds, duration)) : max(0, seconds)

        let target = resolveTransportTarget(providerCommand: "set player position to \(Int(clamped))")
        // Same rule as the play button: a position the player was never told
        // about must not move the scrubber, the lyric line or the remaining
        // time. A scrub that cannot be delivered is better refused than faked.
        guard transportIsDeliverable(target) else {
            // A refused scrub leaves the thumb's previewed line on screen
            // while the playhead never moved — hand the highlight straight
            // back so the lyrics don't claim a position the song isn't at.
            lyrics.updateCurrentLine(for: currentElapsed)
            return
        }

        elapsedAnchor = clamped
        anchorDate = Date()
        displayedElapsed = clamped
        lyrics.updateCurrentLine(for: clamped)

        switch target {
        case let .provider(appName, command):
            runProviderCommand(appName: appName, command: command)
        case .browser:
            seekBrowser(to: clamped)
        case .system:
            if useAdapter {
                adapter.seek(to: clamped)
            } else if useMediaRemote, bridge.canSeek {
                bridge.setElapsedTime(clamped)
            } else {
                runMusicCommand("set player position to \(Int(clamped))")
            }
        }
    }

    // MARK: - Optimistic toggle window

    /// After a user-initiated play/pause toggle, playback reports that
    /// conflict with the optimistic state are ignored until one confirms it.
    /// Players push stale now-playing diffs for a beat after a command — the
    /// pre-toggle snapshot from the MediaRemote stream, a browser DOM read
    /// that has not flipped yet — and those used to snap the transport icon
    /// back and forth (pause → play → pause). The window ends the moment a
    /// report agrees with the optimistic state or after it lapses.
    private var optimisticPlaying: Bool?
    private var optimisticWindowUntil: Date?

    private func armOptimisticWindow(_ state: Bool) {
        optimisticPlaying = state
        optimisticWindowUntil = Date().addingTimeInterval(0.7)
    }

    /// Gateway for every playback-state report coming from the media sources
    /// (MediaRemote stream, browser probe, distributed notifications).
    /// Returns false — and the caller drops the write — when a report
    /// contradicts an in-flight user toggle and is therefore stale.
    private func acceptPlaybackReport(_ reported: Bool) -> Bool {
        guard let optimistic = optimisticPlaying,
              let until = optimisticWindowUntil
        else {
            optimisticPlaying = nil
            optimisticWindowUntil = nil
            return true
        }
        if Date() >= until || reported == optimistic {
            optimisticPlaying = nil
            optimisticWindowUntil = nil
            return true
        }
        return false
    }

    /// Sets `isPlaying` from an authoritative source (e.g. the toggle script's
    /// return value) and keeps the elapsed anchor consistent with the new
    /// state — freezing the position on pause, resetting the clock on resume.
    private func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        if playing {
            anchorDate = Date()
        } else {
            elapsedAnchor = currentElapsed
            anchorDate = Date()
        }
        displayedElapsed = currentElapsed
        // The toggle script's answer is the authoritative post-toggle state:
        // rebase the window on it so later conflicting pushes are still
        // filtered, but now against what the player really did.
        armOptimisticWindow(playing)
        isPlaying = playing
        updateLyricActivityTimer()
    }

    /// Toggles browser playback through AppleScript, trusting the *state* the
    /// page reports back.
    ///
    /// This mirrors `browserTransport`'s discipline so the two browser command
    /// paths behave the same. The synthetic media key is a system-wide command
    /// delivered to whatever macOS treats as the now-playing app — which is not
    /// necessarily the browser, and never the tab we just scripted — so firing
    /// it as a blanket fallback double-delivers the toggle (the page flips, then
    /// the key flips whatever was actually playing). The key is therefore posted
    /// only when a tab we can see is ours answered the script *cleanly* with "no
    /// control here", and only when no music player owns the session (if one is
    /// running, the key would go to it instead — exactly the duplicate to avoid).
    private func toggleBrowserPlayback() {
        // `#movie_player` is the desktop YouTube player and exposes a reliable
        // state; the bare `video` element is the fallback and also covers
        // YouTube Music, whose player is a plain HTML5 video.
        let js = "(function(){var p=document.querySelector('#movie_player');if(p&&p.getPlayerState){if(p.getPlayerState()===1){p.pauseVideo();return 'paused';}else{p.playVideo();return 'playing';}}var v=document.querySelector('video');if(v){if(v.paused){v.play();return 'playing';}else{v.pause();return 'paused';}}return 'none';})();"

        for browser in Self.browserTargets {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { continue }
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
                guard error == nil,
                      let res = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                else { continue }
                if res == "playing" || res == "paused" {
                    // The toggle script returned the authoritative post-toggle
                    // state, so set `isPlaying` from it directly rather than
                    // re-reading the DOM — that read races the player's own
                    // state transition (YouTube's getPlayerState() takes a beat
                    // to flip after pauseVideo()), and the periodic probe still
                    // catches any genuine drift. Stop here: going on to the next
                    // browser would toggle a second time.
                    setPlaying(res == "playing")
                    // The script's answer is the page's own, but it can be
                    // optimistic — a `play()` the page's autoplay policy never
                    // honoured still reports 'playing'. One read-back keeps the
                    // transport honest instead of leaving the claim standing.
                    schedulePlaybackReadBack()
                    return
                }
                if res == "none" {
                    // Our tab, but this page exposes no player we can drive.
                    // The system channel is the fallback here, not a duplicate.
                    break
                }
            }
        }

        sendBrowserFallback(.togglePlayPause)
    }

    /// Selector set for the "next" control, newest first.
    ///
    /// YouTube Music is the reason this is a list: it has no `.ytp-next-button`
    /// (that is the desktop YouTube player) and its paper-icon button does not
    /// always carry a plain `.next-button` class — so the old two-selector query
    /// matched nothing, returned `none`, and the caller fell through to a
    /// synthetic media key. `ytmusic-player-bar` is the one stable hook.
    private static let nextButtonSelectors = [
        ".ytp-next-button",
        "ytmusic-player-bar .next-button",
        "tp-yt-paper-icon-button.next-button",
        "button.next-button"
    ]

    private static let previousButtonSelectors = [
        ".ytp-prev-button",
        "ytmusic-player-bar .previous-button",
        "tp-yt-paper-icon-button.previous-button",
        "button.previous-button"
    ]

    private func nextBrowserTrack() {
        browserTransport(
            selectors: Self.nextButtonSelectors,
            fallbackScript: nil,
            systemCommand: .nextTrack
        )
    }

    private func previousBrowserTrack() {
        browserTransport(
            selectors: Self.previousButtonSelectors,
            // Restart the video when there is no previous-track control
            // (plain YouTube, where "previous" means "back to the start").
            fallbackScript: "var v=document.querySelector('video');if(v){v.currentTime=0;return 'reset';}",
            systemCommand: .previousTrack
        )
    }

    /// The last rung of a browser transport command, reached when no browser
    /// tab acted on the Apple Events path.
    ///
    /// JavaScript through Apple Events is off unless it is switched on in the
    /// browser's own Develop menu, so this is a routine case rather than an
    /// error case — and it used to end at a synthetic media key that needs
    /// Accessibility, which meant the button flipped its icon and nothing else
    /// happened. The system now-playing channel reaches the browser's media
    /// session with no consent at all (it is what the hardware key amounts to),
    /// so it is the fallback; the raw key stays the last resort for a Mac where
    /// no MediaRemote source is armed.
    private func sendBrowserFallback(_ command: SystemTransport) {
        guard !isMusicConnectedOrActive else { return }
        if useAdapter || useMediaRemote {
            sendSystemTransport(command)
        } else {
            switch command {
            case .togglePlayPause: SystemMediaKeySender.togglePlayPause()
            case .nextTrack: SystemMediaKeySender.nextTrack()
            case .previousTrack: SystemMediaKeySender.previousTrack()
            }
        }
    }

    /// Drives a browser's next/previous control through AppleScript, falling
    /// back to the system channel only when a browser genuinely could not act.
    ///
    /// The fallback is *system-wide*: macOS delivers it to whatever it
    /// currently considers the now-playing app, which is not necessarily the
    /// browser we just scripted — and never the tab we scripted. Firing it as a
    /// blanket fallback meant a skip that half-worked (the browser was found but
    /// its button query missed, e.g. YouTube Music) landed a second command on
    /// whatever was actually playing, which read as the song pausing. So it is
    /// sent only when a browser tab that is genuinely showing media answered a
    /// script *cleanly* with "no control here" — a page we can see is ours but
    /// cannot drive.
    ///
    /// A music player that owns the session is never overridden: if one is
    /// playing, the command would go to it rather than the browser, which is
    /// exactly the double-delivery this avoids.
    private func browserTransport(
        selectors: [String],
        fallbackScript: String?,
        systemCommand: SystemTransport
    ) {
        let selectorJS = selectors.map { "document.querySelector('\($0)')" }.joined(separator: "||")
        var body = "(function(){var btn=\(selectorJS);if(btn){btn.click();return 'clicked';}"
        if let fallbackScript {
            body += fallbackScript
        }
        body += "return 'none';})();"
        let js = body

        for browser in Self.browserTargets {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { continue }
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
                guard error == nil,
                      let res = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                else { continue }
                if res == "clicked" || res == "reset" {
                    // A browser acted on the command. Stop here: going on to
                    // the next browser would skip a second time.
                    return
                }
                if res == "none" {
                    // The script ran against a matching tab and reported that
                    // this page has no such control — the one case where the
                    // system channel is the fallback rather than a duplicate.
                    break
                }
            }
        }

        sendBrowserFallback(systemCommand)
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

    /// The media source `openSourceApp()` would open, or nil when there is
    /// nothing to open.
    var openableSourceName: String? {
        if isBrowserVideo, sourceMediaURL != nil { return "YouTube video" }
        if let sourceAppName { return sourceAppName }
        return hasTrack ? controlAppName : nil
    }

    /// Brings the browser tab that owns the current YouTube item to the front;
    /// otherwise brings the app the music is coming from to the front.
    func openSourceApp() {
        if isBrowserVideo {
            if let bundleID = sourceAppBundleID,
               let browser = Self.browserTargets.first(where: { $0.bundleID == bundleID }),
               let sourceMediaURL {
                focusBrowserTab(browser, matching: sourceMediaURL)
            } else if let bundleID = sourceAppBundleID,
                      let running = NSRunningApplication
                        .runningApplications(withBundleIdentifier: bundleID).first {
                running.activate()
            }
            return
        }

        guard let bundleID = sourceAppBundleID ?? (hasTrack ? controlBundleID : nil) else {
            return
        }
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Selects the already-open tab that owns this video. Opening its URL via
    /// NSWorkspace can create another tab, which loses the active playback
    /// session and may restart the video.
    private func focusBrowserTab(_ browser: BrowserTarget, matching mediaURL: URL) {
        guard let runningApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: browser.bundleID).first else { return }
        guard IntegrationPermissions.isAutomationAllowed(browser.bundleID) else {
            runningApp.activate()
            return
        }

        let targetURL = Self.appleScriptStringLiteral(mediaURL.absoluteString)
        let videoID = Self.extractYouTubeVideoID(from: mediaURL.absoluteString) ?? ""
        let videoMatchers = ["v=", "youtu.be/", "shorts/", "live/", "embed/"]
            .map { "u contains \(Self.appleScriptStringLiteral($0 + videoID))" }
            .joined(separator: " or ")
        let tabMatches = videoID.isEmpty
            ? "u is \(targetURL)"
            : "(u is \(targetURL)) or ((u contains \(Self.appleScriptStringLiteral("youtube.com/")) or u contains \(Self.appleScriptStringLiteral("youtu.be/")) ) and (\(videoMatchers)))"
        let selection: String
        if browser.isChromium {
            selection = """
                set active tab index of w to ti
                set index of w to 1
                """
        } else {
            selection = """
                set current tab of w to t
                set index of w to 1
                """
        }
        let scriptSource = """
            tell application "\(browser.name)"
                repeat with wi from 1 to (count of windows)
                    set w to window wi
                    repeat with ti from 1 to (count of tabs of w)
                        set t to tab ti of w
                        set u to URL of t as text
                        if \(tabMatches) then
                            \(selection)
                            activate
                            return "activated"
                        end if
                    end repeat
                end repeat
                activate
                return "not-found"
            end tell
            """

        Self.scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: scriptSource)?.executeAndReturnError(&error)
            guard error == nil, result?.stringValue == "activated" else {
                DispatchQueue.main.async {
                    runningApp.activate()
                }
                return
            }
        }
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private var controlAppIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: controlBundleID).isEmpty
    }

    /// Whether the heart can do anything for the player that is playing.
    ///
    /// Only Music has a favourite this app can set. Spotify's saved-songs
    /// library is Web API only, and there is no account to reach it with.
    var canFavorite: Bool {
        hasTrack && controlBundleID == "com.apple.Music"
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

        // Nothing else to write to.
        isFavorite = !wanted
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
        let bundleID = controlBundleID

        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Consent is read here rather than on the main thread even though
            // the check no longer blocks: this runs on every track change, and
            // the main thread is the one thing that must never be behind a
            // permission lookup.
            guard running, IntegrationPermissions.isAutomationAllowed(bundleID) else { return }
            let shuffle = Self.scriptString(shuffleScript) == "true"
            let loved = lovedScript.map { Self.scriptString($0) == "true" }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isShuffling != shuffle { self.isShuffling = shuffle }
                if let loved, self.isFavorite != loved { self.isFavorite = loved }
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
        let inputs = captureScriptInputs()

        Self.scriptQueue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)

            // A synthetic media key only when the player was never there to
            // receive the Apple Event. The media key goes to whatever macOS
            // currently treats as the now-playing app, *not* the app we
            // resolved — so posting it after a script that failed for some
            // other reason (the app ignored the event, a transient timeout,
            // a consent refusal) double-delivers the command: the player acts
            // on the script, then the key hits the real now-playing app and
            // toggles/skips it a second time. That second key is what made
            // Skip read as "the song paused": the skip landed, then the key
            // toggled whatever was actually playing. If the player is running,
            // the script is the whole command; the retry machinery and the
            // per-command read-back cover a genuinely ignored event.
            if error != nil && !isRunning {
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
            let snapshot = self?.appleScriptSnapshot(inputs)

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
                // The hardware pause key can arrive as a state notification
                // even when the reported value matches our optimistic state.
                // Always re-anchor and refresh the lyric timer so a paused
                // player cannot leave lyric activity running.
                guard self.acceptPlaybackReport(playing) else { return }
                if !playing {
                    self.elapsedAnchor = self.currentElapsed
                    self.anchorDate = Date()
                } else if !self.isPlaying {
                    self.anchorDate = Date()
                }
                self.isPlaying = playing
                self.updateLyricActivityTimer()
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
        // The app this update is from, resolved *before* anything is committed
        // to the controller's own source identity: a report that is about to be
        // declined must not leave the source pointing at the app it came from.
        let reportedPID = (info[MediaRemoteAdapter.Key.processIdentifier] as? Int).map(Int32.init)
        let reportedBundleID = reportedPID.flatMap {
            NSRunningApplication(processIdentifier: pid_t($0))?.bundleIdentifier
        }
        let reportedPlaying = Self.reportedIsPlaying(info)

        // A reading for the app already on screen updates it — that is how a
        // pause, a new title or an ended video lands. A reading for a
        // *different* app may take the notch over only by playing: a paused tab
        // or a paused player reporting in the background is not a reason to
        // move off what is running.
        //
        // Both directions of this used to be wrong in opposite ways. Browser
        // reports were dropped wholesale while a music player had a track, so
        // with Spotify paused in the background YouTube could never appear,
        // while a paused player could claim the screen anyway — leaving a
        // playing video for a song that was not even running. Following the
        // system's own now-playing session, whoever is actually playing it, is
        // what makes the closed notch switch sources in real time.
        let reportIsAboutShownSource = reportedBundleID == nil
            || reportedBundleID == sourceAppBundleID
            // A session the notch has not seen yet is still the first item of
            // the session, not a claim on somebody else's screen: a paused
            // player whose track nothing else is showing is worth displaying.
            || !hasTrack
        if reportedPlaying != true, !reportIsAboutShownSource {
            return
        }

        if let reportedPID {
            updateSourceApp(pid: reportedPID, reportIsPlaying: reportedPlaying == true)
        }

        if !isShowingBrowserSnapshot {
            sourceMediaURL = nil
        }
        let title = Self.normalizedTitle(info[MediaRemoteBridge.InfoKey.title] as? String ?? "")
        let isBrowser = sourceAppBundleID.map { Self.isBrowserBundle($0) } ?? false
        if !isBrowser {
            sourceMediaURL = nil
        }

        // If MediaRemote reports for a browser without a title, defer to the browser probe.
        if isBrowser && title.isEmpty {
            return
        }

        if isBrowser {
            isShowingBrowserSnapshot = true
            isBrowserVideo = true
            lyrics.clear()
            collapsedLyric = nil
        } else {
            isShowingBrowserSnapshot = false
            isBrowserVideo = false
        }

        // The provider filter is about *players*: it hides another music
        // player's media when a specific provider is selected, and it never
        // hides what is not a player's at all (a browser video, a Chrome-app
        // window, a video player) — the media surfaces exist to follow what is
        // making the sound, and the provider only decides which player the
        // controls drive. Filtered the other way, the adapter's browser report
        // blanked the item the browser probe kept restoring: a flicker every
        // couple of seconds under a provider other than Automatic.
        let sourceIsMusicPlayer = sourceAppBundleID.map { Self.musicPlayerBundleIDs.contains($0) } ?? false
        guard !sourceIsMusicPlayer || providerAllowsCurrentSource() else {
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
        let rawTitle = info[MediaRemoteBridge.InfoKey.title] as? String ?? ""
        newTrack.title = Self.normalizedTitle(rawTitle)
        newTrack.artist = info[MediaRemoteBridge.InfoKey.artist] as? String ?? ""
        newTrack.album = info[MediaRemoteBridge.InfoKey.album] as? String ?? ""
        newTrack.duration = info[MediaRemoteBridge.InfoKey.duration] as? TimeInterval ?? 0

        let isBrowser = sourceAppBundleID.map { bundle in Self.browserTargets.contains(where: { $0.bundleID == bundle }) } ?? false
        if !isBrowser {
            sourceMediaURL = nil
        } else if !newTrack.title.isEmpty, newTrack.title != track?.title {
            // A new browser title invalidates the old link until the browser
            // probe supplies the matching page URL.
            sourceMediaURL = nil
        }
        if isBrowser {
            isShowingBrowserSnapshot = true
            isBrowserVideo = true
            if newTrack.album.isEmpty { newTrack.album = "YouTube" }
            if newTrack.artist.isEmpty { newTrack.artist = "YouTube" }
        }

        if let elapsed = info[MediaRemoteBridge.InfoKey.elapsedTime] as? TimeInterval {
            let timestamp = info[MediaRemoteBridge.InfoKey.timestamp] as? Date ?? Date()
            // A position that has not moved while its capture time has, in the
            // middle of playback, is the player re-reporting where it was: the
            // song has demonstrably gone on since. Adopting such a reading
            // re-anchored the playhead to the old position — the lyric line
            // snapped back to an earlier verse and the remaining time grew — so
            // the extrapolation already running is the better answer. A seek is
            // unaffected: it reports a *different* position.
            let isStaleRepeat = isPlaying
                && abs(elapsed - elapsedAnchor) < 0.05
                && timestamp > anchorDate
            if Self.syncLogEnabled {
                Self.syncLog?.notice("ANCHOR e=\(elapsed, format: .fixed(precision: 2), privacy: .public) anchor=\(self.elapsedAnchor, format: .fixed(precision: 2), privacy: .public) stale=\(isStaleRepeat ? 1 : 0, privacy: .public) t=\(timestamp.timeIntervalSince1970, format: .fixed(precision: 2), privacy: .public) ad=\(self.anchorDate.timeIntervalSince1970, format: .fixed(precision: 2), privacy: .public)")
            }
            if !isStaleRepeat {
                elapsedAnchor = elapsed
                anchorDate = timestamp
            }
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
            if Self.syncLogEnabled, playing != isPlaying {
                Self.syncLog?.notice("APPLY play \(self.isPlaying ? 1 : 0, privacy: .public) → \(playing ? 1 : 0, privacy: .public) rate=\(playbackRate, format: .fixed(precision: 2), privacy: .public) accept=\(self.acceptPlaybackReport(playing) ? 1 : 0, privacy: .public)")
            }
            // A stale diff riding in right after a user toggle must not flip
            // the transport state; the metadata below still applies, so only
            // the playback write is skipped, not the whole update.
            if acceptPlaybackReport(playing) {
                if !playing {
                    // Capture the position before changing `isPlaying`, since
                    // `currentElapsed` otherwise uses the old running state.
                    let pausedAt = currentElapsed
                    elapsedAnchor = pausedAt
                    anchorDate = Date()
                    displayedElapsed = pausedAt
                } else if !isPlaying {
                    anchorDate = Date()
                }
                isPlaying = playing
                updateLyricActivityTimer()
            }
        }

        if let data = info[MediaRemoteBridge.InfoKey.artworkData] as? Data {
            setArtwork(NSImage(data: data), data: data)
            updateAccentIfNeeded(for: data)
        }

        updateTrackIfChanged(newTrack)
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
        // is how consent is obtained. Only an *unconsented* browser needs
        // sparing: probing one that is already allowed costs nothing and is
        // how a browser track keeps showing on the closed notch.
        probeBrowserForPlayingMedia(avoidPrompt: !automationIsAllowed())
        apply([:])
    }

    /// One off-main probe for the selected player and then the browsers, on
    /// an empty MediaRemote reply. The player outranks the browser — the
    /// provider is what the notch controls — so a playing Spotify/Music track
    /// demotes the source on the spot instead of losing to a YouTube tab.
    private func probeBrowserForPlayingMedia(avoidPrompt: Bool) {
        if isMusicConnectedOrActive { return }
        let inputs = captureScriptInputs()
        Self.scriptQueue.async { [weak self] in
            guard let self else { return }
            // With avoidPrompt, consent is pre-checked before any script
            // runs, mirroring the launch probe's rule. With the notch open,
            // running the script against a consented-or-undetermined app is
            // exactly how the Automation prompt gets raised.
            let snapshot: Snapshot?
            if avoidPrompt, !self.automationIsAllowed() {
                snapshot = self.browserYouTubeSnapshot(
                    avoidPrompt: true, musicOwnsSession: inputs.musicOwnsSession
                )
            } else {
                snapshot = self.appleScriptSnapshot(inputs)
                    ?? self.browserYouTubeSnapshot(
                        avoidPrompt: avoidPrompt,
                        musicOwnsSession: inputs.musicOwnsSession
                    )
            }
            guard let snapshot else { return }
            let isPlayer = snapshot.bundleID == self.fallbackBundleID

            DispatchQueue.main.async { [weak self] in
                guard let self, self.useMediaRemote else { return }
                if self.isMusicConnectedOrActive && !isPlayer {
                    return
                }
                if isPlayer {
                    // Only actual playback demotes the source. A player that
                    // answers its state script while *paused* is not "playing
                    // where MediaRemote cannot see it" — demoting on it stopped
                    // the adapter's stream and with it every browser and
                    // Chrome-app source, leaving the notch showing the paused
                    // song while YouTube played.
                    guard snapshot.isPlaying else { return }
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
        guard useMediaRemote else { return }
        // If a dedicated music player is connected or active, don't let browser probe hijack the session
        if isMusicConnectedOrActive {
            return
        }
        let inputs = captureScriptInputs()
        // A probe while the notch is closed must never be what raises the
        // Automation dialog — it is only acceptable while the user is looking
        // at the notch, which is how that consent is obtained.
        let avoidPrompt = !isActive
        Self.scriptQueue.async { [weak self] in
            let snapshot = self?.browserYouTubeSnapshot(
                avoidPrompt: avoidPrompt, musicOwnsSession: inputs.musicOwnsSession
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isMusicConnectedOrActive {
                    return
                }
                guard let snapshot else {
                    // Browser went away (tab closed) — clear only a track that
                    // actually came from the browser probe.
                    if self.isShowingBrowserSnapshot {
                        self.finishClearingTrack()
                    }
                    return
                }
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
        sourceMediaURL = snapshot.mediaURL
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
                self.setArtwork(image, data: data)
                self.updateAccentIfNeeded(for: data)
            }
        }.resume()
    }

    /// Replaces the artwork, bumping `artworkVersion` only when the image
    /// data genuinely changes. Same-data re-sets (the 2s browser probe
    /// re-downloading the same thumbnail, MediaRemote re-pushing the same
    /// payload) keep the version so the views' crossfade fires only on a real
    /// artwork change. When no data is available (the AppleScript fallback)
    /// the image instance itself is the change signal.
    private func setArtwork(_ image: NSImage?, data: Data?) {
        let changed: Bool
        if let data {
            changed = data != lastArtworkData
        } else {
            changed = image !== artwork
        }
        guard changed else { return }
        lastArtworkData = data
        artwork = image
        artworkVersion += 1
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

        let inputs = captureScriptInputs()
        Self.scriptQueue.async { [weak self] in
            guard let snapshot = self?.appleScriptSnapshot(inputs),
                  snapshot.isPlaying
            else { return }
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
        if isActive || isVisible {
            rebuildMediaTimers()
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
    ///
    /// `reportIsPlaying` says whether the report this pid came with claims to be
    /// playing. While a browser-derived item is showing, MediaRemote's idea of
    /// the now-playing app is often stale (the gated bridge answers with an old
    /// client, or with none), which is why the browser snapshot is protected
    /// from it — but a report that says it is *playing* is a source change in
    /// progress, and blocking that left the song which replaced a video carrying
    /// the browser's identity: album "YouTube", artist "YouTube", and a
    /// transport still aimed at Chrome, until something cleared the item
    /// outright.
    private func updateSourceApp(pid: Int32, reportIsPlaying: Bool = false) {
        if isShowingBrowserSnapshot, !reportIsPlaying { return }
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
    private func updateTrackIfChanged(_ newTrack: Track) {
        let previous = track
        guard newTrack != previous else {
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
            refreshShuffleAndFavorite()
        } else {
            lyrics.clear()
            setArtwork(nil, data: nil)
            accent = .white
            accentSourceHash = nil
        }
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

    private static func validatedYouTubeURL(from rawValue: String?) -> URL? {
        guard let rawValue,
              let components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.lowercased()
        else { return nil }
        let isYouTubeHost = host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtu.be"
            || host.hasSuffix(".youtu.be")
        guard isYouTubeHost else { return nil }
        return components.url
    }

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

    /// The playing state a MediaRemote payload reports, or nil when it carries
    /// none. `playbackRate` is the normalized form both sources deliver (the
    /// adapter folds its own `playing` flag into it); the raw flag is read too,
    /// for a payload that arrives without the bridge's key mapping.
    private static func reportedIsPlaying(_ info: [String: Any]) -> Bool? {
        if let rate = info[MediaRemoteBridge.InfoKey.playbackRate] as? Double { return rate > 0 }
        if let rate = info[MediaRemoteBridge.InfoKey.playbackRate] as? NSNumber {
            return rate.doubleValue > 0
        }
        if let playing = info[MediaRemoteAdapter.Key.playing] as? Bool { return playing }
        return nil
    }

    /// A now-playing title with the platform suffixes stripped, so a
    /// MediaRemote reading and a DOM reading of the same item compare equal
    /// ("Song - YouTube" and "Song" are the same video).
    private static func normalizedTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" - YouTube", " - YouTube Music"] where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title
    }

    /// Whether two now-playing titles describe the same item. Prefixes are
    /// accepted as well as equality, because the two sides capture different
    /// amounts of the name — a tab title carries " - YouTube", a media session
    /// does not, and a video's own title often runs on past what the other side
    /// recorded. Short strings are never prefix-matched: "Song" matching
    /// "Song 2" is not safe.
    private static func titlesAgree(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        guard min(a.count, b.count) >= 8 else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    /// The apps whose media is "music" as far as source priority is
    /// concerned — the two players the notch can drive directly.
    private static let musicPlayerBundleIDs: Set<String> = [
        "com.apple.Music",
        MusicProvider.spotify.bundleID
    ]

    private static func isBrowserBundle(_ bundleID: String) -> Bool {
        browserTargets.contains { $0.bundleID == bundleID }
    }

    var isMusicConnectedOrActive: Bool {
        // Music holds the session only while it is *actually playing*. The old
        // test also accepted "a music player is running and has a track", and
        // because a paused Spotify keeps its track, that claimed the session
        // for as long as the player stayed open: YouTube could be playing in
        // Chrome and the notch went on showing the paused song, with the
        // transport aimed at Spotify. A paused player now lets the browser
        // take over the moment it starts playing.
        guard isPlaying, !isBrowserVideo else { return false }
        guard let bundle = sourceAppBundleID else {
            // Playing, with no resolved source app: do not hand a session that
            // is demonstrably making sound to a browser probe.
            return true
        }
        return Self.musicPlayerBundleIDs.contains(bundle)
    }

    private func browserYouTubeSnapshot(
        avoidPrompt: Bool, musicOwnsSession: Bool
    ) -> Snapshot? {
        guard !musicOwnsSession else { return nil }

        var fallbackSnapshot: Snapshot?
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
            let js = "(function(){try{var title=(document.querySelector('h1.ytd-watch-metadata')||document.querySelector('h1')).innerText||document.title;var channel=(document.querySelector('#upload-info #channel-name a')||document.querySelector('ytd-channel-name a')).innerText||'';var p=document.querySelector('#movie_player');var d=p&&p.getDuration?p.getDuration():0;var c=p&&p.getCurrentTime?p.getCurrentTime():0;var id=p&&p.getVideoData?p.getVideoData().video_id:'';var playing=false;try{playing=p&&p.getPlayerState?p.getPlayerState()===1:(function(){var v=document.querySelector('video');return !!v&&!v.paused&&!v.ended;})();}catch(e){}return (playing?'PLAYING||':'PAUSED||')+JSON.stringify({title:title,youtuber:channel,thumbnail:id?'https://img.youtube.com/vi/'+id+'/maxresdefault.jpg':'',sourceURL:location.href,progress:d>0?c/d:0,duration:d,playing:playing});}catch(e){return '';}})();"

            let scriptSource: String
            if browser.isChromium {
                scriptSource = """
                tell application "\(browser.name)"
                    set fallback to ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to title of t
                            if u contains "youtube.com/watch" or u contains "youtu.be" or u contains "music.youtube.com" or u contains "youtube.com/shorts" or u contains "youtube.com/live" or u contains "youtube.com/embed" or n contains " - YouTube" or n contains "YouTube Music" then
                                set candidate to ""
                                try
                                    tell t
                                        set candidate to (execute javascript "\(js)") as text
                                    end tell
                                on error
                                    set candidate to n & "||" & u
                                end try
                                if candidate begins with "PLAYING||" then return text 10 thru -1 of candidate
                                if fallback is "" and candidate begins with "PAUSED||" then
                                    set fallback to text 9 thru -1 of candidate
                                else if fallback is "" and candidate is not "" then
                                    set fallback to candidate
                                end if
                            end if
                        end repeat
                    end repeat
                    return fallback
                end tell
                """
            } else {
                scriptSource = """
                tell application "\(browser.name)"
                    set fallback to ""
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            set n to name of t
                            if u contains "youtube.com/watch" or u contains "youtu.be" or u contains "music.youtube.com" or u contains "youtube.com/shorts" or u contains "youtube.com/live" or u contains "youtube.com/embed" or n contains " - YouTube" or n contains "YouTube Music" then
                                set candidate to ""
                                try
                                    set candidate to (do JavaScript "\(js)" in t) as text
                                on error
                                    set candidate to n & "||" & u
                                end try
                                if candidate begins with "PLAYING||" then return text 10 thru -1 of candidate
                                if fallback is "" and candidate begins with "PAUSED||" then
                                    set fallback to text 9 thru -1 of candidate
                                else if fallback is "" and candidate is not "" then
                                    set fallback to candidate
                                end if
                            end if
                        end repeat
                    end repeat
                    return fallback
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
                // A missing `playing` key is not "paused": the page answered
                // without it, so the reading simply has no state to report.
                let playing = Self.boolValue(json["playing"])
                let snapshot = Snapshot(
                    track: track,
                    elapsed: progress * duration,
                    duration: duration,
                    isPlaying: playing ?? false,
                    bundleID: browser.bundleID,
                    appName: browser.name,
                    artworkURL: thumbnail.isEmpty ? nil : URL(string: thumbnail),
                    mediaURL: Self.validatedYouTubeURL(from: json["sourceURL"] as? String),
                    isBrowser: true,
                    playbackStateKnown: playing != nil
                )
                if snapshot.isPlaying { return snapshot }
                if fallbackSnapshot == nil { fallbackSnapshot = snapshot }
                continue
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
            if fallbackSnapshot == nil {
                fallbackSnapshot = Snapshot(
                    track: track,
                    elapsed: 0,
                    duration: 0,
                    isPlaying: false,
                    bundleID: browser.bundleID,
                    appName: browser.name,
                    artworkURL: artworkURL,
                    mediaURL: Self.validatedYouTubeURL(from: urlString),
                    isBrowser: true,
                    // The tab title says nothing about playback, so this
                    // reading must not claim the video is paused — the
                    // now-playing channel answers that instead, through the
                    // playback reconcile.
                    playbackStateKnown: false
                )
            }
        }
        return fallbackSnapshot
    }

    /// Channel names for video IDs already looked up, so the periodic browser
    /// probe never re-fetches what it has already seen.
    private var channelCache: [String: String] = [:]
    /// Insertion order, so the cache can drop its oldest entry instead of
    /// growing one row per video watched for the life of the process.
    private var channelCacheOrder: [String] = []
    private static let channelCacheCapacity = 128
    private let channelCacheLock = NSLock()

    /// The channel name for a video, via YouTube's oEmbed endpoint (a small
    /// JSON document carrying `author_name`). Returns nil when the fetch fails
    /// — consent walls, rate limiting, offline — and the player then shows
    /// "YouTube" as the artist rather than the channel. Blocking on a cold
    /// miss, so it is only ever called off the main thread, and cached so the
    /// 2s probe never refetches.
    private func channelName(for videoID: String) -> String? {
        channelCacheLock.lock()
        let cached = channelCache[videoID]
        channelCacheLock.unlock()
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

        channelCacheLock.lock()
        if channelCache.updateValue(name, forKey: videoID) == nil {
            channelCacheOrder.append(videoID)
            if channelCacheOrder.count > Self.channelCacheCapacity {
                channelCache.removeValue(forKey: channelCacheOrder.removeFirst())
            }
        }
        channelCacheLock.unlock()
        return name
    }

    /// One reading of a player: what it is playing and where it has got to.
    private struct Snapshot {
        var track: Track
        var elapsed: TimeInterval
        var duration: TimeInterval = 0
        var isPlaying: Bool
        var bundleID: String?
        var appName: String?
        var artworkURL: URL?
        /// The page that owns this browser-derived item, if known.
        var mediaURL: URL? = nil
        /// True for browser snapshots: MediaRemote can't see or confirm them,
        /// they carry no real playback position, and their artwork is a URL.
        var isBrowser = false
        /// False when the reading carries no playback state at all — the
        /// tab-title browser fallback, which has a title and a URL and says
        /// nothing about whether the video is running. Such a reading must not
        /// be able to *assert* "paused": that is what left a playing YouTube
        /// video showing a play button, with the periodic probe re-asserting
        /// it every couple of seconds.
        var playbackStateKnown = true
    }

    /// One reading of the player's state, or nil when it has nothing to say.
    /// Blocking, so it is only ever called on `scriptQueue`.
    private func appleScriptSnapshot(_ inputs: ScriptInputs) -> Snapshot? {
        var targets: [(appName: String, bundleID: String)] = []
        if let bundle = inputs.sourceBundleID {
            if bundle == MusicProvider.spotify.bundleID {
                targets = [("Spotify", MusicProvider.spotify.bundleID), ("Music", "com.apple.Music")]
            } else if bundle == "com.apple.Music" {
                targets = [("Music", "com.apple.Music"), ("Spotify", MusicProvider.spotify.bundleID)]
            }
        }
        if targets.isEmpty {
            if inputs.provider == .spotify {
                targets = [("Spotify", MusicProvider.spotify.bundleID)]
            } else if inputs.provider == .appleMusic {
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
        if let browserSnap = browserYouTubeSnapshot(
            avoidPrompt: true, musicOwnsSession: inputs.musicOwnsSession
        ) {
            return browserSnap
        }

        return nil
    }

    private func apply(_ snapshot: Snapshot) {
        isShowingBrowserSnapshot = snapshot.isBrowser
        isBrowserVideo = snapshot.isBrowser
        sourceMediaURL = snapshot.isBrowser ? snapshot.mediaURL : nil
        if snapshot.isBrowser {
            lyrics.clear()
            collapsedLyric = nil
            // A browser item's source identity is its own; the pid that MediaRemote
            // last named is about a player, not this page.
            sourceAppPID = 0
        }
        if snapshot.playbackStateKnown, !snapshot.isPlaying, isPlaying {
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
        if snapshot.playbackStateKnown, acceptPlaybackReport(snapshot.isPlaying) {
            isPlaying = snapshot.isPlaying
        }

        let isNewTrack = snapshot.track != track
        updateTrackIfChanged(snapshot.track)
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
                    self.setArtwork(image, data: data)
                    self.updateAccentIfNeeded(for: data)
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

        let inputs = captureScriptInputs()
        Self.scriptQueue.async { [weak self] in
            let snapshot = self?.appleScriptSnapshot(inputs)

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
            let inputs = self.captureScriptInputs()
            Self.scriptQueue.async {
                let stillNothing = self.appleScriptSnapshot(inputs) == nil
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
        sourceMediaURL = nil
        track = nil
        setArtwork(nil, data: nil)
        isPlaying = false
        sourceAppBundleID = nil
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
                self.setArtwork(image, data: data)
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
            DispatchQueue.main.async { [weak self] in
                self?.refreshFromAppleScript()
            }
        }
    }
}
