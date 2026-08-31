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
///    /// Per-process volume is exposed through the CoreAudio process object's
    /// `voul` property on supported macOS releases.

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

        func volume() -> Float? {
            AudioAppMonitor.readProcessVolume(for: pid)
        }

        func setVolume(_ level: Float) {
            AudioAppMonitor.writeProcessVolume(level, for: pid)
        }
    }

    private(set) var apps: [App] = []

    /// True the instant anything on this Mac is putting audio out, whatever
    /// it is. On 14.4+ this is the union of the per-process flags; below that
    /// it is CoreAudio's own `deviceIsRunningSomewhere`, which every macOS
    /// has and which is just as immediate — it simply cannot say *who*.
    private(set) var isAnyAudioPlaying = false

    /// Called on the main queue the moment CoreAudio reports that the set of
    /// audio processes, or whether one of them is running output, changed.
    /// The owner re-reads the list from here; nothing polls.
    var onAudioActivityChange: (() -> Void)?

    private var isObserving = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var observedProcessObjects: [AudioObjectID] = []
    private var observedDevices: [AudioObjectID] = []

    /// True when this macOS can report audio processes; the UI says so rather
    /// than silently showing a thinner list.
    var canObserveProcesses: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    /// `nowPlayingBundleID` is only used on the fallback path, and to keep the
    /// current player listed even while it is momentarily silent.
    func refresh(nowPlayingBundleID: String? = nil, isPlaying: Bool = false) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let apps: [App]
            if #available(macOS 14.4, *) {
                let observed = Self.audioProcesses()
                if !observed.isEmpty {
                    apps = Self.resolve(observed, keeping: nowPlayingBundleID, isPlaying: isPlaying)
                } else {
                    apps = Self.fallbackApps(nowPlayingBundleID: nowPlayingBundleID, isPlaying: isPlaying)
                }
            } else {
                apps = Self.fallbackApps(nowPlayingBundleID: nowPlayingBundleID, isPlaying: isPlaying)
            }
            DispatchQueue.main.async { [weak self] in
                self?.apps = apps
            }
        }
    }

    // MARK: - Push notifications

    /// Starts listening. Three things are watched, all of them push:
    ///
    /// * `'prs#'` on the system object — a process appearing or leaving.
    /// * `'piro'` on each of those processes — that process starting or
    ///   stopping output. This is the one that makes a browser tab, a game or
    ///   a call show up the moment it makes a sound.
    /// * `deviceIsRunningSomewhere` on every output device — the same fact at
    ///   device granularity, which is all that exists before macOS 14.4.
    ///
    /// Listeners cost nothing while quiet, so unlike the old one-second poll
    /// this runs for the life of the app rather than only while the Audio
    /// screen happens to be open.
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleActivityChange()
        }
        listenerBlock = block

        audioQueue.async { [weak self] in
            guard let self else { return }
            if #available(macOS 14.4, *) {
                var address = Self.address(Self.processObjectListSelector)
                AudioObjectAddPropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &address, self.audioQueue, block
                )
            }

            var deviceList = Self.address(kAudioHardwarePropertyDevices)
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &deviceList, self.audioQueue, block
            )

            self.attachPerObjectListeners()
            self.handleActivityChange()
        }
    }

    /// Tears the listeners down and puts them back. After a sleep/wake cycle
    /// the audio objects this was watching may no longer exist — CoreAudio
    /// re-enumerates devices on wake — and listeners on a dead object never
    /// fire again, which would leave the screen quietly stale forever.
    func restartObserving() {
        stopObserving()
        startObserving()
    }

    deinit {
        stopObserving()
    }

    func stopObserving() {
        pendingChange?.cancel()
        pendingChange = nil
        guard isObserving, let block = listenerBlock else { return }
        isObserving = false

        if #available(macOS 14.4, *) {
            var address = Self.address(Self.processObjectListSelector)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, audioQueue, block
            )
        }
        var deviceList = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &deviceList, audioQueue, block
        )

        detachPerObjectListeners()
        listenerBlock = nil
    }

    /// The set of processes and devices changes underneath us, so the
    /// per-object listeners are torn down and re-attached whenever anything
    /// fires. That is a handful of CoreAudio calls on a real change, not a
    /// timer.
    private func attachPerObjectListeners() {
        guard let block = listenerBlock else { return }
        detachPerObjectListeners()

        if #available(macOS 14.4, *) {
            observedProcessObjects = Self.audioProcessObjects()
            var running = Self.address(Self.processIsRunningOutputSelector)
            for object in observedProcessObjects {
                AudioObjectAddPropertyListenerBlock(object, &running, audioQueue, block)
            }
        }

        observedDevices = Self.outputDeviceObjects()
        var isRunning = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        for device in observedDevices {
            AudioObjectAddPropertyListenerBlock(device, &isRunning, audioQueue, block)
        }
    }

    private func detachPerObjectListeners() {
        guard let block = listenerBlock else { return }

        if #available(macOS 14.4, *) {
            var running = Self.address(Self.processIsRunningOutputSelector)
            for object in observedProcessObjects {
                AudioObjectRemovePropertyListenerBlock(object, &running, audioQueue, block)
            }
        }
        observedProcessObjects = []

        var isRunning = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        for device in observedDevices {
            AudioObjectRemovePropertyListenerBlock(device, &isRunning, audioQueue, block)
        }
        observedDevices = []
    }

    /// One pass per burst.
    ///
    /// A single "audio started" is several notifications — the process list
    /// changes, then that process reports output, then the device reports it
    /// is running — and each pass re-attaches every per-object listener and
    /// rebuilds the app list. Answering all of them individually would turn a
    /// browser opening tabs into a stream of redundant work. A tenth of a
    /// second is below the threshold of feeling delayed and collapses the
    /// burst into one update.
    private func scheduleActivityChange() {
        // Coalesce on the audio queue: the listener block already fires there,
        // so this just debounces the burst into one pass without touching main.
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingChange = nil
            self?.handleActivityChange()
        }
        pendingChange = work
        audioQueue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private var pendingChange: DispatchWorkItem?
    private let audioQueue = DispatchQueue(label: "com.notch.audio-monitor", qos: .utility)

    /// Runs on the audio queue — the listeners fire there, and the debounced
    /// work item is scheduled there, so this never touches the main thread for
    /// CoreAudio work. Only the final state write hops to main.
    private func handleActivityChange() {
        // Already on audioQueue (called from the debounced work item which runs
        // here). attach/detach are safe on this queue since the listeners are
        // registered to fire here too — no cross-thread CoreAudio deadlock.
        attachPerObjectListeners()

        let playing: Bool
        if #available(macOS 14.4, *), !observedProcessObjects.isEmpty {
            playing = observedProcessObjects.contains { Self.isRunningOutput($0) }
        } else {
            playing = observedDevices.contains { Self.deviceIsRunningSomewhere($0) }
        }
        let apps = readAppsOnAudioQueue()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.apps = apps
            if self.isAnyAudioPlaying != playing {
                self.isAnyAudioPlaying = playing
            }
            self.onAudioActivityChange?()
        }
    }

    private func readAppsOnAudioQueue() -> [App] {
        if #available(macOS 14.4, *) {
            let observed = Self.audioProcesses()
            if !observed.isEmpty {
                return Self.resolve(observed, keeping: nil, isPlaying: false)
            }
        }
        return Self.fallbackApps(nowPlayingBundleID: nil, isPlaying: false)
    }

    private static func address(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Every device with at least one output stream.
    private static func outputDeviceObjects() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }

        return devices.filter { device in
            var streams = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(
                device, &streams, 0, nil, &streamSize
            ) == noErr && streamSize > 0
        }
    }

    private static func deviceIsRunningSomewhere(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    // MARK: - CoreAudio process list

    /// `'prs#'`, `'ppid'` and `'piro'` from AudioHardware.h.
    private static let processObjectListSelector = fourCharCode("prs#")
    private static let processPIDSelector = fourCharCode("ppid")
    private static let processIsRunningOutputSelector = fourCharCode("piro")
    private static let processVolumeSelector = fourCharCode("voul")

    private static func fourCharCode(_ value: String) -> AudioObjectPropertySelector {
        value.utf8.reduce(0) { ($0 << 8) + AudioObjectPropertySelector($1) }
    }

    @available(macOS 14.4, *)
    private static func audioProcessObjects() -> [AudioObjectID] {
        var address = self.address(processObjectListSelector)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects
        ) == noErr else { return [] }
        return objects
    }

    @available(macOS 14.4, *)
    private static func audioProcesses() -> [(pid: pid_t, isRunningOutput: Bool)] {
        audioProcessObjects().compactMap { object in
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
    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        audioProcessObjects().first { processID(of: $0) == pid }
    }

    private static func readProcessVolume(for pid: pid_t) -> Float? {
        guard #available(macOS 14.4, *) else { return nil }
        guard let object = processObject(for: pid) else { return nil }
        var address = address(processVolumeSelector)
        var volume: Float = 1
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &volume) == noErr else {
            return nil
        }
        return min(max(volume, 0), 1)
    }

    private static func writeProcessVolume(_ level: Float, for pid: pid_t) {
        guard #available(macOS 14.4, *), let object = processObject(for: pid) else { return }
        var address = address(processVolumeSelector)
        var volume = min(max(level, 0), 1)
        var size = UInt32(MemoryLayout<Float>.size)
        _ = AudioObjectSetPropertyData(object, &address, 0, nil, size, &volume)
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

    // MARK: - Process Host Resolution

    private static func resolveHostApp(for running: NSRunningApplication) -> (id: String, name: String, icon: NSImage?, mainApp: NSRunningApplication?) {
        let bundleID = running.bundleIdentifier ?? ""

        // Common helper and browser mappings
        let knownMappings: [(prefix: String, mainBundleID: String, defaultName: String)] = [
            ("com.google.Chrome", "com.google.Chrome", "Google Chrome"),
            ("com.apple.WebKit", "com.apple.Safari", "Safari"),
            ("com.apple.Safari", "com.apple.Safari", "Safari"),
            ("company.thebrowser.Browser", "company.thebrowser.Browser", "Arc"),
            ("com.brave.Browser", "com.brave.Browser", "Brave"),
            ("org.mozilla.firefox", "org.mozilla.firefox", "Firefox"),
            ("com.microsoft.edgemac", "com.microsoft.edgemac", "Microsoft Edge"),
            ("com.operasoftware", "com.operasoftware.Opera", "Opera"),
            ("com.hnc.Discord", "com.hnc.Discord", "Discord"),
            ("com.tinyspeck.slackmacgap", "com.tinyspeck.slackmacgap", "Slack"),
            ("com.spotify.client", "com.spotify.client", "Spotify"),
            ("com.apple.Music", "com.apple.Music", "Music"),
            ("com.apple.TV", "com.apple.TV", "Apple TV"),
            ("com.apple.podcasts", "com.apple.podcasts", "Podcasts"),
            ("org.videolan.vlc", "org.videolan.vlc", "VLC"),
            ("com.colliderli.iina", "com.colliderli.iina", "IINA"),
            ("us.zoom.xos", "us.zoom.xos", "Zoom"),
            ("com.apple.FaceTime", "com.apple.FaceTime", "FaceTime"),
            ("com.apple.QuickTimePlayerX", "com.apple.QuickTimePlayerX", "QuickTime Player")
        ]

        for mapping in knownMappings {
            if bundleID.hasPrefix(mapping.prefix) || bundleID.contains(mapping.prefix) {
                if let mainApp = NSRunningApplication.runningApplications(withBundleIdentifier: mapping.mainBundleID).first {
                    return (mapping.mainBundleID, mainApp.localizedName ?? mapping.defaultName, mainApp.icon, mainApp)
                }
                return (mapping.mainBundleID, mapping.defaultName, running.icon, running)
            }
        }

        // Check if there is a running application whose bundle identifier is a prefix
        if let mainApp = NSWorkspace.shared.runningApplications.first(where: { app in
            guard let appID = app.bundleIdentifier else { return false }
            return (bundleID.hasPrefix(appID) || appID.hasPrefix(bundleID)) && app.activationPolicy == .regular
        }) {
            return (mainApp.bundleIdentifier ?? bundleID, mainApp.localizedName ?? running.localizedName ?? "Audio App", mainApp.icon, mainApp)
        }

        return (bundleID, running.localizedName ?? "Audio App", running.icon, running)
    }

    /// Turns pids into apps, resolving browser and helper processes to their
    /// main parent applications (Chrome, Safari, Firefox, Discord, etc.).
    private static func resolve(
        _ processes: [(pid: pid_t, isRunningOutput: Bool)],
        keeping nowPlayingBundleID: String?,
        isPlaying: Bool
    ) -> [App] {
        var byBundle: [String: App] = [:]

        for process in processes {
            guard let running = NSRunningApplication(processIdentifier: process.pid) else { continue }

            let host = resolveHostApp(for: running)
            guard !host.id.isEmpty, host.id != "com.apple.audio.CoreAudio" else { continue }

            let app = App(
                id: host.id,
                name: host.name,
                icon: host.icon,
                isPlaying: process.isRunningOutput,
                pid: host.mainApp?.processIdentifier ?? process.pid
            )

            // If already present, ensure isPlaying is true if any child process is playing
            if let existing = byBundle[host.id] {
                if !existing.isPlaying && app.isPlaying {
                    byBundle[host.id] = app
                }
            } else {
                byBundle[host.id] = app
            }
        }

        // Also ensure all running known audio/browser apps appear
        let runningApps = NSWorkspace.shared.runningApplications
        for running in runningApps {
            guard let id = running.bundleIdentifier,
                  running.activationPolicy == .regular,
                  audioBundleIDs.contains(id) || id == nowPlayingBundleID
            else { continue }

            if byBundle[id] == nil {
                byBundle[id] = App(
                    id: id,
                    name: running.localizedName ?? id,
                    icon: running.icon,
                    isPlaying: id == nowPlayingBundleID && isPlaying,
                    pid: running.processIdentifier
                )
            }
        }

        return sorted(Array(byBundle.values))
    }

    // MARK: - Pre-14.4 fallback

    /// Known media and browser apps that produce audio on macOS.
    private static let audioBundleIDs: Set<String> = [
        "com.apple.Music", "com.spotify.client", "com.google.Chrome",
        "com.apple.Safari", "org.mozilla.firefox", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.brave.Browser", "com.operasoftware.Opera",
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
