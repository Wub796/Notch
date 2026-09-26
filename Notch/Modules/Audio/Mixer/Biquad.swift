import Foundation

/// One second-order IIR section, in Direct Form I.
///
/// Coefficients come from the RBJ Audio-EQ-Cookbook formulas — the standard
/// published derivation for a peaking or shelving section, applied to a
/// bilinear-transform biquad. Kept as a plain struct of five Floats so a whole
/// filter chain can be built on the control thread and handed to the audio
/// thread as a value, with no allocation and no locking around individual
/// coefficients.
///
/// The mixer's chain (see `MixerStrip`) is: the app's own EQ curves, then any
/// AutoEQ correction matched to the output device, then loudness compensation,
/// then gain. All of that is this type, repeated.
struct Biquad {
    var b0: Float
    var b1: Float
    var b2: Float
    var a1: Float
    var a2: Float

    /// A unity section — the identity, used to pad a chain so its length does
    /// not change when a band is bypassed.
    static let unity = Biquad(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    /// One band of a graphic EQ: a peaking filter at `frequency` with `gain`
    /// in dB, `q` setting how wide the affected region is.
    static func peaking(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> Biquad {
        let a = pow(10, gainDB / 40)
        let w = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w)
        let alpha = sin(w) / (2 * max(q, 0.05))

        let b0 = 1 + alpha * a
        let b1 = -2 * cosW
        let b2 = 1 - alpha * a
        let a0 = 1 + alpha / a
        let a1 = -2 * cosW
        let a2 = 1 - alpha / a
        return normalized(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    /// A shelf: everything below `frequency` (low) or above it (high) is
    /// lifted or cut by `gainDB`, with `slope` controlling the transition.
    /// This is what a loudness compensation or a broad tone control needs,
    /// where a peaking band would leave the extremes alone.
    static func lowShelf(frequency: Double, gainDB: Double, slope: Double, sampleRate: Double) -> Biquad {
        shelf(frequency: frequency, gainDB: gainDB, slope: slope, sampleRate: sampleRate, high: false)
    }

    static func highShelf(frequency: Double, gainDB: Double, slope: Double, sampleRate: Double) -> Biquad {
        shelf(frequency: frequency, gainDB: gainDB, slope: slope, sampleRate: sampleRate, high: true)
    }

    private static func shelf(
        frequency: Double,
        gainDB: Double,
        slope: Double,
        sampleRate: Double,
        high: Bool
    ) -> Biquad {
        let a = pow(10, gainDB / 40)
        let w = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w)
        let sinW = sin(w)
        let alpha = sinW / 2 * sqrt((a + 1 / a) * (1 / max(slope, 0.05) - 1) + 2)
        let beta = 2 * a.sqrt() * alpha

        let b0: Double
        let b1: Double
        let b2: Double
        let a0: Double
        let a1: Double
        let a2: Double
        if high {
            b0 = a * ((a + 1) + (a - 1) * cosW + beta)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosW)
            b2 = a * ((a + 1) + (a - 1) * cosW - beta)
            a0 = (a + 1) - (a - 1) * cosW + beta
            a1 = 2 * ((a - 1) - (a + 1) * cosW)
            a2 = (a + 1) - (a - 1) * cosW - beta
        } else {
            b0 = a * ((a + 1) - (a - 1) * cosW + beta)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosW)
            b2 = a * ((a + 1) - (a - 1) * cosW - beta)
            a0 = (a + 1) + (a - 1) * cosW + beta
            a1 = -2 * ((a - 1) + (a + 1) * cosW)
            a2 = (a + 1) + (a - 1) * cosW - beta
        }
        return normalized(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    /// The mirror of `highPass`: everything above `frequency` is left alone
    /// and everything below it is rolled off. The spectrum meter uses it as
    /// the low end of a two-section band split (`AudioBandAnalyzer`); the
    /// mixer's curves do not need it, because every band a user can shape is
    /// a shelf or a peaking filter.
    static func lowPass(frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w)
        let alpha = sin(w) / (2 * max(q, 0.05))
        let b0 = (1 - cosW) / 2
        let b1 = 1 - cosW
        let b2 = (1 - cosW) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosW
        let a2 = 1 - alpha
        return normalized(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    /// A first-order-style roll-off, expressed as the biquad equivalent.
    static func highPass(frequency: Double, q: Double, sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w)
        let alpha = sin(w) / (2 * max(q, 0.05))
        let b0 = (1 + cosW) / 2
        let b1 = -(1 + cosW)
        let b2 = (1 + cosW) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosW
        let a2 = 1 - alpha
        return normalized(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    private static func normalized(
        b0: Double, b1: Double, b2: Double,
        a0: Double, a1: Double, a2: Double
    ) -> Biquad {
        guard a0 != 0, a0.isFinite else { return .unity }
        return Biquad(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(a1 / a0),
            a2: Float(a2 / a0)
        )
    }
}

private extension Double {
    /// `pow(x, 0.5)` without pulling in a second call site for the shelf's
    /// square-root term.
    func sqrt() -> Double { Foundation.sqrt(self) }
}

/// A chain of `Biquad` sections applied to every channel, keeping each
/// section's own history.
///
/// The audio thread runs `process` while the control thread rebuilds the chain,
/// so the sections are guarded by a spin lock rather than a mutex: the audio
/// thread may spin for the few nanoseconds a swap takes but must never be
/// suspended by a lock its own thread could be holding. Same reasoning as the
/// rest of the realtime path in `MixerStrip` — no allocation, no Objective-C,
/// no waiting on another thread's I/O.
final class BiquadCascade {
    private var sections: [Biquad] = []
    private var history: [Float] = []
    private var channelCount = 0
    private var lock = os_unfair_lock_s()

    /// Rebuilds the chain. Called from the control thread; the audio thread
    /// sees either the old chain or the new one, never a half-updated mix.
    func prepare(sections: [Biquad], channelCount: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        self.channelCount = max(channelCount, 0)
        self.sections = sections
        // Four state slots per section per channel: x[n-1], x[n-2], y[n-1],
        // y[n-2]. Reallocated only when the shape actually changes, so a gain
        // tweak does not clear the filters' history and click.
        let needed = sections.count * self.channelCount * 4
        if history.count != needed {
            history = [Float](repeating: 0, count: needed)
        }
    }

    /// Drops the filter history — for when the chain is torn down and rebuilt
    /// against different audio, where carrying the old tail would be noise.
    func reset() {
        os_unfair_lock_lock(&lock)
        for index in history.indices { history[index] = 0 }
        os_unfair_lock_unlock(&lock)
    }

    var isEmpty: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return sections.isEmpty
    }

    /// Applies the chain in place to `frameCount` frames of a single channel,
    /// starting at `offset`. Audio-thread only.
    ///
    /// Direct Form I, so each section reads its two input and two output
    /// samples straight out of the history array — one contiguous buffer, no
    /// per-section allocations, and stability preserved for the coefficients
    /// the cookbook produces.
    func process(
        channel: Int,
        samples: UnsafeMutablePointer<Float>,
        frameCount: Int,
        stride: Int
    ) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard !sections.isEmpty, channel < channelCount else { return }

        for (sectionIndex, section) in sections.enumerated() {
            let base = (sectionIndex * channelCount + channel) * 4
            var x1 = history[base]
            var x2 = history[base + 1]
            var y1 = history[base + 2]
            var y2 = history[base + 3]

            var index = 0
            for _ in 0..<frameCount {
                let x = samples[index]
                let y = section.b0 * x
                    + section.b1 * x1
                    + section.b2 * x2
                    - section.a1 * y1
                    - section.a2 * y2
                x2 = x1
                x1 = x
                y2 = y1
                y1 = y
                samples[index] = y
                index += stride
            }

            history[base] = x1
            history[base + 1] = x2
            history[base + 2] = y1
            history[base + 3] = y2
        }
    }
}
