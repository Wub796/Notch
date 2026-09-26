import CoreAudio
import Foundation

/// A listen-only tap of everything the machine is playing, reduced to three
/// band energies.
///
/// This is the visualiser's honest source. A tap carries the mixed output
/// samples themselves, so the bars can be the music instead of a shape
/// inferred from the volume slider. It is the same CoreAudio mechanism the
/// per-app mixer uses (`MixerStrip`), with the two decisions reversed that
/// make a strip a strip:
///
/// * **It taps everything.** `stereoGlobalTapButExcludeProcesses: []` is the
///   whole output mix, no process excluded — including this one, whose mixer
///   replays the apps it carries. Excluding ourselves would blank the bars the
///   moment a user touched a per-app slider, because in that configuration the
///   copy of the app's audio that reaches the speakers is rendered by Notch.
///   The trade-off runs the other way and is the harmless direction: an app the
///   mixer has taken over may be measured twice while it is being replayed, so
///   the bars can read a little loud until it is reset — where the alternative
///   is a meter that sits at zero with music playing.
/// * **It does not mute.** A strip mutes what it taps, because its replayed
///   copy is meant to be the only one; a meter that muted would silence the
///   Mac the moment the bars started moving.
///
/// Nothing leaves this class except three numbers. The samples are measured
/// inside the render callback, mixed to mono into a buffer allocated before
/// the callback ever runs, and are never copied, queued or written anywhere.
///
/// The tap needs macOS 14.2, the same floor as per-app volume, and macOS may
/// ask for audio-capture permission the first time one is created —
/// `NSAudioCaptureUsageDescription` in Info.plist is what that prompt shows.
/// If either is missing, `start()` fails with a reason and the visualiser
/// keeps its volume-driven motion rather than showing a dead bar.
final class AudioSpectrumTap {
    /// How many frames one callback will ever be measured with. The scratch
    /// buffer is sized once, so a longer callback is truncated to this rather
    /// than allocating on the audio thread. Callbacks are a few hundred
    /// frames; the ceiling is there so a pathological size cannot overrun it.
    private static let frameCapacity = 4_096

    /// Channel pointers are cached for the same reason: an interleaved tap
    /// hands over one buffer per stream and a non-interleaved one hands over
    /// one per channel, so the mixer below wants an array of base pointers,
    /// and building that array per callback would allocate on the audio
    /// thread. Eight is more than any tap delivers.
    private static let channelCapacity = 8

    private let analyzer = AudioBandAnalyzer()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    private var scratch: UnsafeMutablePointer<Float>?
    private var channelPointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>?
    private var scratchFrames = 0

    private var sampleRate: Double = 48_000
    private var isNonInterleaved = true

    /// Guards the two fields below, which are written where the CoreAudio work
    /// runs (the meter's serial control queue) and read on the main thread —
    /// the meter publishes at 30Hz. The render callback touches neither, so a
    /// plain lock is safe here: `bands` is the only thing shared with the audio
    /// thread, and `AudioBandAnalyzer` guards it with a *try*-lock precisely so
    /// that path can never block.
    private let stateLock = NSLock()
    private var running = false
    private var reason: String?

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    var failureReason: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return reason
    }

    private func setRunning(_ value: Bool) {
        stateLock.lock()
        running = value
        stateLock.unlock()
    }

    private func setFailureReason(_ value: String?) {
        stateLock.lock()
        reason = value
        stateLock.unlock()
    }

    /// The band energies last measured, 0...1, low/mid/high — empty of audio
    /// when the tap is not running.
    var bands: [Float] {
        isRunning ? analyzer.bands : [0, 0, 0]
    }

    // MARK: - Control thread

    /// Creates the tap and its aggregate device and starts measuring. False
    /// with `failureReason` set when the platform or CoreAudio says no; the
    /// caller is expected to fall back rather than to retry in a loop.
    ///
    /// Called from the meter's serial control queue, never from the main
    /// thread: building a tap asks the system to authorise audio capture and to
    /// construct a device graph, either of which can wait an unbounded moment —
    /// and doing that inline is what froze the panel when the audio surface was
    /// opened. The tap exists only while something is playing —
    /// `NotchState.syncAudioMeter` starts and stops it with playback — so a Mac
    /// with nothing playing has no tap of ours at all.
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        guard #available(macOS 14.2, *) else {
            setFailureReason("Measuring the output mix needs macOS 14.2 or later.")
            return false
        }
        guard allocateBuffers() else {
            setFailureReason("Couldn't allocate the meter's buffers.")
            return false
        }

        guard let tapUID = createTap() else {
            releaseBuffers()
            return false
        }
        guard let aggregate = createAggregate(tapUID: tapUID) else {
            destroyTap()
            releaseBuffers()
            return false
        }
        aggregateID = aggregate
        readTapFormat()
        analyzer.prepare(sampleRate: sampleRate)

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { [weak self] _, inputData, _, _, _ in
            // Only the input side is read: the tap's audio arrives as this
            // device's input and there is nothing to play back, because the
            // tap is unmuted and the app is not in the audio path.
            self?.measure(
                input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            )
        }
        guard status == noErr, let procID else {
            setFailureReason("CoreAudio refused the meter's callback (\(status)).")
            teardown()
            return false
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            setFailureReason("CoreAudio refused to start the meter (\(startStatus)).")
            teardown()
            return false
        }

        setFailureReason(nil)
        setRunning(true)
        return true
    }

    /// Tears the tap down. Any audio-capture the system granted jots back to
    /// nothing — no tap, no aggregate, no callback, and no samples anywhere.
    func stop() {
        guard isRunning || aggregateID != AudioObjectID(kAudioObjectUnknown) || tapID != AudioObjectID(kAudioObjectUnknown) else {
            return
        }
        teardown()
        setRunning(false)
    }

    // MARK: - CoreAudio plumbing

    @available(macOS 14.2, *)
    private func createTap() -> CFString? {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        // Left at `.unmuted` on purpose — see the type's note. This is the one
        // difference from `MixerStrip` that must not be got wrong: muting the
        // system mix to measure it would be audible silence.
        description.muteBehavior = CATapMuteBehavior.unmuted
        description.isPrivate = true
        description.name = "Notch Meter"

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr, newTapID != AudioObjectID(kAudioObjectUnknown) else {
            // The common failures are a refused audio-capture permission and a
            // tap that can't be built for the current output device; the hint
            // covers the first without claiming to know which one it was.
            setFailureReason("Couldn't read the output mix (\(status)) — if macOS is "
                + "holding back audio access, allow Notch under Privacy & Security.")
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
            // A tap that was created but cannot be named is a tap that would
            // leak until the next teardown, so it goes back now: a failed
            // start must leave nothing of ours in the audio system.
            setFailureReason("The meter's tap didn't report its UID (\(uidStatus)).")
            destroyTap()
            return nil
        }
        return uid
    }

    /// An aggregate device holding nothing but the tap. It has no sub-devices
    /// and no output: a tap is delivered as this device's input, and nothing
    /// is ever rendered back out. That is the standard shape for
    /// measurement-only taps, and the reason a *private* aggregate is used at
    /// all — it must not appear in the user's sound settings as a device they
    /// never chose.
    private func createAggregate(tapUID: CFString) -> AudioObjectID? {
        var newID = AudioObjectID(kAudioObjectUnknown)
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notch Meter",
            kAudioAggregateDeviceUIDKey: "com.notchapp.Notch.meter.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newID)
        guard status == noErr, newID != AudioObjectID(kAudioObjectUnknown) else {
            setFailureReason("Couldn't build the meter's device (\(status)).")
            return nil
        }
        return newID
    }

    /// The tap's own stream format, because the mixdown below has to know
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
        // Only the layout matters to a meter: interleaved frames all live in
        // one buffer, non-interleaved ones each get their own, and the two are
        // read differently below.
        isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
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
        releaseBuffers()
        analyzer.reset()
        // `failureReason` is deliberately *not* cleared here: every failure
        // path sets it and then tears the half-built tap down, so clearing it
        // in teardown would erase the only explanation the caller ever gets.
        // `start()` clears it on the way to a working tap instead.
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

    private func allocateBuffers() -> Bool {
        if scratch == nil {
            scratch = UnsafeMutablePointer<Float>.allocate(capacity: Self.frameCapacity)
            scratchFrames = Self.frameCapacity
        }
        if channelPointers == nil {
            channelPointers = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(
                capacity: Self.channelCapacity
            )
        }
        return scratch != nil && channelPointers != nil
    }

    private func releaseBuffers() {
        scratch?.deallocate()
        scratch = nil
        channelPointers?.deallocate()
        channelPointers = nil
        scratchFrames = 0
    }

    // MARK: - Audio thread

    /// Mixes the tap's channels down to one and measures it.
    ///
    /// Realtime rules apply: the two buffers were allocated before the callback
    /// started, every loop bound was computed from the format, and anything
    /// unexpected leaves the levels alone for this callback rather than
    /// crashing or allocating. Mono is not a compromise — the bars show how
    /// loud each range is across the whole mix, and a stereo pair's two
    /// channels of a kick are the same kick.
    private func measure(input: UnsafeMutableAudioBufferListPointer) {
        guard let scratch, let channelPointers, !input.isEmpty else { return }

        let frames: Int
        if isNonInterleaved {
            // One buffer per channel.
            let buffers = min(input.count, Self.channelCapacity)
            var usable = 0
            var available = Int.max
            for buffer in 0..<buffers {
                guard let memory = input[buffer].mData else { continue }
                channelPointers[usable] = memory.assumingMemoryBound(to: Float.self)
                // The shortest channel bounds all of them: a buffer list whose
                // channels disagree would otherwise read past the small one.
                available = min(available, Int(input[buffer].mDataByteSize) / MemoryLayout<Float>.size)
                usable += 1
            }
            guard usable > 0, available > 0 else { return }
            frames = min(available, scratchFrames)
            guard frames > 0 else { return }

            let scale = 1 / Float(usable)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<usable {
                    sum += channelPointers[channel]![frame]
                }
                scratch[frame] = sum * scale
            }
        } else {
            // One buffer, every channel's frames in turn.
            guard let memory = input[0].mData else { return }
            let data = memory.assumingMemoryBound(to: Float.self)
            let channels = max(min(Int(input[0].mNumberChannels), Self.channelCapacity), 1)
            let available = Int(input[0].mDataByteSize) / MemoryLayout<Float>.size
            frames = min(available / channels, scratchFrames)
            guard frames > 0 else { return }

            let scale = 1 / Float(channels)
            for frame in 0..<frames {
                var sum: Float = 0
                let base = frame * channels
                for channel in 0..<channels {
                    sum += data[base + channel]
                }
                scratch[frame] = sum * scale
            }
        }

        analyzer.analyze(scratch, count: frames)
    }
}
