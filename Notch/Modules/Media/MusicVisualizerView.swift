import SwiftUI

/// Three bars beside the notch, each showing a measured frequency range:
/// low, mid and high. Each height follows that band's current magnitude from
/// the real-time audio meter; without a live measurement the bars stay idle
/// rather than inventing frequency-specific movement from the volume setting.
struct MusicVisualizerView: View {
    let accent: Color

    /// The tap runs ahead of the output controls; false when muted or silent.
    let outputIsAudible: Bool

    /// Measured band energies, 0...1, in low/mid/high order, when the real
    /// meter is running.
    var bands: [Float]?

    private static let barWidth: CGFloat = 4
    private static let maxHeight: CGFloat = 15
    private static let barCount = AudioBandAnalyzer.bandCount

    private var isMetered: Bool {
        (bands?.count ?? 0) >= 3
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
                bars { _ in Self.barWidth }
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
        let names = ["low", "mid", "high"]
        return zip(names, bands)
            .map { "\($0) \(Int(($1 * 100).rounded())) percent" }
            .joined(separator: ", ")
    }

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: 3.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: Self.barWidth, height: height(index))
            }
        }
        .frame(height: Self.maxHeight)
    }

    /// Measured: this bar's band, mapped directly to its own height with no
    /// per-band boost that would disguise the relative magnitudes.
    private func meteredHeight(_ index: Int) -> CGFloat {
        guard let bands, bands.indices.contains(index) else { return Self.barWidth }
        // The tap is upstream of volume and mute, so keep the drawing
        // consistent with what reaches the speakers without scaling the
        // measured magnitudes by volume.
        guard outputIsAudible else { return Self.barWidth }

        let magnitude = CGFloat(min(max(bands[index], 0), 1))
        guard magnitude > 0.01 else { return Self.barWidth }
        let range = Self.maxHeight - Self.barWidth
        return Self.barWidth + range * magnitude
    }
}
