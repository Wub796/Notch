import AppKit
import Foundation
import Observation

/// The measured source behind the closed notch's bars.
///
/// This class is the lifecycle and the publication, not the measurement: the
/// samples are read and split into bands by `AudioSpectrumTap`, which exists
/// only while something is playing. What lives here is the timer that copies
/// the tap's latest band levels onto the main thread at 30Hz, plus the two
/// states the UI needs to tell the truth — whether the meter is live at all,
/// and why it is not.
///
/// It also owns how many bands that is, because the count is a setting rather
/// than a property of the tap: the user can move between three and five bars
/// while the music is playing, and the change has to reach both the analyzer
/// that measures the bands and the view that draws them.
///
/// There is no permission this class can check. macOS either lets the tap be
/// created or refuses it in the call itself (see `AudioSpectrumTap`), so the
/// failure it surfaces is a CoreAudio status and a hint, never a guess at what
/// the privacy database thinks.
///
/// When the tap cannot start — an older macOS, or audio access refused —
/// `isLive` stays false and the visualiser stays still rather than pretending
/// to show frequency data. `failureReason` says why in Settings and on the
/// Audio surface.
@Observable
final class SystemAudioMeter {
    private(set) var bands: [Float] = [Float](repeating: 0, count: AudioBandAnalyzer.defaultBandCount)

    /// How many bands are measured, and therefore how many bars the view has
    /// data for. Kept clamped to what the analyzer offers, so the count the
    /// bars draw and the count the tap measures cannot drift apart.
    private(set) var bandCount = AudioBandAnalyzer.defaultBandCount

    /// True only while the tap is running, which is exactly when `bands` is a
    /// measurement rather than three zeros waiting for one.
    private(set) var isLive = false

    /// Why the meter is not measuring, when it is not. Survives a stop on
    /// purpose: playback ending is not a fix, and a reason that vanished with
    /// the music would be unreadable in the one place the user goes to look.
    private(set) var failureReason: String?

    /// Whether this Mac can measure the output mix at all. The tap API landed
    /// in macOS 14.2, so on 14.0 and 14.1 the waveform stays idle rather than
    /// suggesting the volume setting contains frequency information.
    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    /// The last failure, mirrored for views that have no handle on the live
    /// meter — the visualiser settings live in a pane that cannot reach
    /// `NotchState`, and that pane is where the user can act on the reason.
    private(set) static var lastFailureReason: String?

    private let tap = AudioSpectrumTap()
    private var timer: Timer?

    /// Where every CoreAudio call happens, one at a time.
    ///
    /// Building a process tap constructs a device graph and asks the system to
    /// authorise audio capture; either can wait an unbounded moment. Doing that
    /// inline on the thread that asked for it is what froze the whole notch
    /// when the audio surface was opened, so `start()` and `stop()` are now
    /// requests: the work happens here, and the result is published on main.
    private let controlQueue = DispatchQueue(
        label: "com.notchapp.Notch.meter.control",
        qos: .userInitiated
    )

    /// True while a tap is being built. Both this and `generation` are touched
    /// only from the main thread (the `start`/`stop` callers and the completion
    /// hop), so neither needs a lock.
    private var isStarting = false

    /// Bumped by every start and stop. A start whose completion arrives after a
    /// stop — or after a newer start — throws its own tap away rather than
    /// leaving one running with nothing driving it.
    private var generation: UInt64 = 0

    /// Starts measuring, if it can. Cheap to call while already running, and
    /// safe to call again after the user grants audio access in System
    /// Settings: a refusal leaves no timer behind, so the next call is a real
    /// retry — nothing here caches a refusal and no relaunch is needed.
    ///
    /// Returns immediately. `isLive` and `failureReason` are published on the
    /// main thread once the tap has actually been built (or refused), which is
    /// why the visualiser stays still until it can show real band magnitudes.
    func start() {
        guard timer == nil, !isStarting else { return }
        isStarting = true
        generation &+= 1
        let token = generation

        controlQueue.async { [weak self] in
            guard let self else { return }
            #if DEBUG
            print("[Notch] meter: building the output tap")
            #endif
            let started = self.tap.start()
            #if DEBUG
            if started {
                print("[Notch] meter: tap running")
            } else {
                print("[Notch] meter: tap refused — \(self.tap.failureReason ?? "no reason given")")
            }
            #endif

            DispatchQueue.main.async {
                self.isStarting = false
                guard self.generation == token else {
                    // A stop landed while this tap was being built, so it must
                    // not be left running. Queued rather than called here: the
                    // teardown belongs behind whatever the queue is doing.
                    self.queueTapStop()
                    return
                }

                self.publish()
                if started {
                    self.failureReason = nil
                    Self.lastFailureReason = nil
                    self.beginPublishing()
                } else {
                    self.failureReason = self.tap.failureReason
                    Self.lastFailureReason = self.failureReason
                    // Deliberately no timer: there are no levels to publish,
                    // and one left running would make `start()`'s `timer == nil`
                    // guard refuse the retry that a granted audio permission or
                    // a newly attached output device needs.
                }
            }
        }
    }

    /// The 30Hz publication loop. Its own method so the timer closure's
    /// `[weak self]` sits in a method body rather than nested inside the
    /// completion above, which holds `self` strongly — the ownership the timer
    /// needs, without the "weak capture differs from outer scope" diagnostic.
    private func beginPublishing() {
        // 30Hz is enough to drive the bars — the analyzer already smoothed the
        // levels on the audio thread, so this only has to carry them across —
        // and it keeps the observed writes far below the audio callback rate.
        timer = Timer.scheduledRepeating(every: 1.0 / 30.0) { [weak self] in
            self?.publish()
        }
    }

    func stop() {
        generation &+= 1
        isStarting = false
        timer?.invalidate()
        timer = nil
        // Off the main thread for the same reason as the start: destroying an
        // aggregate device and its tap waits on the audio system.
        queueTapStop()
        isLive = false
        bands = [Float](repeating: 0, count: bandCount)
    }

    /// Changes how many bands are measured. Called from the main thread when
    /// the setting changes, and safe whether or not the tap is running.
    ///
    /// The published levels are re-sized here, so the bars redraw at the new
    /// count at once — idle for the moment it takes the tap to publish levels
    /// of the same length, which is the honest way round: a bar is only as
    /// tall as a measurement it actually has. The retune itself is queued
    /// with every other CoreAudio call, behind whatever the control queue is
    /// already doing.
    func setBandCount(_ count: Int) {
        let clamped = AudioBandAnalyzer.clampedBandCount(count)
        guard clamped != bandCount else { return }
        bandCount = clamped
        bands = [Float](repeating: 0, count: clamped)
        controlQueue.async { [weak self] in
            self?.tap.setBandCount(clamped)
        }
    }

    private func queueTapStop() {
        controlQueue.async { [weak self] in
            self?.tap.stop()
        }
    }

    deinit { stop() }

    /// Copies the tap's latest levels across, writing only on a change so the
    /// observation that redraws the bars fires when the music moves rather
    /// than thirty times a second regardless.
    private func publish() {
        let live = tap.isRunning
        if live != isLive { isLive = live }
        guard live else {
            let silence = [Float](repeating: 0, count: bandCount)
            if bands != silence { bands = silence }
            return
        }
        let measured = tap.bands
        if measured != bands { bands = measured }
    }
}
