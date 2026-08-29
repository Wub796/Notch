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
        if #available(macOS 14.4, *) {
            let observed = Self.audioProcesses()
            if !observed.isEmpty {
                apps = Self.resolve(observed, keeping: nowPlayingBundleID, isPlaying: isPlaying)
                return
            }
        }
        apps = Self.fallbackApps(nowPlayingBundleID: nowPlayingBundleID, isPlaying: isPlaying)
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
            DispatchQueue.main.async { [weak self] in
                self?.scheduleActivityChange()
            }
        }
        listenerBlock = block

        if #available(macOS 14.4, *) {
            var address = Self.address(Self.processObjectListSelector)
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block
            )
        }

        var deviceList = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &deviceList, .main, block
        )

        attachPerObjectListeners()
        handleActivityChange()
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
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block
            )
        }
        var deviceList = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &deviceList, .main, block
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
                AudioObjectAddPropertyListenerBlock(object, &running, .main, block)
            }
        }

        observedDevices = Self.outputDeviceObjects()
        var isRunning = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        for device in observedDevices {
            AudioObjectAddPropertyListenerBlock(device, &isRunning, .main, block)
        }
    }

    private func detachPerObjectListeners() {
        guard let block = listenerBlock else { return }

        if #available(macOS 14.4, *) {
            var running = Self.address(Self.processIsRunningOutputSelector)
            for object in observedProcessObjects {
                AudioObjectRemovePropertyListenerBlock(object, &running, .main, block)
            }
        }
        observedProcessObjects = []

        var isRunning = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        for device in observedDevices {
            AudioObjectRemovePropertyListenerBlock(device, &isRunning, .main, block)
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
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingChange = nil
            self?.handleActivityChange()
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private var pendingChange: DispatchWorkItem?

    private func handleActivityChange() {
        attachPerObjectListeners()

        let playing: Bool
        if #available(macOS 14.4, *), !observedProcessObjects.isEmpty {
            playing = observedProcessObjects.contains { Self.isRunningOutput($0) }
        } else {
            playing = observedDevices.contains { Self.deviceIsRunningSomewhere($0) }
        }
        if isAnyAudioPlaying != playing {
            isAnyAudioPlaying = playing
        }

        onAudioActivityChange?()
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
