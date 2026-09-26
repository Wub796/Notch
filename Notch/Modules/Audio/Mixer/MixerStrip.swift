import CoreAudio
import Foundation

/// One app's audio path.
///
/// The app's audio is tapped out of the system, silenced at the source
/// (`mutedWhenTapped`), and replayed through a private aggregate device whose
/// render callback is this strip — which is where its gain, EQ, AutoEQ
/// correction and loudness compensation are applied, and where "which output
/// device" is decided. That indirection is not a preference: current macOS no
/// longer lets a client set another process's output level, so a tap-and-replay
/// path is the only way left to make one app quieter than the others.
///
/// Nothing else in the process does anything on this app's behalf: a strip
/// exists only while the app has a setting that isn't unity (see `MixerEngine`),
/// and every create/destroy happens on the engine's serial control queue rather
/// than on the main thread — building a tap constructs a device graph and can
/// wait on the audio system, which is a frozen panel when the UI is the caller —
/// so an app the user never touched has no tap, no aggregate, and no render
/// callbacks.
final class MixerStrip {
    /// The bundle id this strip is carrying. Stability matters: the engine keys
    /// its settings by it, and the process objects behind it are re-resolved
    /// when the app is relaunched.
    let appID: String

    /// Guards the lifecycle fields below, which are written where the CoreAudio
    /// work runs (the engine's control queue) and read from the main thread:
    /// `reconcile` decides with them, and the mixer's rows read `failures`.
    private let lifecycleLock = NSLock()
    private var running = false
    private var starting = false
    private var reason: String?

    var isRunning: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return running
    }

    var failureReason: String? {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return reason
    }

    /// Whether this strip is meant to be up: running, or somewhere between the
    /// engine asking for it and the tap actually existing.
    ///
    /// `reconcile` asks this rather than `isRunning`, and that is load-bearing —
    /// a start is asynchronous, so a second pass arriving while the first is
    /// still building would otherwise read "not running" and create a *second*
    /// strip for the same app, orphaning the tap already on its way up.
    var isActive: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return running || starting
    }

    /// Marks the strip as on its way up, on the caller's thread, before the
    /// control queue gets to it. The engine calls this as it hands the strip
    /// over — see `isActive` for why it cannot wait for the queue.
    func markStarting() {
        lifecycleLock.lock()
        starting = true
        lifecycleLock.unlock()
    }

    private func setRunning(_ value: Bool) {
        lifecycleLock.lock()
        running = value
        // Reaching either end of the transition settles the strip, however it
        // got there: a start that failed is no longer on its way up.
        starting = false
        lifecycleLock.unlock()
    }

    private func setFailureReason(_ value: String?) {
        lifecycleLock.lock()
        reason = value
        lifecycleLock.unlock()
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    /// Gain at unity until told otherwise, so a strip that starts before its
    /// settings arrive passes audio through unchanged rather than silencing it.
    private var gain: Float = 1
    /// Applied when boosting. A 4x lift on a track that is already near full
    /// scale would square off into hard clipping; the soft knee keeps that from
    /// sounding like a fault in the app being boosted.
    private var usesSoftClip = true
    private let filters = BiquadCascade()

    private let processObjects: [AudioObjectID]
    private var outputDeviceID: AudioObjectID
    private var outputDeviceUID: String
    private var sampleRate: Double
    private var channelCount = 2
    private var isNonInterleaved = true

    init(
        appID: String,
        processObjects: [AudioObjectID],
        outputDeviceID: AudioObjectID,
        outputDeviceUID: String,
        sampleRate: Double
    ) {
        self.appID = appID
        self.processObjects = processObjects
        self.outputDeviceID = outputDeviceID
        self.outputDeviceUID = outputDeviceUID
        self.sampleRate = sampleRate
    }

    // MARK: - Control thread

    /// Gain and filter chain, set from the main thread at any time — the render
    /// callback reads whatever was last stored.
    func apply(gain: Float, filters sections: [Biquad], channelCount: Int) {
        self.gain = max(gain, 0)
        filters.prepare(sections: sections, channelCount: max(channelCount, 1))
    }

    /// True when this strip would change nothing about the app's audio: unity
    /// gain and an empty chain. The engine uses it to decide whether the tap is
    /// worth having at all.
    var isTransparent: Bool {
        abs(gain - 1) < 0.0005 && filters.isEmpty
    }

    /// Creates the tap and its aggregate device and starts rendering. Returns
    /// false with `failureReason` set when the platform or CoreAudio says no —
    /// on 14.0 and 14.1 that is every time, which the UI states plainly rather
    /// than showing controls that do nothing.
    ///
    /// Called on the engine's control queue, never on the main thread: creating
    /// a tap asks the system for audio-capture access and builds a private
    /// aggregate device, and either can wait an unbounded moment.
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        guard !processObjects.isEmpty else {
            setFailureReason("This app has no audio process to tap yet.")
            return false
        }
        guard #available(macOS 14.2, *) else {
            setFailureReason("Per-app volume needs macOS 14.2 or later.")
            return false
        }

        guard let tapUID = createTap() else { return false }
        guard let aggregate = createAggregate(tapUID: tapUID) else {
            destroyTap()
            return false
        }
        aggregateID = aggregate
        readTapFormat()

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { [weak self] _, inputData, _, outputData, _ in
            self?.render(
                input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData)),
                output: UnsafeMutableAudioBufferListPointer(outputData)
            )
        }
        guard status == noErr, let procID else {
            setFailureReason("CoreAudio refused the render callback (\(status)).")
            teardown()
            return false
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            setFailureReason("CoreAudio refused to start the device (\(startStatus)).")
            teardown()
            return false
        }

        setFailureReason(nil)
        setRunning(true)
        return true
    }

    /// Tears the strip down: no tap, no aggregate, no callback, and the app is
    /// back to playing through the system exactly as it did before. Also called
    /// on the control queue — destroying an aggregate device waits on the audio
    /// system for the same reason creating one does.
    func stop() {
        guard isRunning || aggregateID != AudioObjectID(kAudioObjectUnknown) || tapID != AudioObjectID(kAudioObjectUnknown) else { return }
        teardown()
        setRunning(false)
    }

    // MARK: - CoreAudio plumbing

    @available(macOS 14.2, *)
    private func createTap() -> CFString? {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        // The whole mechanism: once something reads the tap, the app's own
        // output stops, so what the user hears is this strip's output rather
        // than the app's audio plus a copy of it.
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped
        description.isPrivate = true
        description.name = "Notch Mixer — \(appID)"

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr, newTapID != AudioObjectID(kAudioObjectUnknown) else {
            setFailureReason("Couldn't tap this app's audio (\(status)).")
            return nil
        }
        tapID = newTapID

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, pointer)
        }
        guard uidStatus == noErr else {
            setFailureReason("The tap didn't report its UID (\(uidStatus)).")
            return nil
        }
        return uid
    }

    /// A private aggregate device whose sub-device is the chosen output and
    /// whose tap is the one above: the tap's audio arrives as this device's
    /// input, the callback below turns it into that output's audio.
    private func createAggregate(tapUID: CFString) -> AudioObjectID? {
        var newID = AudioObjectID(kAudioObjectUnknown)
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notch Mixer — \(appID)",
            kAudioAggregateDeviceUIDKey: "com.notchapp.Notch.mixer.\(UUID().uuidString)",
            // Private so it never shows up in System Settings or another app's
            // device list — this is plumbing, not a device the user chose.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]
            ],
            // The tap starts when the device does, rather than needing the
            // audio system to notice it separately.
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newID)
        guard status == noErr, newID != AudioObjectID(kAudioObjectUnknown) else {
            setFailureReason("Couldn't build the mixing device (\(status)).")
            return nil
        }
        return newID
    }

    /// The tap's own stream format, because the render callback has to know
    /// whether it is handed one buffer of interleaved frames or one buffer per
    /// channel — and taps are not guaranteed to be either across releases.
    private func readTapFormat() {
        guard tapID != AudioObjectID(kAudioObjectUnknown) else { return }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr else { return }
        if format.mSampleRate > 0 { sampleRate = format.mSampleRate }
        let channels = max(Int(format.mChannelsPerFrame), 1)
        channelCount = channels
        isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        filters.prepare(sections: [], channelCount: channels)
    }

    private func teardown() {
        if let ioProcID {
            if aggregateID != AudioObjectID(kAudioObjectUnknown) {
                AudioDeviceStop(aggregateID, ioProcID)
            }
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        destroyTap()
        filters.reset()
    }

    private func destroyTap() {
        guard tapID != AudioObjectID(kAudioObjectUnknown) else { return }
        // Only ever non-zero on 14.2+, where the create call above succeeded,
        // but the guard keeps this file compiling against an older target.
        if #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Audio thread

    /// Copies the tap's audio to the output with level and filters applied.
    ///
    /// Realtime rules apply here: no allocation, no locks beyond the filter
    /// chain's own spin lock, no Swift runtime calls that could allocate. Every
    /// value it needs was computed on the main thread, and anything unexpected
    /// (a buffer list that doesn't match the format) results in a copy rather
    /// than silence — a wrong tap should sound like the app, not like a fault.
    private func render(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer
    ) {
        guard output.count > 0 else { return }
        let framesPerChannel = max(channelCount, 1)

        if isNonInterleaved {
            for channel in 0..<min(framesPerChannel, min(input.count, output.count)) {
                guard let source = input[channel].mData?.assumingMemoryBound(to: Float.self),
                      let destination = output[channel].mData?.assumingMemoryBound(to: Float.self)
                else { continue }
                let frames = Int(min(input[channel].mDataByteSize, output[channel].mDataByteSize)) / MemoryLayout<Float>.size
                guard frames > 0 else { continue }
                destination.update(from: source, count: frames)
                applyLevelAndFilters(destination, frames: frames, channel: channel, stride: 1)
            }
            return
        }

        // Interleaved: one buffer holds every channel's frames in turn, so each
        // channel is processed with a stride equal to the channel count.
        guard let source = input[0].mData?.assumingMemoryBound(to: Float.self),
              let destination = output[0].mData?.assumingMemoryBound(to: Float.self)
        else { return }
        let frames = Int(min(input[0].mDataByteSize, output[0].mDataByteSize)) / MemoryLayout<Float>.size
        guard frames > 0 else { return }
        destination.update(from: source, count: frames)
        for channel in 0..<framesPerChannel {
            let offset = min(channel, frames - 1)
            applyLevelAndFilters(destination + offset, frames: frames / framesPerChannel, channel: channel, stride: framesPerChannel)
        }
    }

    /// In-place gain and filtering for one channel's frames.
    private func applyLevelAndFilters(
        _ samples: UnsafeMutablePointer<Float>,
        frames: Int,
        channel: Int,
        stride: Int
    ) {
        var index = 0
        if gain != 1 {
            for _ in 0..<frames {
                let value = samples[index]
                samples[index] = scaled(value)
                index += stride
            }
        }
        filters.process(channel: channel, samples: samples, frameCount: frames, stride: stride)
    }

    @inline(__always)
    private func scaled(_ value: Float) -> Float {
        let scaled = value * gain
        // Only above unity: a cut needs no protection, and the knee would
        // otherwise add harmonics to quiet material for no reason.
        guard usesSoftClip, gain > 1 else { return scaled }
        if scaled > 1 || scaled < -1 {
            return tanhf(scaled)
        }
        return scaled
    }
}
