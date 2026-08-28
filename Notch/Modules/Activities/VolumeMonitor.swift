import CoreAudio
import Foundation

/// Event-driven observer of the system output volume (CoreAudio property
/// listeners — no polling, no permissions). Reports level and mute changes so
/// the notch can act as a volume HUD.
final class VolumeMonitor {
    /// Called on the main queue with (level 0...1, isMuted).
    var onChange: ((Float, Bool) -> Void)?

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var isRunning = false

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
    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleChange()
        }
        listenerBlock = block

        // Track default-device swaps (AirPods connect, display speakers…)
        // so the volume listeners always follow the active output.
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultDeviceAddress,
            .main
        ) { [weak self] _, _ in
            self?.attachToDefaultDevice(reportInitial: false)
        }

        attachToDefaultDevice(reportInitial: false)
    }

    private func attachToDefaultDevice(reportInitial: Bool) {
        guard let block = listenerBlock else { return }

        if deviceID != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.volumeAddress, .main, block)
            AudioObjectRemovePropertyListenerBlock(deviceID, &Self.muteAddress, .main, block)
        }

        var newDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultDeviceAddress,
            0, nil, &size, &newDevice
        )
        guard status == noErr, newDevice != kAudioObjectUnknown else {
            deviceID = AudioObjectID(kAudioObjectUnknown)
            return
        }
        deviceID = newDevice

        if AudioObjectHasProperty(deviceID, &Self.volumeAddress) {
            AudioObjectAddPropertyListenerBlock(deviceID, &Self.volumeAddress, .main, block)
        }
        if AudioObjectHasProperty(deviceID, &Self.muteAddress) {
            AudioObjectAddPropertyListenerBlock(deviceID, &Self.muteAddress, .main, block)
        }

        if reportInitial {
            handleChange()
        }
    }

    private func handleChange() {
        guard let state = currentState() else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(state.level, state.muted)
        }
    }

    func currentState() -> (level: Float, muted: Bool)? {
        guard deviceID != kAudioObjectUnknown else { return nil }

        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &Self.volumeAddress, 0, nil, &size, &level
        ) == noErr else { return nil }

        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(deviceID, &Self.muteAddress) {
            AudioObjectGetPropertyData(deviceID, &Self.muteAddress, 0, nil, &muteSize, &muted)
        }

        return (min(max(level, 0), 1), muted != 0)
    }
}
