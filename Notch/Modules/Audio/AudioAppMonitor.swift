import AppKit
import Observation

/// The apps the audio screen lists.
///
/// macOS exposes no public way to enumerate which processes are producing
/// audio, let alone to set their volume — Sapphire ships an audio HAL plug-in
/// for that. What can be known for certain is which app owns the system
/// now-playing session, and which known media apps are running. That is what
/// this reports: real state, no guesses dressed up as measurements.
@Observable
final class AudioAppMonitor {
    struct App: Identifiable, Equatable {
        let id: String
        let name: String
        let icon: NSImage?
        let isPlaying: Bool

        static func == (lhs: App, rhs: App) -> Bool {
            lhs.id == rhs.id && lhs.isPlaying == rhs.isPlaying
        }

        func activate() {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: id)
                .first?
                .activate()
        }
    }

    private(set) var apps: [App] = []

    /// Apps worth listing when they are running. Deliberately a list rather
    /// than "every running app": a Finder row with a volume bar is noise.
    private static let audioBundleIDs: Set<String> = [
        "com.apple.Music",
        "com.spotify.client",
        "com.google.Chrome",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.apple.TV",
        "com.apple.QuickTimePlayerX",
        "com.colliderli.iina",
        "org.videolan.vlc",
        "com.apple.podcasts",
        "com.apple.FaceTime",
        "us.zoom.xos",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
    ]

    /// `nowPlayingBundleID` is the app that currently owns the system session,
    /// which is the only one that can honestly be marked as playing.
    func refresh(nowPlayingBundleID: String? = nil, isPlaying: Bool = false) {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return Self.audioBundleIDs.contains(id) || id == nowPlayingBundleID
        }

        apps = running
            .compactMap { app -> App? in
                guard let id = app.bundleIdentifier else { return nil }
                return App(
                    id: id,
                    name: app.localizedName ?? id,
                    icon: app.icon,
                    isPlaying: id == nowPlayingBundleID && isPlaying
                )
            }
            // Whatever is playing sorts to the top, then alphabetically.
            .sorted {
                $0.isPlaying == $1.isPlaying
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : $0.isPlaying
            }
    }
}
