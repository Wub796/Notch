import CoreAudio
import Foundation
import Observation

/// Lists CoreAudio output devices and switches the system default — the
/// notch equivalent of Sapphire's audio device picker. Public API only.
@Observable
final class AudioOutputManager {
    /// Shared instance: the system's audio state is one thing, and the
    /// Settings pane and the notch both read it.
    static let shared = AudioOutputManager()
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let transport: UInt32

        var symbolName: String {
            switch transport {
            case kAudioDeviceTransportTypeBluetooth,
                 kAudioDeviceTransportTypeBluetoothLE:
                "airpods"
            case kAudioDeviceTransportTypeUSB:
                "hifispeaker.fill"
            case kAudioDeviceTransportTypeHDMI,
                 kAudioDeviceTransportTypeDisplayPort:
                "tv"
            case kAudioDeviceTransportTypeAirPlay:
                "airplayaudio"
            case kAudioDeviceTransportTypeVirtual,
                 kAudioDeviceTransportTypeAggregate:
                "waveform"
            default:
                "speaker.wave.2.fill"
            }
        }
    }

    private(set) var devices: [Device] = []
    private(set) var currentDeviceID: AudioDeviceID = 0

    /// Output volume of the current device, 0...1, and its mute state.
    private(set) var volume: Float = 0
    private(set) var isMuted = false

    /// System alert (notification) volume, 0...1. Read and written through
    /// AppleScript — no CoreAudio property exists for it.
    private(set) var alertVolume: Float = 1

    /// State for the software mute fallback used on devices with no mute
    /// property of their own.
    private var softwareMuted = false
    private var volumeBeforeSoftwareMute: Float = 0.2

    private var isListening = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeDeviceID = AudioDeviceID(kAudioObjectUnknown)

    /// Serial queue for all CoreAudio property queries: device enumeration
    /// and volume reads are synchronous calls that can block, so they must
    /// never run on the main thread. Listeners fire on this queue too.
    private let audioQueue = DispatchQueue(label: "com.notch.audio-output", qos: .utility)

    /// Debounce: a single device change fires several notifications, and
    /// re-enumerating all devices for each one froze the UI.
    private var pendingRefresh: DispatchWorkItem?

    /// The device set from the last enumeration, so a *new* device appearing
    /// can be detected for the auto-switch feature.
    private var lastSeenDeviceIDs: Set<AudioDeviceID> = []
    /// False until the first enumeration completes, so the initial population
    /// is never treated as a burst of new devices.
    private var hasSeenDevices = false

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var systemOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var deviceListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func refresh() {
        // Run the heavy CoreAudio queries on the audio queue; only the
        // resulting state lands on main. The caller (launch, notch open)
        // gets an immediate read from the cache, and the queue updates it.
        refreshOnAudioQueue()
    }

    /// Reads the current alert volume through AppleScript. Called on launch
    /// and when the Settings pane opens; it is slow, so never per-frame.
    func refreshAlertVolume() {
        let script = NSAppleScript(source: "get alert volume of (get volume settings)")
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error) else { return }
        let pct = Int(result.int32Value)
        alertVolume = Float(pct) / 100.0
    }

    /// Debounce task for alert volume writes: `osascript` is heavy and the
    /// slider re-fires the binding on every render, so writes are coalesced.
    private var alertVolumeDebounceTask: Task<Void, Never>?

    /// Sets the system alert volume through `osascript`. A subprocess rather
    /// than in-process NSAppleScript: `set volume` silently fails under
    /// Hardened Runtime even with the Apple Events entitlement (the same
    /// restriction FineTune hit), while a child osascript bypasses it.
    func setAlertVolume(_ volume: Float) {
        let clamped = min(max(volume, 0), 1)
        let pct = Int(round(clamped * 100))
        let newVolume = Float(pct) / 100.0

        // Deduplicate: the observable update re-renders the slider, which
        // re-sends the same value; without this guard the debounce below
        // never fires.
        guard newVolume != alertVolume else { return }
        alertVolume = newVolume

        alertVolumeDebounceTask?.cancel()
        alertVolumeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "set volume alert volume \(pct)"]
            do {
                try process.run()
            } catch {
                // The slider is still optimistic; nothing else to do.
            }
            self.alertVolumeDebounceTask = nil
        }
    }

    private func refreshOnAudioQueue() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let devices = Self.outputDevices()
            let deviceID = Self.defaultOutputDevice()

            // Read volume on the audio queue — readScalar does synchronous
            // CoreAudio calls that can block on Bluetooth devices.
            let readings = Self.volumeElements.compactMap {
                self.readScalar(device: deviceID, element: $0)
            }
            let volume: Float
            if !readings.isEmpty {
                volume = min(max(readings.reduce(0, +) / Float32(readings.count), 0), 1)
            } else {
                volume = self.volume
            }

            var muted: UInt32 = 0
            var muteSize = UInt32(MemoryLayout<UInt32>.size)
            var isMuted = self.isMuted
            if AudioObjectHasProperty(deviceID, &Self.muteAddress),
               AudioObjectGetPropertyData(
                   deviceID, &Self.muteAddress, 0, nil, &muteSize, &muted
               ) == noErr {
                isMuted = muted != 0
            }

            let newIDs = Set(devices.map(\.id))
            let appeared = newIDs.subtracting(self.lastSeenDeviceIDs)
            self.lastSeenDeviceIDs = newIDs
            let autoSwitchCandidate = devices.first { appeared.contains($0.id) }
            let shouldAutoSwitch = self.hasSeenDevices
                && autoSwitchCandidate != nil
                && deviceID != autoSwitchCandidate?.id
                && NotchSettings.shared.autoSwitchOutputOnConnect
            self.hasSeenDevices = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.devices = devices
                self.currentDeviceID = deviceID
                self.volume = volume
                self.isMuted = isMuted
                if shouldAutoSwitch, let candidate = autoSwitchCandidate {
                    self.select(candidate)
                }
                // Re-attach the volume listener for the new device — on the
                // audio queue, not main.
                self.audioQueue.async { self.attachVolumeListener() }
            }
        }
    }

    /// Keeps the picker honest when the output changes anywhere else — a
    /// headset connecting, Sound settings, or another app. Without this the
    /// list only reflected whatever was true the last time the notch opened.
    /// It also drives the auto-switch-to-connected-device feature.
    func startListening() {
        guard !isListening else { return }
        isListening = true

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            // Coalesce on the audio queue: a single device change fires
            // several notifications, and re-enumerating for each froze the
            // UI. The debounce collapses them into one refresh.
            self.pendingRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.refreshOnAudioQueue()
            }
            self.pendingRefresh = work
            self.audioQueue.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, audioQueue, block
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.deviceListAddress, audioQueue, block
        )
        attachVolumeListener()
    }

    /// Volume lives on the device, so the listener has to follow the default
    /// output as it changes.
    ///
    /// It also has to be attached per element, not just the main one:
    /// boring.notch listens on the scalar property for the main element and
    /// channels 1 and 2, because devices that answer only on their channels —
    /// most Bluetooth headsets — never fire the main listener, and the HUD
    /// then misses every change made outside the app.
    private static func scalarAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private static let listenerElements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]

    private func attachVolumeListener() {
        guard let block = listenerBlock else { return }

        if volumeDeviceID != kAudioObjectUnknown {
            for element in Self.listenerElements {
                var address = Self.scalarAddress(element: element)
                AudioObjectRemovePropertyListenerBlock(volumeDeviceID, &address, audioQueue, block)
            }
            AudioObjectRemovePropertyListenerBlock(
                volumeDeviceID, &Self.muteAddress, audioQueue, block
            )
        }

        volumeDeviceID = currentDeviceID
        guard volumeDeviceID != kAudioObjectUnknown else { return }

        for element in Self.listenerElements {
            var address = Self.scalarAddress(element: element)
            if AudioObjectHasProperty(volumeDeviceID, &address) {
                AudioObjectAddPropertyListenerBlock(volumeDeviceID, &address, audioQueue, block)
            }
        }
        if AudioObjectHasProperty(volumeDeviceID, &Self.muteAddress) {
            AudioObjectAddPropertyListenerBlock(
                volumeDeviceID, &Self.muteAddress, audioQueue, block
            )
        }
    }

    // MARK: - Volume

    /// Reads the device's volume.
    ///
    /// boring.notch's approach, and it matters: many devices (aggregate
    /// devices, some USB DACs, most Bluetooth headsets) do not answer on the
    /// main element at all, and reading only that leaves the HUD stuck at
    /// zero. So every candidate element is probed, each answer is validated
    /// for the size CoreAudio actually reports, and the readings are averaged.
    private static let volumeElements: [UInt32] = [
        kAudioObjectPropertyElementMain, 1, 2, 3, 4,
    ]

    private func readScalar(device: AudioDeviceID, element: UInt32) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var needed: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &needed) == noErr,
              needed == UInt32(MemoryLayout<Float32>.size)
        else { return nil }
        var level = Float32(0)
        var size = needed
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level) == noErr else {
            return nil
        }
        return level
    }

    @discardableResult
    private func writeScalar(device: AudioDeviceID, element: UInt32, value: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(device, &address) else { return false }
        var needed: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &needed) == noErr,
              needed == UInt32(MemoryLayout<Float32>.size)
        else { return false }
        var level = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, needed, &level) == noErr
    }

    /// The current level, averaged across whichever elements answer.
    func currentVolume() -> Float {
        let device = currentDeviceID
        guard device != kAudioObjectUnknown else { return volume }
        let readings = Self.volumeElements.compactMap { readScalar(device: device, element: $0) }
        guard !readings.isEmpty else { return volume }
        return min(max(readings.reduce(0, +) / Float32(readings.count), 0), 1)
    }

    private func readVolume() {
        let device = currentDeviceID
        guard device != kAudioObjectUnknown else { return }

        let readings = Self.volumeElements.compactMap { readScalar(device: device, element: $0) }
        if !readings.isEmpty {
            volume = min(max(readings.reduce(0, +) / Float32(readings.count), 0), 1)
        }

        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &Self.muteAddress),
           AudioObjectGetPropertyData(
               device, &Self.muteAddress, 0, nil, &muteSize, &muted
           ) == noErr {
            isMuted = muted != 0
        } else {
            isMuted = softwareMuted
        }
    }

    /// Sets the output volume, unmuting first so dragging the HUD off zero
    /// actually makes sound. Falls back to per-channel writes where the main
    /// element refuses.
    func setVolume(_ newValue: Float) {
        let device = currentDeviceID
        guard device != kAudioObjectUnknown else { return }
        let level = Float32(min(max(newValue, 0), 1))

        if level > 0, isMuted {
            toggleMute()
        }

        if !writeScalar(device: device, element: kAudioObjectPropertyElementMain, value: level) {
            var wroteAny = false
            for element in UInt32(1) ... UInt32(4)
            where writeScalar(device: device, element: element, value: level) {
                wroteAny = true
            }
            guard wroteAny else { return }
        }
        volume = level

        // Dragging all the way down is a mute, as macOS treats it.
        if level == 0, !isMuted {
            toggleMute()
        }
    }

    /// Toggles mute, with the reference's software fallback for devices that
    /// expose no mute property at all: remember the level, write zero, and
    /// restore it on the way back.
    func toggleMute() {
        let device = currentDeviceID
        guard device != kAudioObjectUnknown else {
            performSoftwareMuteToggle()
            return
        }
        guard AudioObjectHasProperty(device, &Self.muteAddress) else {
            performSoftwareMuteToggle()
            return
        }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            device, &Self.muteAddress, 0, nil, &size, &muted
        ) == noErr else {
            performSoftwareMuteToggle()
            return
        }

        var newValue: UInt32 = muted == 0 ? 1 : 0
        guard AudioObjectSetPropertyData(
            device, &Self.muteAddress, 0, nil, size, &newValue
        ) == noErr else {
            performSoftwareMuteToggle()
            return
        }
        isMuted = newValue != 0
    }

    private func performSoftwareMuteToggle() {
        let device = currentDeviceID
        guard device != kAudioObjectUnknown else { return }

        if softwareMuted {
            let restored = min(max(volumeBeforeSoftwareMute, 0), 1)
            _ = writeScalar(
                device: device, element: kAudioObjectPropertyElementMain, value: restored
            )
            volume = restored
            softwareMuted = false
        } else {
            let current = currentVolume()
            if current > 0.001 { volumeBeforeSoftwareMute = current }
            _ = writeScalar(device: device, element: kAudioObjectPropertyElementMain, value: 0)
            volume = 0
            softwareMuted = true
        }
        isMuted = softwareMuted
    }

    /// The current output device's name, for the dashboard chip.
    var currentDeviceName: String {
        devices.first { $0.id == currentDeviceID }?.name ?? "Output"
    }

    /// The glyph for the current output device, or a generic speaker.
    var currentSymbol: String {
        devices.first { $0.id == currentDeviceID }?.symbolName ?? "speaker.wave.2.fill"
    }

    /// Cycles the default output to the next available device.
    func cycleToNextDevice() {
        if devices.isEmpty {
            refresh()
        }
        let list = devices
        guard list.count > 1,
              let index = list.firstIndex(where: { $0.id == currentDeviceID })
        else { return }
        select(list[(index + 1) % list.count])
    }

    /// Switches the system default output. Alerts and UI sounds use a
    /// separate device property, so both are set — otherwise switching to
    /// headphones left system sounds playing out of the speakers.
    func select(_ device: Device) {
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var deviceID = device.id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultOutputAddress,
            0, nil, size, &deviceID
        )
        guard status == noErr else { return }

        var systemID = device.id
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.systemOutputAddress,
            0, nil, size, &systemID
        )

        currentDeviceID = device.id
        attachVolumeListener()
        readVolume()
    }

    // MARK: - CoreAudio queries

    private static func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            0, nil, &size, &deviceID
        )
        return deviceID
    }

    private static func outputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputStreams(id), let name = name(of: id) else { return nil }
            return Device(id: id, name: name, transport: transport(of: id))
        }
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0
        else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, buffer) == noErr else {
            return false
        }
        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let name else {
            return nil
        }
        let resolved = name.takeUnretainedValue() as String
        return resolved.isEmpty ? nil : resolved
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return transport
    }
}
