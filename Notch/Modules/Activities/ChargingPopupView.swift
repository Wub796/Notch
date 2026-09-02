import SwiftUI

/// Charging popup: a glass capsule that pops in beneath the hardware notch
/// when the charger is connected, holds for a few seconds, then eases away —
/// the iOS charging popup, re-imagined for the notch.
///
/// The pop itself is the caller's transition; this is only what it contains.
struct ChargingPopupView: View {
    /// Battery percentage at the moment the popup was raised, 0...1.
    let level: CGFloat

    private let tint = NotchTheme.battery

    private var percent: Int {
        Int((min(max(level, 0), 1) * 100).rounded())
    }

    var body: some View {
        HStack(spacing: 10) {
            boltBadge

            VStack(alignment: .leading, spacing: 1) {
                Text("Charging")
                    .font(.notchCallout.weight(.bold))
                    .foregroundStyle(NotchTheme.inkPrimary)

                // The reading was here as well as on the right; one number,
                // once, and a word about what is actually happening.
                Text(percent >= 100 ? "Fully charged" : "Power adapter connected")
                    .font(.notchFootnote)
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: NotchTheme.Space.s)

            Text("\(percent)%")
                .font(.notchHeadline.monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(NotchAnimations.content, value: percent)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                .fill(
                    NotchTheme.prefersReducedTransparency
                        // Reduce Transparency asks for solid, not frosted: the
                        // popup reads as a clean flat surface against whatever
                        // is behind it instead of a half-blur the user has
                        // explicitly reduced.
                        ? AnyShapeStyle(Color.black.opacity(0.9))
                        : AnyShapeStyle(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchTheme.Radius.tile, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Charging")
        .accessibilityValue("\(percent) percent")
    }

    /// Green circle with a white bolt — the iOS charging glyph.
    private var boltBadge: some View {
        ZStack {
            Circle()
                .fill(tint)
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}
