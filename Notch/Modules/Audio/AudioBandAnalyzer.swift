import Foundation

/// The energy in each of the ranges the closed notch draws a bar for.
///
/// The visualiser asks one question per bar — how loud is the bottom right
/// now, and the range above it, and the next — and this answers it from the
/// samples themselves rather than from anything the system reports *about*
/// them. That distinction is the whole point: the volume is one number and
/// cannot tell several bars apart, so a meter built on it draws the same shape
/// once per bar. Filtering the real mix into ranges and measuring each one
/// gives genuinely different numbers, which is what makes the bars move like
/// the music instead of like the volume slider.
///
/// **The count is the user's.** Three, four or five bars are offered
/// (`NotchSettings.audioMeterBarCount`), and the split follows the choice. The
/// two tuned anchors stay edges at every count: everything below
/// `lowMidCrossover` is the first bar, so a kick lives in the bottom bar, and
/// everything above `midHighCrossover` is the last, so cymbals and sibilance
/// live at the top. Counting up from three, each extra bar subdivides a range
/// that carries real content — the middle of the spectrum at four, the top of
/// the mix at five — rather than rescaling the whole meter, so the ends keep
/// meaning what they always meant.
///
/// The split is `bandCount - 1` crossovers, not `bandCount` unrelated filters:
/// each edge bounds the two bands either side of it — the lower band through
/// its low-pass, the upper through its high-pass — so the ranges tile the
/// spectrum instead of overlapping or leaving a gap, and they can be as loud
/// or as quiet as the mix actually is in any combination.
///
/// Every step here runs on the audio thread:
///
/// * Coefficients are `Biquad` values stored in each section, so a filter is
///   five Floats and four history slots and nothing is allocated per call.
///   Each band is one high-pass at its lower edge and one low-pass at its
///   upper; the bottom band's lower edge and the top band's upper edge are
///   *unity* sections, which is how the open ends take the same two steps as
///   every interior band with no branch per band in the loop.
/// * The band levels are written straight into a fixed five-slot store, under
///   a *try*lock, so the meter can publish them from the main thread without
///   the audio thread ever waiting for it. A dropped publish costs one
///   callback's worth of a value that is about to be overwritten anyway.
///
/// The value that comes out is normalized against fixed dBFS limits rather
/// than against whatever has been loudest so far, so a quiet passage reads as
/// quiet — a self-scaling meter would show a floor of full-height bars for
/// silence, which is the opposite of honest.
final class AudioBandAnalyzer {
    /// The count the meter is tuned around, and the one the settings fall
    /// back to when nothing has been chosen.
    static let defaultBandCount = 3

    /// The range the settings offer. One band is not a spectrum, and past five
    /// the bars stop fitting the closed notch's wing; these are also the clamp
    /// a value read back from the defaults file goes through, so what the bars
    /// draw can never disagree with what the analyzer measures.
    static let minimumBandCount = 3
    static let maximumBandCount = 5

    static func clampedBandCount(_ count: Int) -> Int {
        min(max(count, minimumBandCount), maximumBandCount)
    }

    /// Where the bottom bar ends and the next one begins, in Hz. Below the
    /// range of almost every small speaker and above the fundamental of a bass
    /// line: what a listener hears as "the bottom" is kick, bass and the low
    /// end of a piano, and it all lives under this.
    static let lowMidCrossover: Double = 250

    /// Where the top bar begins. Above the fundamental range of the human
    /// voice and most instruments, so the last bar is cymbals, sibilance,
    /// strings' air — the part of a mix that is present or absent rather than
    /// melodic.
    static let midHighCrossover: Double = 3_500

    /// The edge a four-bar split adds between the two anchors: their geometric
    /// mean, which is the middle of the *audible* span they bound rather than
    /// the arithmetic middle of the two numbers. The bar it creates is the
    /// body of the mix — guitars, keys, the lower half of a voice.
    private static var middleCrossover: Double {
        (lowMidCrossover * midHighCrossover).squareRoot()
    }

    /// The edge a five-bar split adds above the top anchor: the geometric mean
    /// of that anchor and the top of the audible range, so the last bar is the
    /// very top of the mix — hiss, cymbal wash, air — and the bar before it is
    /// presence.
    private static var airCrossover: Double {
        (midHighCrossover * 20_000).squareRoot()
    }

    /// The crossovers for a count, low to high. Three bars are the two tuned
    /// anchors unchanged; four and five add one subdivision each, in the order
    /// the content is: the middle first, then the top.
    static func crossovers(for bandCount: Int) -> [Double] {
        switch clampedBandCount(bandCount) {
        case 4:
            return [lowMidCrossover, middleCrossover, midHighCrossover]
        case 5:
            return [lowMidCrossover, middleCrossover, midHighCrossover, airCrossover]
        default:
            return [lowMidCrossover, midHighCrossover]
        }
    }

    /// How much of a band's level survives one release step. The meter steps
    /// once per render callback — a few milliseconds — so this is the decay
    /// of a bar falling back after a transient: 0.72 per step reaches the
    /// floor in roughly a fifth of a second, which reads as a note ending
    /// rather than as a bar collapsing.
    private static let release: Float = 0.72

    /// The two ends of the scale a band's RMS is read against, in dBFS. The
    /// floor sits just under what a quiet-but-audible band measures, and the
    /// ceiling at a healthy level for a band with real content in it, so a
    /// normal track uses most of the bar's travel without ever being pinned.
    private static let floorDB: Float = -52
    private static let ceilingDB: Float = -6

    /// One biquad with its own Direct Form I history.
    ///
    /// A struct of values rather than a `BiquadCascade`, because the bands are
    /// a few short chains of one or two sections over a *mono* mixdown: the
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

    /// Two sections per band — lower edge, then upper edge — sized once for
    /// the widest split the settings offer. Fixed capacity is the point: the
    /// render callback must never grow its own storage, and a count change
    /// retunes the sections that are already here rather than building a new
    /// chain for the audio thread to find.
    private var sections: [Section] = Array(
        repeating: Section(),
        count: AudioBandAnalyzer.maximumBandCount * 2
    )

    /// How many bands are being measured. Written on the control thread
    /// (`setBandCount`) and read by the render callback: one integer, and
    /// every value it can see names a split the sections have been retuned
    /// for, so the worst a change landing mid-callback can do is measure one
    /// callback at the previous split.
    private(set) var bandCount = AudioBandAnalyzer.defaultBandCount

    /// Bumped when the split changes, so the render callback can drop the
    /// envelope the old split was measured into instead of decaying it through
    /// the new bars — a bar that opens at the height of a range it is no
    /// longer measuring is a reading of nothing.
    private var layoutVersion: UInt64 = 0
    private var seenLayoutVersion: UInt64 = 0

    private var sampleRate: Double = 48_000

    /// Per-band accumulators, one callback's worth, and the envelope the bars
    /// are read through. Both are audio-thread working state, both fixed
    /// capacity: a transient takes a bar to its new height in the callback it
    /// arrives in, and the release above brings it back down.
    private var sums: [Float] = [Float](repeating: 0, count: AudioBandAnalyzer.maximumBandCount)
    private var envelope: [Float] = [Float](repeating: 0, count: AudioBandAnalyzer.maximumBandCount)

    /// The levels as the main thread sees them, and how many of the five slots
    /// are live at the current count. Guarded by `lock`: the render callback
    /// *tries* it once per callback, and the main thread reads through it.
    private var published: [Float] = [Float](repeating: 0, count: AudioBandAnalyzer.maximumBandCount)
    private var publishedCount = AudioBandAnalyzer.defaultBandCount
    private var lock = os_unfair_lock_s()
    private var isPrepared = false

    // MARK: - Control thread

    /// Points the crossovers at the rate the tap actually runs at. Called
    /// before the render callback starts; a later device change calls it again
    /// and the sections keep their history (see `Section.retune`).
    func prepare(sampleRate: Double) {
        guard sampleRate > 0 else { return }
        self.sampleRate = sampleRate
        retune()
    }

    /// Changes how many bands are measured, without stopping the tap.
    ///
    /// Called on the control thread — the same place `prepare` and `reset`
    /// run — while the render callback may be running, exactly like a
    /// sample-rate change: the sections are retuned in place and the count the
    /// callback reads moves with them. One callback can therefore be measured
    /// half at the old split, which on a visualiser is invisible; the count
    /// and the retuned sections are both in place before the next one.
    func setBandCount(_ count: Int) {
        let clamped = Self.clampedBandCount(count)
        guard clamped != bandCount else { return }

        // The published levels change size with the split, so they are cleared
        // in the same critical section that moves the count: the main thread
        // reads a new count as zeroes rather than as the tail of the previous
        // split, whatever order it arrives in.
        os_unfair_lock_lock(&lock)
        for slot in published.indices { published[slot] = 0 }
        publishedCount = clamped
        os_unfair_lock_unlock(&lock)

        bandCount = clamped
        layoutVersion &+= 1
        if isPrepared { retune() }
    }

    /// Drops the filters' history and the levels, so a meter that starts again
    /// does not open on the tail of the last thing it heard.
    func reset() {
        for index in sections.indices { sections[index].reset() }
        for band in envelope.indices { envelope[band] = 0 }
        os_unfair_lock_lock(&lock)
        for slot in published.indices { published[slot] = 0 }
        publishedCount = bandCount
        os_unfair_lock_unlock(&lock)
        isPrepared = false
    }

    /// The most recent band energies, 0...1, lowest band first. Read from the
    /// main thread — the render callback only ever *tries* this lock, so taking
    /// it here cannot stall audio.
    ///
    /// The copy is deliberate. Handing out the stored array would leave the
    /// render callback writing into a buffer the caller still holds, and
    /// Swift's answer to that is a copy allocated on the audio thread.
    var bands: [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return Array(published[0 ..< publishedCount])
    }

    // MARK: - Audio thread

    /// Measures `count` mono frames — one callback's worth of the mixdown.
    /// Audio thread only: no allocation, no failure path, and a guard that
    /// leaves the levels untouched rather than zeroing them if it is somehow
    /// called before `prepare`.
    func analyze(_ samples: UnsafePointer<Float>, count: Int) {
        guard isPrepared, count > 0 else { return }

        // Read once per callback: the bar count can change while the tap runs,
        // and a change landing mid-callback applies to the next one. Both
        // configurations are valid for these samples either way.
        let bandCount = self.bandCount
        if layoutVersion != seenLayoutVersion {
            seenLayoutVersion = layoutVersion
            for band in envelope.indices { envelope[band] = 0 }
        }
        for band in 0 ..< bandCount { sums[band] = 0 }

        for index in 0 ..< count {
            let sample = samples[index]
            var band = 0
            while band < bandCount {
                // Both of this band's sections are cut from the same sample:
                // its high-pass at the crossover below it and its low-pass at
                // the one above, so the bands tile the spectrum.
                let filtered = sections[band * 2 + 1].process(sections[band * 2].process(sample))
                sums[band] += filtered * filtered
                band += 1
            }
        }

        let scale = 1 / Float(count)
        for band in 0 ..< bandCount {
            step(index: band, rms: (sums[band] * scale).squareRoot())
        }
        publish(count: bandCount)
    }

    /// One band's envelope for this callback: straight to the new level if it
    /// rose, a fraction of the way down if it fell.
    private func step(index: Int, rms: Float) {
        guard envelope.indices.contains(index) else { return }
        let measured = Self.normalized(dBFS: rms)
        envelope[index] = max(measured, envelope[index] * Self.release)
    }

    /// Hands the envelope to `published`, or skips this callback if the main
    /// thread is reading. Never blocks: a visualiser is not worth a stalled
    /// audio thread, and the next callback is a few milliseconds away.
    private func publish(count: Int) {
        guard os_unfair_lock_trylock(&lock) else { return }
        for band in 0 ..< count { published[band] = envelope[band] }
        publishedCount = count
        os_unfair_lock_unlock(&lock)
    }

    /// Builds every band's two sections from the crossovers for the current
    /// count and rate. An open end — the bottom band's lower edge, the top
    /// band's upper edge — is a unity section rather than a special case, so
    /// the loop above runs the same two steps for every band it measures.
    private func retune() {
        let edges = Self.crossovers(for: bandCount)
        // Clamped below Nyquist: the bilinear transform has no valid answer for
        // an edge at or above half the sample rate — the tangent flips sign —
        // and a device running unusually slowly must degrade the top split, not
        // turn the meter into noise. No practical output rate is anywhere near
        // this: the highest edge here is the 8.4kHz air crossover.
        let limit = sampleRate * 0.45
        for band in 0 ..< bandCount {
            let lower = band == 0
                ? Biquad.unity
                : Biquad.highPass(frequency: min(edges[band - 1], limit), q: 0.707, sampleRate: sampleRate)
            let upper = band == bandCount - 1
                ? Biquad.unity
                : Biquad.lowPass(frequency: min(edges[band], limit), q: 0.707, sampleRate: sampleRate)
            sections[band * 2].retune(lower)
            sections[band * 2 + 1].retune(upper)
        }
        isPrepared = true
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
