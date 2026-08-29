import AppKit
import CoreAudio
import Observation

/// Which apps are putting audio out of this Mac right now.
///
/// macOS 14.4 made the audio process list public — `kAudioHardwarePropertyProcessObjectList`
/// on the system object, with `kAudioProcessPropertyIsRunningOutput` per
/// process — so "is this app making sound" is a fact that can be read rather
/// than guessed. That covers device audio generally: a browser tab, a game, a
/// call, anything, not only whatever holds the now-playing session.
///
/// Setting a process's volume is still not exposed; only observing it is.
///
/// The three selectors are spelled as four-character codes rather than by
/// name. `kAudioHardwarePropertyProcessObjectList` and friends only exist in
/// the macOS 14.4 SDK, so naming them makes the whole file — and therefore
/// this type — fail to compile on Xcode 15.2 and earlier, which then reads as
/// "cannot find AudioAppMonitor in scope" everywhere it is used. The values
/// are stable ABI; the `#available` check below is what keeps them from being
/// called on a system that does not implement them.
@Observable
final class AudioAppMonitor {
    struct App: Identifiable, Equatable {
        let id: String
        let name: String
        let icon: NSImage?
        /// True when CoreAudio reports the process is actively running output.
        let isPlaying: Bool
        let pid: pid_t

        static func == (lhs: App, rhs: App) -> Bool {
            lhs.id == rhs.id && lhs.isPlaying == rhs.isPlaying
        }

        func activate() {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    private(set) var apps: [App] = []

    /// True when this macOS can report audio processes; the UI says so rather
    /// than silently showing a thinner list.
    var canObserveProcesses: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    /// `nowPlayingBundleID` is only used on the fallback path, and to keep the
    /// current player listed even while it is momentarily silent.
    func refresh(nowPlayingBundleID: String? = nil, isPlaying: Bool = false) {
        if #available(macOS 14.4, *) {
            let observed = Self.audioProcesses()
            if !observed.isEmpty {
                apps = Self.resolve(observed, keeping: nowPlayingBundleID, isPlaying: isPlaying)
                return
            }
        }
        apps = Self.fallbackApps(nowPlayingBundleID: nowPlayingBundleID, isPlaying: isPlaying)
    }

    // MARK: - CoreAudio process list

    /// `'prs#'`, `'ppid'` and `'piro'` from AudioHardware.h.
    private static let processObjectListSelector = fourCharCode("prs#")
    private static let processPIDSelector = fourCharCode("ppid")
    private static let processIsRunningOutputSelector = fourCharCode("piro")

    private static func fourCharCode(_ value: String) -> AudioObjectPropertySelector {
        value.utf8.reduce(0) { ($0 << 8) + AudioObjectPropertySelector($1) }
    }

    @available(macOS 14.4, *)
    private static func audioProcesses() -> [(pid: pid_t, isRunningOutput: Bool)] {
        var address = AudioObjectPropertyAddress(
            mSelector: processObjectListSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects
        ) == noErr else { return [] }

        return objects.compactMap { object in
            guard let pid = processID(of: object) else { return nil }
            return (pid, isRunningOutput(object))
        }
    }

    @available(macOS 14.4, *)
    private static func processID(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: processPIDSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr,
              pid > 0 else { return nil }
        return pid
    }

    @available(macOS 14.4, *)
    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: processIsRunningOutputSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    /// Turns pids into apps, dropping the ones with no user-facing identity —
    /// coreaudiod and friends have audio processes but no icon and no name
    /// worth showing.
    private static func resolve(
        _ processes: [(pid: pid_t, isRunningOutput: Bool)],
        keeping nowPlayingBundleID: String?,
        isPlaying: Bool
    ) -> [App] {
        var byBundle: [String: App] = [:]

        for process in processes {
            guard let running = NSRunningApplication(processIdentifier: process.pid),
                  let bundleID = running.bundleIdentifier,
                  let name = running.localizedName,
                  running.activationPolicy != .prohibited
            else { continue }

            let app = App(
                id: bundleID,
                name: name,
                icon: running.icon,
                isPlaying: process.isRunningOutput,
                pid: process.pid
            )
            // One row per app: a browser has several audio processes and only
            // some of them are producing sound at any moment.
            if let existing = byBundle[bundleID], existing.isPlaying { continue }
            byBundle[bundleID] = app
        }

        // Keep the current player visible between tracks, when it briefly
        // stops running output but is plainly still the thing you are using.
        if let nowPlayingBundleID, byBundle[nowPlayingBundleID] == nil,
           let running = NSRunningApplication
               .runningApplications(withBundleIdentifier: nowPlayingBundleID).first {
            byBundle[nowPlayingBundleID] = App(
                id: nowPlayingBundleID,
                name: running.localizedName ?? nowPlayingBundleID,
                icon: running.icon,
                isPlaying: isPlaying,
                pid: running.processIdentifier
            )
        }

        return sorted(Array(byBundle.values))
    }

    // MARK: - Pre-14.4 fallback

    /// Known media apps that are running. Without the process list there is no
    /// way to tell whether they are actually making sound, so only the
    /// now-playing app is marked as playing.
    private static let audioBundleIDs: Set<String> = [
        "com.apple.Music", "com.spotify.client", "com.google.Chrome",
        "com.apple.Safari", "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.apple.TV", "com.apple.QuickTimePlayerX", "com.colliderli.iina",
        "org.videolan.vlc", "com.apple.podcasts", "com.apple.FaceTime",
        "us.zoom.xos", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
    ]

    private static func fallbackApps(nowPlayingBundleID: String?, isPlaying: Bool) -> [App] {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            guard let id = app.bundleIdentifier else { return false }
            return audioBundleIDs.contains(id) || id == nowPlayingBundleID
        }

        return sorted(running.compactMap { app in
            guard let id = app.bundleIdentifier else { return nil }
            return App(
                id: id,
                name: app.localizedName ?? id,
                icon: app.icon,
                isPlaying: id == nowPlayingBundleID && isPlaying,
                pid: app.processIdentifier
            )
        })
    }

    /// Whatever is making sound sorts to the top, then alphabetically.
    private static func sorted(_ apps: [App]) -> [App] {
        apps.sorted {
            $0.isPlaying == $1.isPlaying
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.isPlaying
        }
    }
}
