import AudioToolbox // kAudioHardwareServiceDeviceProperty_VirtualMainVolume
import CoreAudio
import Foundation
import Observation

/// Lists CoreAudio input devices (microphones), switches the system default
/// input, and reads/writes each device's input level — the FineTune-style
/// mic control for the Audio screen.
///
/// Volume is read and written through the virtual main volume property on the
/// input scope when the device exposes it (this is what matches the System
/// Settings input slider), falling back to per-element scalars like the
/// output manager does.
@Observable
final class AudioInputManager {
    struct InputDevice: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let transport: UInt32

        var symbolName: String {
            switch transport {
            case kAudioDeviceTransportTypeBluetooth,
                 kAudioDeviceTransportTypeBluetoothLE:
                "airpods"
            case kAudioDeviceTransportTypeUSB:
                "mic.fill"
            case kAudioDeviceTransportTypeBuiltIn:
                "mic.fill"
            default:
                "waveform.badge.mic"
            }
        }
    }

    private(set) var devices: [InputDevice] = []
    private(set) var currentDeviceID: AudioDeviceID = 0

    /// Input volume of the current device, 0...1, and its mute state.
    private(set) var volume: Float = 1
    private(set) var isMuted = false

    /// Software mute fallback for devices without an input mute property.
    private var softwareMuted = false
    private var volumeBeforeSoftwareMute: Float = 1

    private var isListening = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    private let audioQueue = DispatchQueue(label: "com.notch.audio-input", qos: .utility)
    private var pendingRefresh: DispatchWorkItem?

    private static var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
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
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    func refresh() {
        refreshOnAudioQueue()
    }

    /// Starts persistent listeners so mic state stays current without polling
    /// — the input equivalent of `AudioOutputManager.startListening()`.
    func startListening() {
        guard !isListening else { return }
        isListening = true

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.pendingRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.refreshOnAudioQueue()
            }
            self.pendingRefresh = work
            self.audioQueue.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultInputAddress, audioQueue, block
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.deviceListAddress, audioQueue, block
        )
        refreshOnAudioQueue()
    }

    private func refreshOnAudioQueue() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let devices = Self.inputDevices()
            let deviceID = Self.defaultInputDevice()

            var volume = self.volume
            if deviceID != kAudioObjectUnknown,
               let read = Self.readInputVolume(device: deviceID) {
                volume = read
            }

            var muted: UInt32 = 0
            var muteSize = UInt32(MemoryLayout<UInt32>.size)
            var isMuted = self.isMuted
            if deviceID != kAudioObjectUnknown,
               AudioObjectHasProperty(deviceID, &Self.muteAddress),
               AudioObjectGetPropertyData(
                   deviceID, &Self.muteAddress, 0, nil, &muteSize, &muted
               ) == noErr {
                isMuted = muted != 0
            } else if self.softwareMuted {
                isMuted = true
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.devices = devices
                self.currentDeviceID = deviceID
                self.volume = volume
                self.isMuted = isMuted
            }
        }
    }

    /// Switches the system default input device.
    func select(_ device: InputDevice) {
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceID = device.id
        guard AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultInputAddress,
            0, nil, size, &deviceID
        ) == noErr else { return }
        currentDeviceID = device.id
        refreshOnAudioQueue()
    }

    /// Sets the current input device's level, matching the System Settings
    /// slider via the virtual main volume property when available.
    func setVolume(_ newValue: Float) {
        let device = currentDeviceID
        guard device != kAudioObjectUnknown else { return }
        let level = Float32(min(max(newValue, 0), 1))

        if level > 0, isMuted {
            toggleMute()
        }
        if !Self.writeInputVolume(device: device, level: level) {
            return
        }
        volume = level
    }

    /// Toggles input mute, with a software fallback for devices that expose
    /// no input mute property: remember the level, write zero, restore on
    /// the way back.
    func toggleMute() {
        let device = currentDeviceID
        guard device != kAudioObjectUnknown else { return }

        if !AudioObjectHasProperty(device, &Self.muteAddress) {
            performSoftwareMuteToggle(device: device)
            return
        }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            device, &Self.muteAddress, 0, nil, &size, &muted
        ) == noErr else {
            performSoftwareMuteToggle(device: device)
            return
        }

        var newValue: UInt32 = muted == 0 ? 1 : 0
        guard AudioObjectSetPropertyData(
            device, &Self.muteAddress, 0, nil, size, &newValue
        ) == noErr else {
            performSoftwareMuteToggle(device: device)
            return
        }
        isMuted = newValue != 0
    }

    private func performSoftwareMuteToggle(device: AudioDeviceID) {
        if softwareMuted {
            let restored = min(max(volumeBeforeSoftwareMute, 0), 1)
            _ = Self.writeInputVolume(device: device, level: restored)
            volume = restored
            softwareMuted = false
        } else {
            let current = Self.readInputVolume(device: device) ?? volume
            if current > 0.001 { volumeBeforeSoftwareMute = current }
            _ = Self.writeInputVolume(device: device, level: 0)
            volume = 0
            softwareMuted = true
        }
        isMuted = softwareMuted
    }

    // MARK: - CoreAudio queries

    /// Reads an input device's level: virtual main volume first (matches the
    /// System Settings slider), then per-element scalars.
    private static func readInputVolume(device: AudioDeviceID) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device, &address) {
            var level = Float32(1)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level) == noErr {
                return min(max(level, 0), 1)
            }
        }
        for element in [kAudioObjectPropertyElementMain, UInt32(1)] {
            var scalar = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &scalar) else { continue }
            var needed: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &scalar, 0, nil, &needed) == noErr,
                  needed == UInt32(MemoryLayout<Float32>.size)
            else { continue }
            var level = Float32(1)
            var size = needed
            if AudioObjectGetPropertyData(device, &scalar, 0, nil, &size, &level) == noErr {
                return min(max(level, 0), 1)
            }
        }
        return nil
    }

    @discardableResult
    private static func writeInputVolume(device: AudioDeviceID, level: Float32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device, &address) {
            var value = level
            let size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr {
                return true
            }
        }
        var scalar = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &scalar) else { return false }
        var value = level
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &scalar, 0, nil, size, &value) == noErr
    }

    private static func defaultInputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            0, nil, &size, &deviceID
        )
        return deviceID
    }

    private static func inputDevices() -> [InputDevice] {
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
            guard hasInputStreams(id), let name = name(of: id) else { return nil }
            return InputDevice(id: id, name: name, transport: transport(of: id))
        }
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
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
