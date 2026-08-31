import AppKit
import Combine
import Foundation

final class UnifiedMediaMetadataEngine: ObservableObject {
    @Published private(set) var track: NotchMediaTrack?

    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var anchorPosition: TimeInterval = 0
    private var anchorDate = Date()

    init() {
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: Notification.Name("com.apple.iTunes.playerInfo"), object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            },
            center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        ]
        refresh()
    }

    deinit {
        refreshTask?.cancel()
        tickTimer?.invalidate()
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            async let apple = Self.appleMusicSnapshot()
            async let spotify = Self.spotifySnapshot()
            let candidates = await [apple, spotify].compactMap { $0 }
            guard !Task.isCancelled else { return }
            let selected = candidates.first(where: { $0.isPlaying }) ?? candidates.first
            await MainActor.run { [weak self] in
                self?.apply(selected)
            }
        }
    }

    private func apply(_ value: NotchMediaTrack?) {
        track = value
        anchorPosition = value?.currentPosition ?? 0
        anchorDate = Date()
        tickTimer?.invalidate()
        tickTimer = nil
        guard value?.isPlaying == true else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let current = track, current.isPlaying else { return }
        let position = min(max(anchorPosition + Date().timeIntervalSince(anchorDate), 0), current.duration > 0 ? current.duration : .greatestFiniteMagnitude)
        track = NotchMediaTrack(
            title: current.title,
            artist: current.artist,
            album: current.album,
            artwork: current.artwork,
            duration: current.duration,
            currentPosition: position,
            isPlaying: true,
            mediaSource: current.mediaSource
        )
    }

    private static func appleMusicSnapshot() async -> NotchMediaTrack? {
        guard let raw = await script("""
        tell application "Music"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & (duration of t as text) & "||" & (player position as text) & "||" & (player state as text)
        end tell
        """) else { return nil }
        return parse(raw, source: .appleMusic, appName: "Music")
    }

    private static func spotifySnapshot() async -> NotchMediaTrack? {
        guard let raw = await script("""
        tell application "Spotify"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & (duration of t as text) & "||" & (player position as text) & "||" & (player state as text)
        end tell
        """) else { return nil }
        return parse(raw, source: .spotify, appName: "Spotify")
    }

    private static func script(_ source: String) async -> String? {
        await Task.detached(priority: .utility) {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            guard error == nil else { return nil }
            return result?.stringValue
        }.value
    }

    private static func parse(_ raw: String, source: NotchMediaSource, appName: String) -> NotchMediaTrack? {
        let parts = raw.components(separatedBy: "||")
        guard parts.count >= 6, !parts[0].isEmpty else { return nil }
        let duration = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        let position = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        let image = NSRunningApplication.runningApplications(withBundleIdentifier: source == .spotify ? MusicProvider.spotify.bundleID : "com.apple.Music").first?.icon
        return NotchMediaTrack(
            title: parts[0], artist: parts[1], album: parts[2], artwork: image,
            duration: duration > 21_600 ? duration / 1_000 : duration,
            currentPosition: position, isPlaying: parts[5] == "playing", mediaSource: source
        )
    }
}
