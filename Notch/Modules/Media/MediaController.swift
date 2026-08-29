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

    private var selectedProvider: MusicProvider {
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
    private var useMediaRemote: Bool
    private var mediaRemoteRetryWork: DispatchWorkItem?
    private var progressTimer: Timer?
    private var fallbackTimer: Timer?
    private var lyricActivityTimer: Timer?
    private var pendingClearWork: DispatchWorkItem?
    private var isActive = false

    var hasTrack: Bool {
        track != nil
    }

    /// True when transport controls do something: a track is showing, or a
    /// specific provider is selected — play will launch and start that app.
    var canControlTransport: Bool {
        hasTrack || selectedProvider != .automatic
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
        if bridge.isAvailable && bridge.supportsQueries {
            useMediaRemote = true
        }
        if useMediaRemote {
            bridge.registerForNotifications()
            let center = NotificationCenter.default
            center.addObserver(
                forName: MediaRemoteBridge.infoDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refreshFromMediaRemote()
            }
            center.addObserver(
                forName: MediaRemoteBridge.isPlayingDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refreshFromMediaRemote()
            }
            refreshFromMediaRemote()
        }

        // Read whatever is playing straight away, off the main thread so a
        // slow-to-answer player cannot hold up launch. Without this the notch
        // showed nothing until it was first opened: MediaRemote is push-based
        // and sends nothing until something changes, and where it is gated the
        // Apple Events path only ran while the notch was expanded.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Only when consent is already on file: a probe at launch must not
            // be what raises the Automation dialog.
            guard let bundleID = self?.fallbackBundleID,
                  IntegrationPermissions.isAutomationAllowed(bundleID),
                  let snapshot = self?.appleScriptSnapshot()
            else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.track == nil else { return }
                self.apply(snapshot)
            }
        }
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
        guard lyrics.isSynced, !lyrics.lines.isEmpty else {
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
        lyrics.updateCurrentLine(for: displayedElapsed)
    }

    // MARK: - Transport controls

    func togglePlayPause() {
        if let provider = selectedProvider.appleScriptAppName {
            runProviderCommand(appName: provider, command: "playpause")
        } else if useMediaRemote {
            bridge.send(.togglePlayPause)
        } else {
            runMusicCommand("playpause")
        }
    }

    func nextTrack() {
        if let provider = selectedProvider.appleScriptAppName {
            runProviderCommand(appName: provider, command: "next track")
        } else if useMediaRemote {
            bridge.send(.nextTrack)
        } else {
            runMusicCommand("next track")
        }
    }

    func previousTrack() {
        if let provider = selectedProvider.appleScriptAppName {
            runProviderCommand(appName: provider, command: "previous track")
        } else if useMediaRemote {
            bridge.send(.previousTrack)
        } else {
            runMusicCommand("previous track")
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

        if let provider = selectedProvider.appleScriptAppName {
            runProviderCommand(appName: provider, command: "set player position to \(Int(clamped))")
        } else if useMediaRemote, bridge.canSeek {
            bridge.setElapsedTime(clamped)
        } else {
            runMusicCommand("set player position to \(Int(clamped))")
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

    private func runProviderCommand(appName: String, command: String) {
        guard fallbackAppIsRunning,
              let script = NSAppleScript(source: "tell application \"\(appName)\" to \(command)")
        else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        refreshFromAppleScript()
    }

    // MARK: - MediaRemote source

    private func refreshFromMediaRemote() {
        guard useMediaRemote else { return }
        bridge.nowPlayingInfo { [weak self] info in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
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
        newTrack.title = info[MediaRemoteBridge.InfoKey.title] as? String ?? ""
        newTrack.artist = info[MediaRemoteBridge.InfoKey.artist] as? String ?? ""
        newTrack.album = info[MediaRemoteBridge.InfoKey.album] as? String ?? ""
        newTrack.duration = info[MediaRemoteBridge.InfoKey.duration] as? TimeInterval ?? 0

        elapsedAnchor = info[MediaRemoteBridge.InfoKey.elapsedTime] as? TimeInterval ?? 0
        anchorDate = info[MediaRemoteBridge.InfoKey.timestamp] as? Date ?? Date()

        if let rate = info[MediaRemoteBridge.InfoKey.playbackRate] as? Double {
            let playing = rate > 0
            if playing != isPlaying {
                isPlaying = playing
                updateLyricActivityTimer()
            }
        }

        if let data = info[MediaRemoteBridge.InfoKey.artworkData] as? Data {
            artwork = NSImage(data: data)
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

        useMediaRemote = false
        isSystemNowPlayingRestricted = true
        // Rebuild the timers on the Apple Events path.
        if isActive {
            setActive(true)
        }
    }

    /// Why nothing is showing, when nothing is showing — so the player says
    /// what is actually wrong instead of claiming nothing is playing.
    var emptyStateReason: String? {
        guard track == nil else { return nil }
        if isSystemNowPlayingRestricted {
            return "macOS restricts system-wide now-playing for third-party apps on "
                + "this version. Notch reads \(fallbackAppName) directly; other "
                + "players, browsers included, can't be seen."
        }
        if !bridge.isAvailable {
            return "System-wide now-playing isn't available here. Notch reads "
                + "\(fallbackAppName) directly."
        }
        return nil
    }

    /// Resolves the now-playing app from its PID, once per change.
    private func updateSourceApp(pid: Int32) {
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
            let followers = await SpotifyClient.followers(forArtist: track.artist, token: token)

            await MainActor.run { [weak self] in
                guard let self, self.lastSpotifyLookup == key else { return }
                self.queue = items
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
        guard newTrack != previous else { return }
        track = newTrack.title.isEmpty ? nil : newTrack

        // Announce track-to-track changes, not the initial pickup at launch.
        if let current = track, previous != nil, current.title != previous?.title {
            onTrackChange?(current)
        }
        if let track {
            if NotchSettings.shared.fetchLyrics {
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
    }

    // MARK: - Apple Events fallback (the selected provider)

    /// App name and bundle used by the AppleScript fallback: the chosen
    /// provider, or Music.app for Automatic.
    private var fallbackAppName: String {
        selectedProvider.appleScriptAppName ?? "Music"
    }

    private var fallbackBundleID: String {
        selectedProvider == .automatic ? "com.apple.Music" : selectedProvider.bundleID
    }

    private func stateScript(for appName: String) -> String {
        """
        tell application "\(appName)"
            if player state is stopped then return "stopped"
            set t to current track
            return (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & \
        (duration of t as text) & "||" & (player position as text) & "||" & (player state as text)
        end tell
        """
    }

    private var fallbackAppIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: fallbackBundleID).isEmpty
    }

    /// One reading of the player's state, or nil when it has nothing to say.
    /// Blocking, so it is only called from a background queue or from the
    /// fallback timer, which already runs while the notch is open.
    private struct Snapshot {
        var track: Track
        var elapsed: TimeInterval
        var isPlaying: Bool
    }

    private func appleScriptSnapshot() -> Snapshot? {
        // Never launch a player just to ask what is playing.
        guard fallbackAppIsRunning,
              let script = NSAppleScript(source: stateScript(for: fallbackAppName))
        else { return nil }

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

    private func apply(_ snapshot: Snapshot) {
        elapsedAnchor = snapshot.elapsed
        anchorDate = Date()
        isPlaying = snapshot.isPlaying

        let isNewTrack = snapshot.track != track
        updateTrackIfChanged(snapshot.track)
        updateLyricActivityTimer()

        // MediaRemote hands artwork over with the rest of the info; Apple
        // Events do not, so on this path it has to be asked for separately —
        // otherwise a Mac where MediaRemote is gated never shows a cover.
        if isNewTrack {
            loadFallbackArtwork()
        }

        if sourceAppName == nil,
           let app = NSRunningApplication
               .runningApplications(withBundleIdentifier: fallbackBundleID).first {
            sourceAppName = app.localizedName
            sourceAppIcon = app.icon
        }
    }

    private func refreshFromAppleScript() {
        guard let snapshot = appleScriptSnapshot() else {
            clearTrackAfterGrace()
            return
        }
        pendingClearWork?.cancel()
        pendingClearWork = nil
        apply(snapshot)
    }

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
            // inline here did.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let stillNothing = self?.appleScriptSnapshot() == nil
                DispatchQueue.main.async { [weak self] in
                    guard let self, stillNothing else { return }
                    self.finishClearingTrack()
                }
            }
        }
        pendingClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func finishClearingTrack() {
        track = nil
        artwork = nil
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

    private func runMusicCommand(_ command: String) {
        guard fallbackAppIsRunning,
              let script = NSAppleScript(source: "tell application \"\(fallbackAppName)\" to \(command)")
        else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        refreshFromAppleScript()
    }
}
