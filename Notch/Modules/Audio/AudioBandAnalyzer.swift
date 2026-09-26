import Foundation

/// The energy in each of the three ranges the closed notch draws a bar for.
///
/// The visualiser asks one question per bar — how loud is the bottom right
/// now, and the middle, and the top — and this answers it from the samples
/// themselves rather than from anything the system reports *about* them. That
/// distinction is the whole point: the volume is one number and cannot tell
/// three bars apart, so a meter built on it draws the same shape three times.
/// Filtering the real mix into three ranges and measuring each one gives three
/// genuinely different numbers, which is what makes the bars move like the
/// music instead of like the volume slider.
///
/// The split is two crossovers, not three unrelated filters: `low` is
/// everything below the low/mid crossover, `mid` is what is left between it
/// and the mid/high crossover, and `high` is everything above that. The same
/// two edges are used on both sides of themselves, so the ranges tile the
/// spectrum instead of overlapping or leaving a gap — a kick lands in the
/// first bar, a vocal in the second, cymbals in the third, and they can be as
/// loud or as quiet as the mix actually is in any combination.
///
/// Every step here runs on the audio thread:
///
/// * Coefficients are `Biquad` values stored in each section, so a filter is
///   five Floats and four history slots and nothing is allocated per call.
/// * The band levels are written straight into a fixed three-slot store, under
///   a *try*lock, so the meter can publish them from the main thread without
///   the audio thread ever waiting for it. A dropped publish costs one
///   callback's worth of a value that is about to be overwritten anyway.
///
/// The value that comes out is normalized against fixed dBFS limits rather
/// than against whatever has been loudest so far, so a quiet passage reads as
/// quiet — a self-scaling meter would show a floor of full-height bars for
/// silence, which is the opposite of honest.
final class AudioBandAnalyzer {
    /// How many bars the visualiser draws, and how many levels this measures.
    static let bandCount = 3

    /// Where the low bar ends and the mid bar begins, in Hz. Below the range
    /// of almost every small speaker and above the fundamental of a bass line:
    /// what a listener hears as "the bottom" is kick, bass and the low end of
    /// a piano, and it all lives under this.
    static let lowMidCrossover: Double = 250

    /// Where the mid bar ends and the high bar begins. Above the fundamental
    /// range of the human voice and most instruments, so the third bar is
    /// cymbals, sibilance, strings' air — the part of a mix that is present or
    /// absent rather than melodic.
    static let midHighCrossover: Double = 3_500

    /// The two ends of the scale a band's RMS is read against, in dBFS. The
    /// floor sits just under what a quiet-but-audible band measures, and the
    /// ceiling at a healthy level for a band with real content in it, so a
    /// normal track uses most of the bar's travel without ever being pinned.
    private static let floorDB: Float = -52
    private static let ceilingDB: Float = -6

    /// How much of a band's level survives one release step. The meter steps
    /// once per render callback — a few milliseconds — so this is the decay
    /// of a bar falling back after a transient: 0.72 per step reaches the
    /// floor in roughly a fifth of a second, which reads as a note ending
    /// rather than as a bar collapsing.
    private static let release: Float = 0.72

    /// One biquad with its own Direct Form I history.
    ///
    /// A struct of values rather than a `BiquadCascade`, because the bands are
    /// three short chains of one or two sections over a *mono* mixdown: the
    /// cascade's per-channel history and spin lock are for the mixer's audio
    /// path, and all this needs is a filter that keeps its own last four
    /// samples.
    private struct Section {
        private var coefficients: Biquad = .unity
        private var x1: Float = 0
        private var x2: Float = 0
        private var y1: Float = 0
        private var y2: Float = 0

        mutating func retune(_ new: Biquad) {
            // History is deliberately kept: a sample-rate change moves the
            // crossover by a few Hz of phase, which is inaudible on a meter,
            // whereas clearing the state mid-stream would put a step into the
            // filters and a click into the bars.
            guard new.b0 != coefficients.b0 || new.a1 != coefficients.a1 || new.a2 != coefficients.a2 else {
                return
            }
            coefficients = new
        }

        mutating func process(_ x: Float) -> Float {
            let c = coefficients
            let y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            return y
        }

        mutating func reset() {
            x1 = 0
            x2 = 0
            y1 = 0
            y2 = 0
        }
    }

    /// The low band: everything under the first crossover.
    private var lowBand = Section()
    /// The mid band: the second crossover's low-pass…
    private var midCeiling = Section()
    /// …followed by the first crossover's high-pass, which is what leaves the
    /// middle. Two sections in series is the band-pass the cookbook does not
    /// provide directly, and it keeps the three bands complementary: low and
    /// mid share the same edge instead of each approximating it.
    private var midFloor = Section()
    /// The high band: everything above the second crossover.
    private var highBand = Section()

    private var sampleRate: Double = 48_000

    /// The levels as the bars see them, and the envelope they are read
    /// through. `envelope` is the audio thread's working copy: a transient
    /// takes a bar to its new height in the callback it arrives in, and the
    /// release above brings it back down.
    private var envelope: [Float] = [0, 0, 0]
    private var published: [Float] = [0, 0, 0]
    private var lock = os_unfair_lock_s()
    private var isPrepared = false

    // MARK: - Control thread

    /// Points the crossovers at the rate the tap actually runs at. Called
    /// before the render callback starts; a later device change calls it again
    /// and the sections keep their history (see `Section.retune`).
    func prepare(sampleRate: Double) {
        guard sampleRate > 0 else { return }
        self.sampleRate = sampleRate
        lowBand.retune(.lowPass(frequency: Self.lowMidCrossover, q: 0.707, sampleRate: sampleRate))
        midCeiling.retune(.lowPass(frequency: Self.midHighCrossover, q: 0.707, sampleRate: sampleRate))
        midFloor.retune(.highPass(frequency: Self.lowMidCrossover, q: 0.707, sampleRate: sampleRate))
        highBand.retune(.highPass(frequency: Self.midHighCrossover, q: 0.707, sampleRate: sampleRate))
        isPrepared = true
    }

    /// Drops the filters' history and the levels, so a meter that starts again
    /// does not open on the tail of the last thing it heard.
    func reset() {
        lowBand.reset()
        midCeiling.reset()
        midFloor.reset()
        highBand.reset()
        envelope = [0, 0, 0]
        os_unfair_lock_lock(&lock)
        published = [0, 0, 0]
        os_unfair_lock_unlock(&lock)
        isPrepared = false
    }

    /// The most recent band energies, 0...1, in low/mid/high order. Read from
    /// the main thread — the render callback only ever *tries* this lock, so
    /// taking it here cannot stall audio.
    var bands: [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return published
    }

    // MARK: - Audio thread

    /// Measures `count` mono frames — one callback's worth of the mixdown.
    /// Audio thread only: no allocation, no failure path, and a guard that
    /// leaves the levels untouched rather than zeroing them if it is somehow
    /// called before `prepare`.
    func analyze(_ samples: UnsafePointer<Float>, count: Int) {
        guard isPrepared, count > 0 else { return }

        var lowSum: Float = 0
        var midSum: Float = 0
        var highSum: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            // All three bars are cut from the same sample, through the two
            // crossovers from either side: what leaves one bar is what the
            // next one starts from, so the ranges tile the spectrum.
            let low = lowBand.process(sample)
            let mid = midFloor.process(midCeiling.process(sample))
            let high = highBand.process(sample)
            lowSum += low * low
            midSum += mid * mid
            highSum += high * high
        }

        let scale = 1 / Float(count)
        step(index: 0, rms: (lowSum * scale).squareRoot())
        step(index: 1, rms: (midSum * scale).squareRoot())
        step(index: 2, rms: (highSum * scale).squareRoot())
        publish()
    }

    /// One band's envelope for this callback: straight to the new level if it
    /// rose, a fraction of the way down if it fell.
    private func step(index: Int, rms: Float) {
        guard envelope.indices.contains(index) else { return }
        let measured = Self.normalized(dBFS: rms)
        envelope[index] = max(measured, envelope[index] * Self.release)
    }

    /// Hands the envelope to `bands`, or skips this callback if the main
    /// thread is reading. Never blocks: a visualiser is not worth a stalled
    /// audio thread, and the next callback is a few milliseconds away.
    private func publish() {
        guard os_unfair_lock_trylock(&lock) else { return }
        published[0] = envelope[0]
        published[1] = envelope[1]
        published[2] = envelope[2]
        os_unfair_lock_unlock(&lock)
    }

    /// A band's RMS as a fraction of the bar's travel.
    private static func normalized(dBFS rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10f(rms)
        // Digital silence and, defensively, anything the log could not resolve.
        guard db.isFinite else { return 0 }
        let fraction = (db - floorDB) / (ceilingDB - floorDB)
        return min(max(fraction, 0), 1)
    }
}
