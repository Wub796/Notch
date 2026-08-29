import CoreAudio
import Foundation
import Observation

/// Lists CoreAudio output devices and switches the system default — the
/// notch equivalent of Sapphire's audio device picker. Public API only.
@Observable
final class AudioOutputManager {
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

    /// State for the software mute fallback used on devices with no mute
    /// property of their own.
    private var softwareMuted = false
    private var volumeBeforeSoftwareMute: Float = 0.2

    private var isListening = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeDeviceID = AudioObjectID(kAudioObjectUnknown)

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

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func refresh() {
        devices = Self.outputDevices()
        currentDeviceID = Self.defaultOutputDevice()
        readVolume()
        startListening()
    }

    /// Keeps the picker honest when the output changes anywhere else — a
    /// headset connecting, Sound settings, or another app. Without this the
    /// list only reflected whatever was true the last time the notch opened.
    private func startListening() {
        guard !isListening else { return }
        isListening = true

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.devices = Self.outputDevices()
            self.currentDeviceID = Self.defaultOutputDevice()
            self.attachVolumeListener()
            self.readVolume()
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, block
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.deviceListAddress, .main, block
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
                AudioObjectRemovePropertyListenerBlock(volumeDeviceID, &address, .main, block)
            }
            AudioObjectRemovePropertyListenerBlock(
                volumeDeviceID, &Self.volumeAddress, .main, block
            )
            AudioObjectRemovePropertyListenerBlock(
                volumeDeviceID, &Self.muteAddress, .main, block
            )
        }

        volumeDeviceID = currentDeviceID
        guard volumeDeviceID != kAudioObjectUnknown else { return }

        for element in Self.listenerElements {
            var address = Self.scalarAddress(element: element)
            if AudioObjectHasProperty(volumeDeviceID, &address) {
                AudioObjectAddPropertyListenerBlock(volumeDeviceID, &address, .main, block)
            }
        }
        if AudioObjectHasProperty(volumeDeviceID, &Self.volumeAddress) {
            AudioObjectAddPropertyListenerBlock(
                volumeDeviceID, &Self.volumeAddress, .main, block
            )
        }
        if AudioObjectHasProperty(volumeDeviceID, &Self.muteAddress) {
            AudioObjectAddPropertyListenerBlock(
                volumeDeviceID, &Self.muteAddress, .main, block
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
        NotchTheme.Haptics.generic()
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
        NotchTheme.Haptics.generic()
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
        NotchTheme.Haptics.generic()
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
