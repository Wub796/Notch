import AppKit
import CoreAudio
import Observation

/// Which apps get their audio rewritten, and how.
///
/// The engine owns one `MixerStrip` per app that has been changed and tears it
/// down again the moment that app is back to unity — so the cost of this module
/// is proportional to how many apps the user has actually touched, and an app
/// nobody has touched is untouched in the literal sense: no tap, no aggregate
/// device, no render callback, and its audio never leaves the system's own path.
///
/// Settings are keyed by bundle id rather than by PID or process object. Both of
/// those are re-issued when an app relaunches, and settings that evaporated
/// every time a browser restarted would read as a bug.
@Observable
final class MixerEngine {
    /// One app's settings, as the user set them.
    struct AppMix: Identifiable, Equatable, Codable {
        var id: String
        /// Linear gain: 1 is unchanged, 0 is silent, 4 is the boost ceiling.
        var gain: Float = 1
        var isMuted = false
        /// Where this app's audio should come out, when it should not simply
        /// follow the system output. Stored as a device UID because device IDs
        /// are not stable across reboots.
        var routeDeviceUID: String?
        /// Either a built-in preset's id or `custom`, with `bands` carrying the
        /// curve in the custom case — see `Equalizer`.
        var equalizerPresetID: String = EqualizerPreset.flat.id
        var equalizerBands: [EQBand]?
        /// Boosts the low end as the output level drops, so quiet listening
        /// keeps its weight instead of thinning out.
        var loudnessCompensation = false
        /// The AutoEQ correction chosen for this app, if any.
        var autoEQProfileID: UUID?
    }

    /// Master switch. Off means no tap is ever created: the feature is inert
    /// rather than merely hidden, which is what keeps a disabled mixer from
    /// being a thing that can fail.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.isEnabled)
            if !isEnabled { stopAll() } else { reconcile() }
        }
    }

    /// Every app with non-default settings — the whole of what this module
    /// persists, and what the UI draws its rows from.
    private(set) var mixes: [String: AppMix] = [:]
    /// Why the last attempt to tap an app failed, per app. Shown in the row
    /// rather than silently leaving a slider that does nothing.
    private(set) var failures: [String: String] = [:]
    /// Apps whose audio is currently being rewritten.
    private(set) var activeAppIDs: Set<String> = []

    /// True when this macOS is new enough for the tap path at all.
    var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    private var strips: [String: MixerStrip] = [:]
    /// Every tap is built, updated and destroyed here, one at a time.
    ///
    /// A tap is not a cheap object to make: it constructs a private aggregate
    /// device and asks the system to authorise audio capture, either of which
    /// can wait. `reconcile` decides *whether* a strip should exist — that part
    /// reads and writes this object's state and stays on the main thread — and
    /// hands the CoreAudio half of it to this queue. Running it inline is what
    /// froze the notch when a per-app slider was first moved.
    private let controlQueue = DispatchQueue(
        label: "com.notchapp.Notch.mixer.control",
        qos: .userInitiated
    )
    /// The CoreAudio objects each app is currently made of, refreshed from the
    /// app monitor — the tap has to name them, and they change as apps start,
    /// quit and spawn helpers.
    private var processObjectsByApp: [String: [AudioObjectID]] = [:]
    private var outputDevice: AudioOutputDevice?
    private let defaults = UserDefaults.standard
    private var hasLoaded = false

    private enum Key {
        static let isEnabled = "mixer.isEnabled"
        static let mixes = "mixer.appMixes"
    }

    init() {
        isEnabled = true
        isEnabled = UserDefaults.standard.object(forKey: Key.isEnabled) as? Bool ?? true
        if let data = defaults.data(forKey: Key.mixes),
           let stored = try? JSONDecoder().decode([String: AppMix].self, from: data) {
            mixes = stored
        }
        hasLoaded = true
        outputDevice = Self.systemOutputDevice()
    }

    // MARK: - What the UI reads

    func mix(for appID: String) -> AppMix {
        mixes[appID] ?? AppMix(id: appID)
    }

    /// Whether an app's row should offer the full mixer or just a plain slider:
    /// without a tap path there is nothing to control, which the row says.
    func canControl(_ appID: String) -> Bool {
        isEnabled && isSupported && !(processObjectsByApp[appID]?.isEmpty ?? true)
    }

    func isActive(_ appID: String) -> Bool {
        activeAppIDs.contains(appID)
    }

    // MARK: - What the UI sets

    func setGain(_ gain: Float, for appID: String) {
        var mix = mix(for: appID)
        mix.gain = min(max(gain, 0), 4)
        // A slider pulled back to silence and a mute button are the same
        // outcome; keep them from disagreeing in the stored value.
        if mix.gain > 0, mix.isMuted { mix.isMuted = false }
        store(mix)
    }

    func toggleMute(for appID: String) {
        var mix = mix(for: appID)
        mix.isMuted.toggle()
        store(mix)
    }

    func route(_ deviceUID: String?, for appID: String) {
        var mix = mix(for: appID)
        mix.routeDeviceUID = deviceUID
        store(mix)
    }

    func setEqualizer(_ presetID: String, bands: [EQBand]?, for appID: String) {
        var mix = mix(for: appID)
        mix.equalizerPresetID = presetID
        mix.equalizerBands = presetID == EqualizerPreset.customID ? bands : nil
        store(mix)
    }

    func setLoudnessCompensation(_ enabled: Bool, for appID: String) {
        var mix = mix(for: appID)
        mix.loudnessCompensation = enabled
        store(mix)
    }

    func setAutoEQProfile(_ profileID: UUID?, for appID: String) {
        var mix = mix(for: appID)
        mix.autoEQProfileID = profileID
        store(mix)
    }

    /// Forgets an app's settings and gives it its own audio back.
    func reset(_ appID: String) {
        mixes.removeValue(forKey: appID)
        failures.removeValue(forKey: appID)
        persist()
        reconcile()
    }

    // MARK: - App and device changes

    /// Hands the engine the app list the monitor just resolved. Called on every
    /// audio-activity change, which is push-based: nothing here polls.
    func observe(apps: [AudioAppMonitor.App]) {
        processObjectsByApp = apps.reduce(into: [:]) { result, app in
            result[app.id] = app.volumeObjects
        }
        reconcile()
    }

    /// Re-reads the system output device — its UID decides where an unrouted
    /// app's audio is sent, and its volume feeds loudness compensation.
    func refreshDevices() {
        outputDevice = Self.systemOutputDevice()
        reconcile()
    }

    /// Drops every tap. Called when the app is shutting down, and when the
    /// notch sleeps its modules.
    ///
    /// The teardowns are queued like every other CoreAudio call, and this waits
    /// for that queue to drain: a private aggregate device and its tap belong to
    /// this process, so none of them should still be being built while the
    /// process is ending. Blocking here is safe because `shutdown` is only ever
    /// called from the main thread.
    func shutdown() {
        stopAll()
        controlQueue.sync {}
    }

    // MARK: - Reconciliation

    /// Brings the taps in line with the settings: starts one for every app that
    /// needs it, updates the ones already running, and destroys the rest.
    private func reconcile() {
        guard hasLoaded else { return }
        guard isEnabled, isSupported else {
            stopAll()
            return
        }

        let wanted = Set(mixes.keys.filter { needsProcessing(mix(for: $0)) })

        for appID in wanted {
            guard let objects = processObjectsByApp[appID], !objects.isEmpty else {
                // Nothing to tap yet — the app is closed, or the monitor has not
                // seen it play. Its row stays, and the tap appears when it does.
                continue
            }
            let target = targetOutputDevice(for: appID)
            let strip: MixerStrip
            // `isActive`, not `isRunning`: a strip whose tap is still being
            // built is already this app's strip, and a second pass arriving
            // mid-build must not replace it with another one.
            if let existing = strips[appID], existing.isActive, existing.appID == appID {
                strip = existing
            } else {
                let previous = strips[appID]
                strip = MixerStrip(
                    appID: appID,
                    processObjects: objects,
                    outputDeviceID: target?.id ?? 0,
                    outputDeviceUID: target?.uid ?? "",
                    sampleRate: target?.sampleRate ?? 48_000
                )
                strips[appID] = strip
                // Marked here rather than on the queue: this is the moment the
                // app stops being stripless, and the next reconcile reads it.
                strip.markStarting()
                build(strip, replacing: previous, for: appID)
            }
            strip.apply(
                gain: mix(for: appID).isMuted ? 0 : mix(for: appID).gain,
                filters: filters(for: appID, outputDevice: target),
                channelCount: 2
            )
        }

        for (appID, strip) in strips where !wanted.contains(appID) {
            strips.removeValue(forKey: appID)
            failures.removeValue(forKey: appID)
            tearDown(strip)
        }

        activeAppIDs = Set(strips.keys)
    }

    /// Builds a strip's tap on the control queue and reports the outcome on the
    /// main thread, where the observable results belong.
    private func build(_ strip: MixerStrip, replacing previous: MixerStrip?, for appID: String) {
        controlQueue.async { [weak self] in
            // The strip this one replaces is destroyed first, on the same
            // queue, so the two can never both be running for one app.
            previous?.stop()
            #if DEBUG
            print("[Notch] mixer: building a tap for \(appID)")
            #endif
            let started = strip.start()

            DispatchQueue.main.async {
                guard let self else { return }
                guard started else {
                    self.failures[appID] = strip.failureReason ?? "Could not start mixing this app."
                    // Only if this strip is still the app's current one: a newer
                    // pass may already have replaced it, and removing that one
                    // would take a working tap away.
                    if self.strips[appID] === strip {
                        self.strips.removeValue(forKey: appID)
                        self.activeAppIDs = Set(self.strips.keys)
                    }
                    #if DEBUG
                    print("[Notch] mixer: tap refused for \(appID)")
                    #endif
                    return
                }
                if self.strips[appID] === strip {
                    self.failures.removeValue(forKey: appID)
                    self.activeAppIDs = Set(self.strips.keys)
                }
                #if DEBUG
                print("[Notch] mixer: tap running for \(appID)")
                #endif
            }
        }
    }

    /// Destroys a strip off the main thread, for the same reason it is built
    /// there: an aggregate device is not torn down instantly.
    private func tearDown(_ strip: MixerStrip) {
        controlQueue.async {
            strip.stop()
        }
    }

    /// Whether a strip is worth having: everything at its default means the app
    /// plays through the system untouched, which is the point.
    private func needsProcessing(_ mix: AppMix) -> Bool {
        if mix.isMuted { return true }
        if abs(mix.gain - 1) > 0.0005 { return true }
        if mix.routeDeviceUID != nil { return true }
        if mix.loudnessCompensation { return true }
        if mix.autoEQProfileID != nil { return true }
        if mix.equalizerPresetID != EqualizerPreset.flat.id { return true }
        return false
    }

    /// The chain a strip applies: the app's equalizer curve, then the AutoEQ
    /// correction for the device its audio is going to, then loudness
    /// compensation for how loud that device currently is.
    ///
    /// Order matters. The equalizer is the user's taste, the correction is the
    /// headphone's measured error, and loudness is a property of the listening
    /// level — applying taste before correction before level is the order in
    /// which each makes sense of what came before it.
    private func filters(for appID: String, outputDevice device: AudioOutputDevice?) -> [Biquad] {
        let mix = mix(for: appID)
        var sections: [Biquad] = []

        let sampleRate = device?.sampleRate ?? 48_000
        let bands = mix.equalizerBands ?? EqualizerPreset.preset(for: mix.equalizerPresetID)?.bands ?? []
        for band in bands where band.gain != 0 {
            sections.append(
                Biquad.peaking(frequency: band.frequency, gainDB: Double(band.gain), q: band.q, sampleRate: sampleRate)
            )
        }

        if let profileID = mix.autoEQProfileID, let profile = AutoEQLibrary.shared.profile(id: profileID) {
            sections.append(contentsOf: profile.biquads(sampleRate: sampleRate))
        }

        if mix.loudnessCompensation, let device {
            sections.append(contentsOf: LoudnessCurve.shelves(for: device.volume, sampleRate: sampleRate))
        }

        return sections
    }

    /// Where one app's audio should come out: its own pick, else the system
    /// output.
    private func targetOutputDevice(for appID: String) -> AudioOutputDevice? {
        if let uid = mix(for: appID).routeDeviceUID,
           let routed = Self.outputDevice(uid: uid) {
            return routed
        }
        return outputDevice
    }

    // MARK: - Persistence

    private func store(_ mix: AppMix) {
        mixes[mix.id] = mix
        persist()
        reconcile()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(mixes) else { return }
        defaults.set(data, forKey: Key.mixes)
    }

    private func stopAll() {
        for (_, strip) in strips { tearDown(strip) }
        strips.removeAll()
        activeAppIDs = []
    }

    // MARK: - The system's output device

    /// What CoreAudio currently calls the default output: the id the aggregate
    /// device is built against, the UID that survives a reboot, the volume
    /// loudness compensation reads, and the rate the filters are designed for.
    struct AudioOutputDevice {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let volume: Float
        let sampleRate: Double
    }

    static func systemOutputDevice() -> AudioOutputDevice? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != AudioDeviceID(kAudioObjectUnknown)
        else { return nil }
        return outputDevice(id: deviceID)
    }

    static func outputDevice(uid: String) -> AudioOutputDevice? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), pointer, &size, &deviceID)
        }
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return outputDevice(id: deviceID)
    }

    /// Every output device the user could route an app to — the same list the
    /// audio screen's device switcher offers.
    static func outputDevices() -> [AudioOutputDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let device = outputDevice(id: id)
            return device
        }
    }

    private static func outputDevice(id: AudioDeviceID) -> AudioOutputDevice? {
        guard let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID) else { return nil }
        let name = stringProperty(id, selector: kAudioObjectPropertyName) ?? uid
        return AudioOutputDevice(
            id: id,
            uid: uid,
            name: name,
            volume: floatProperty(id, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput),
            sampleRate: nominalSampleRate(id)
        )
    }

    private static func stringProperty(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String
    }

    private static func floatProperty(
        _ id: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Float {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: Float32 = 1
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 1 }
        return value
    }

    private static func nominalSampleRate(_ id: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Float64 = 48_000
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, value > 0 else { return 48_000 }
        return value
    }
}
