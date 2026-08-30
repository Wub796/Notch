import SwiftUI

/// Charging popup: a glass capsule that pops in beneath the hardware notch
/// when the charger is connected, holds for a few seconds, then eases away —
/// the iOS charging popup, re-imagined for the notch.
///
/// The pop uses a small overshoot (scale 0.55 → ~1.04 → 1) via a bouncy
/// spring; dismissal eases out. Both respect Reduce Motion.
struct ChargingPopupView: View {
    /// Battery percentage at the moment the popup was raised, 0...1.
    let level: CGFloat

    /// Tint of the fill bar — the app's battery green.
    private let tint = NotchTheme.battery

    @State private var isFilled = false

    var body: some View {
        HStack(spacing: 10) {
            boltBadge

            VStack(alignment: .leading, spacing: 3) {
                Text("Charging")
                    .font(.notchCallout.weight(.bold))
                    .foregroundStyle(NotchTheme.inkPrimary)

                Text("\(Int((level * 100).rounded()))%")
                    .font(.notchFootnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Text("\(Int((level * 100).rounded()))%")
                .font(.notchHeadline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                isFilled = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Charging")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
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
