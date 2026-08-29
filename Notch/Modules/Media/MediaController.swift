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
    private(set) var isPlaying = false

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
    private var sourceAppBundleID: String?

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
    private var isActive = false

    var hasTrack: Bool {
        track != nil
    }

    /// True when transport controls do something: a track is showing, or a
    /// specific provider is selected — play will launch and start that app.
    var canControlTransport: Bool {
        hasTrack || selectedProvider != .automatic
    }

    var currentElapsed: TimeInterval {
        guard track != nil else { return 0 }
        guard isPlaying else { return elapsedAnchor }
        return elapsedAnchor + Date().timeIntervalSince(anchorDate)
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
        guard active else { return }

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
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
                self?.updateSourceApp(pid: pid)
            }
        }
        bridge.isPlaying { [weak self] playing in
            DispatchQueue.main.async {
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
            track = nil
            artwork = nil
            isPlaying = false
            sourceAppBundleID = nil
            updateLyricActivityTimer()
            return
        }

        consecutiveEmptyReplies = 0

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
            DispatchQueue.main.async {
                guard let self, self.accentSourceHash == hash else { return }
                withAnimation(.notchSpring) {
                    self.accent = color
                }
            }
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
        } else {
            lyrics.clear()
            artwork = nil
            accent = .white
            accentSourceHash = nil
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

    private func refreshFromAppleScript() {
        // Never launch a player just to ask what is playing.
        guard fallbackAppIsRunning,
              let script = NSAppleScript(source: stateScript(for: fallbackAppName))
        else { return }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let raw = result.stringValue, raw != "stopped" else {
            track = nil
            isPlaying = false
            return
        }

        let parts = raw.components(separatedBy: "||")
        guard parts.count >= 6 else { return }

        var newTrack = Track()
        newTrack.title = parts[0]
        newTrack.artist = parts[1]
        newTrack.album = parts[2]
        newTrack.duration = TimeInterval(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0

        elapsedAnchor = TimeInterval(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        anchorDate = Date()
        isPlaying = parts[5] == "playing"

        updateTrackIfChanged(newTrack)
        updateLyricActivityTimer()

        // The AppleScript path only ever talks to the selected provider.
        if sourceAppName == nil,
           let app = NSRunningApplication
               .runningApplications(withBundleIdentifier: fallbackBundleID).first {
            sourceAppName = app.localizedName
            sourceAppIcon = app.icon
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
