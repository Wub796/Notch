import SwiftUI

/// The bars beside the notch, each showing a measured frequency range: the
/// bottom of the mix at the left, the top at the right. Each height follows
/// that band's current magnitude from the real-time audio meter; without a
/// live measurement the bars stay idle rather than inventing frequency-specific
/// movement from the volume setting.
///
/// The count is the user's (`NotchSettings.audioMeterBarCount`), so the bars
/// share one meter box rather than each being given the tuned three-bar
/// spacing: the closed notch's trailing wing was measured around 19pt of
/// meter, and letting the meter grow with the setting would widen the whole
/// closed pill — and with it the clearance between the cover and the camera
/// housing. Four and five bars therefore thin and tighten, spending at most a
/// couple of points more of that clearance instead of asking the pill to move.
struct MusicVisualizerView: View {
    let accent: Color

    /// The tap runs ahead of the output controls; false when muted or silent.
    let outputIsAudible: Bool

    /// Measured band energies, 0...1, lowest first, when the real-time meter
    /// is running.
    var bands: [Float]?

    /// How many bars to draw, from the user's setting. Defaulted for callers
    /// with no settings in hand, which get the tuned three-bar meter.
    var barCount: Int = AudioBandAnalyzer.defaultBandCount

    /// The height every bar is drawn inside, and the tallest a bar can be.
    private static let maxHeight: CGFloat = 15

    /// The count the view actually draws, clamped to what the meter measures.
    private var resolvedBarCount: Int {
        AudioBandAnalyzer.clampedBandCount(barCount)
    }

    /// Bar width for the count: 4pt at three bars, then 3.5 and 3, so five
    /// bars stay inside the wing's box — five 3pt bars and their gaps measure
    /// 21pt, two points more than the three-bar meter and far less than the
    /// wing's own clearance.
    private var barWidth: CGFloat {
        switch resolvedBarCount {
        case 4: 3.5
        case 5: 3
        default: 4
        }
    }

    /// The gap between bars, widened or narrowed so the bars share the box
    /// instead of adding to it: 3.5pt at three, 2pt at four, 1.5pt at five.
    private var barSpacing: CGFloat {
        switch resolvedBarCount {
        case 4: 2
        case 5: 1.5
        default: 3.5
        }
    }

    /// True only when the meter has published exactly the levels this view is
    /// drawing. A count change goes through the tap, so for a frame or two the
    /// bands are still the previous split's: showing them under the new count
    /// would label them as ranges nothing measured.
    private var isMetered: Bool {
        bands?.count == resolvedBarCount
    }

    var body: some View {
        Group {
            if isMetered {
                // The meter publishes at 30Hz; animating between its values is
                // all the motion needed, so no timeline is driven here.
                bars { index in meteredHeight(index) }
                    .animation(.easeOut(duration: 0.07), value: bands ?? [])
            } else {
                // A volume setting is not audio magnitude and contains no
                // frequency information. Stay still until real bands arrive.
                bars { _ in barWidth }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Output frequency bands")
        .accessibilityValue(accessibilityValue)
    }

    /// Accessible readings of each measured band, or the reason the bars are
    /// idle while a live measurement is unavailable.
    private var accessibilityValue: String {
        guard isMetered, let bands else {
            return "No live measurement"
        }
        return zip(bandNames, bands)
            .map { "\($0) \(Int(($1 * 100).rounded())) percent" }
            .joined(separator: ", ")
    }

    /// What each bar is measuring. Three names are the tuned ranges; four and
    /// five subdivide those, so the names follow the split `AudioBandAnalyzer`
    /// makes — the middle at four bars, the top at five.
    private var bandNames: [String] {
        switch resolvedBarCount {
        case 4: ["low", "low-mid", "high-mid", "high"]
        case 5: ["low", "low-mid", "mid", "high-mid", "high"]
        default: ["low", "mid", "high"]
        }
    }

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0 ..< resolvedBarCount, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: height(index))
            }
        }
        .frame(height: Self.maxHeight)
    }

    /// Measured: this bar's band, mapped directly to its own height with no
    /// per-band boost that would disguise the relative magnitudes.
    private func meteredHeight(_ index: Int) -> CGFloat {
        guard let bands, bands.indices.contains(index) else { return barWidth }
        // The tap is upstream of volume and mute, so keep the drawing
        // consistent with what reaches the speakers without scaling the
        // measured magnitudes by volume.
        guard outputIsAudible else { return barWidth }

        let magnitude = CGFloat(min(max(bands[index], 0), 1))
        guard magnitude > 0.01 else { return barWidth }
        let range = Self.maxHeight - barWidth
        return barWidth + range * magnitude
    }
}
