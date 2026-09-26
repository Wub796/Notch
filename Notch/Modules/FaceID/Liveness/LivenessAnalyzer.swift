import Foundation

/// The rolling-window driver for the liveness cues.
///
/// Ported from Glance (`Liveness/LivenessAnalyzer.swift`, MIT © Jonathan Zhou).
/// It takes `LivenessFrame` rather than `FaceRecognitionResult`, which keeps its
/// dependency graph shallow enough that the decision logic never needs Vision —
/// and, more importantly here, keeps liveness genuinely independent of whether
/// the face matched: the analyzer is fed every detected face, matched or not, so
/// a bad match can't quietly starve the spoof checks of frames.
final class LivenessAnalyzer {
    private let windowDuration: TimeInterval

    /// Read fresh on every `observe()` rather than captured at init, so a
    /// settings change mid-scan takes effect immediately instead of on the next
    /// lock.
    var modeProvider: () -> LivenessMode = { .light }
    var tuningProvider: () -> LivenessTuning = { .default }
    /// The diagnostics readout can switch individual cues off to isolate one;
    /// the unlock path leaves this at "all enabled".
    var enabledCuesProvider: () -> Set<LivenessCue> = { Set(LivenessCue.allCases) }

    private var frames: [LivenessFrame] = []
    private var evaluator = LivenessEvaluator()
    private(set) var lastSnapshot = LivenessSnapshot.empty
    /// Kept for the diagnostics readout — the numbers behind the flat-vs-3D
    /// cue's level, which are otherwise impossible to interpret.
    private(set) var lastGeometry = GeometryLivenessResult.empty

    init(windowDuration: TimeInterval = 2.0) {
        self.windowDuration = windowDuration
    }

    func reset() {
        frames.removeAll()
        evaluator.reset()
        lastSnapshot = .empty
        lastGeometry = .empty
    }

    /// Call once per frame with a detected face.
    ///
    /// The window is time-pruned at about two seconds, but the evaluator's fire
    /// counts are not — they accumulate across the whole scan, so a tell can't
    /// be waited out.
    @discardableResult
    func observe(_ frame: LivenessFrame) -> LivenessSnapshot {
        frames.append(frame)
        frames.removeAll { frame.timestamp.timeIntervalSince($0.timestamp) > windowDuration }

        evaluator.mode = modeProvider()
        evaluator.tuning = tuningProvider()
        evaluator.enabledCues = enabledCuesProvider()

        let geometry = GeometryLiveness.evaluate(frames)
        lastGeometry = geometry

        let readings = LivenessCues.readings(window: frames, geometry: geometry)
        let snapshot = evaluator.observe(readings)
        lastSnapshot = snapshot
        return snapshot
    }
}
