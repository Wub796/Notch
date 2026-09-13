import SwiftUI

/// The volume / brightness bar, ported from boring.notch's
/// `SystemEventIndicatorModifier.DraggableProgressBar` and Atoll's variant.
///
/// Two capsules: a `.tertiary` track and a gradient fill running from the
/// leading edge, with the gradient itself oriented trailing-to-leading so the
/// bright end sits at the current value. It thickens while dragged, and it is
/// draggable — dragging sets the system value through `onChange`, which is why
/// the reference calls it a *draggable* progress bar rather than a readout.
struct DraggableProgressBar: View {
    @Binding var value: CGFloat

    /// Tint for the filled portion; the reference uses the album accent or
    /// white depending on a preference.
    var tint: Color = .white

    /// Whether this is the inline (in-notch) HUD, which draws slightly
    /// thinner than the standalone one.
    var inline: Bool = true

    var onChange: ((CGFloat) -> Void)?

    @State private var isDragging = false

    private var height: CGFloat {
        inline ? (isDragging ? 9 : 6) : (isDragging ? 10 : 7)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tertiary)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.2)],
                            startPoint: .trailing,
                            endPoint: .leading
                        )
                    )
                    .frame(width: max(0, min(geometry.size.width * value, geometry.size.width)))
                    .shadow(color: tint.opacity(0.55), radius: 8, x: 3)
                    // A zero-width capsule still paints a dot; hiding it keeps
                    // muted and zero-brightness from looking broken.
                    .opacity(value.isZero ? 0 : 1)
                    // Remote value changes (media keys, per-app mixers) glide
                    // to the new level; the width also animates its thickness
                    // settle. While the finger is down the animation is nil so
                    // the fill sticks to 1:1 tracking — a tween here would
                    // chase the cursor.
                    .animation(isDragging ? nil : NotchAnimations.content, value: value)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        // 1:1 tracking: the fill follows the pointer instantly.
                        isDragging = true
                        update(to: gesture.location.x, in: geometry)
                    }
                    .onEnded { _ in
                        // Settle the thickness change with the house spring
                        // (profile-aware; collapses to a short fade under
                        // Reduce Motion). The value itself is already where the
                        // finger left it.
                        isDragging = false
                    }
            )
        }
        .frame(height: height)
        // The thickness jump (6 → 9) springs with the house curve; under the
        // finger the value animation above is disabled, so this owns the settle.
        .animation(NotchAnimations.content, value: isDragging)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let step: CGFloat = 1.0 / 16.0
            let target = direction == .increment ? value + step : value - step
            value = max(0, min(1, target))
            onChange?(value)
        }
    }

    private func update(to x: CGFloat, in geometry: GeometryProxy) {
        guard geometry.size.width > 0 else { return }
        value = max(0, min(x / geometry.size.width, 1))
        onChange?(value)
    }
}

/// The dropped HUD bar: glyph, a full-width level bar, and the reading.
///
/// This is the layout the notch actually uses. `InlineHUD` below is the
/// references' wing arrangement, kept because it is the right shape when the
/// bar has to sit beside the camera housing rather than under it.
/// The volume / brightness bar that drops beneath the notch.
struct DroppedHUDBar: View {
    let kind: InlineHUD.Kind
    @Binding var value: CGFloat
    var showsPercentage: Bool = true
    var onChange: ((CGFloat) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            glyph
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .symbolVariant(.fill)
                .frame(width: 18)

            DraggableProgressBar(
                value: $value,
                tint: kind.tint,
                inline: false,
                onChange: onChange
            )

            if showsPercentage {
                Text(reading)
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .frame(width: 38, alignment: .trailing)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, NotchTheme.Space.m)
        .padding(.vertical, NotchTheme.Space.xs)
        .notchTile(radius: NotchTheme.Radius.tile)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityValue(reading)
    }

    private var reading: String {
        if case let .volume(muted) = kind, muted || value.isZero { return "Muted" }
        return "\(Int(value * 100))%"
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case let .volume(muted):
            Image(systemName: InlineHUD.speakerSymbol(value))
                .symbolVariant(muted || value.isZero ? .slash : .none)
                .contentTransition(.interpolate)
        case .brightness:
            Image(systemName: value > 0.5 ? "sun.max.fill" : "sun.min.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.2))
                .contentTransition(.interpolate)
        }
    }
}

/// The references' wing HUD: a labelled glyph on the left wing, the reserved
/// camera dead zone, and the bar with its percentage on the right.
///
/// Layout is boring.notch's `InlineHUD`: each wing is a fixed 100pt (less 12
/// when not hovered, so the content eases outward as the pill grows), and the
/// dead zone is the hardware notch less 20. Fixed wing widths are what keep
/// the glyph and the bar from sliding around as the value's digits change.
struct InlineHUD: View {
    let kind: Kind
    @Binding var value: CGFloat
    let isHovering: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var showsPercentage: Bool = true
    var onChange: ((CGFloat) -> Void)?

    enum Kind {
        case volume(muted: Bool)
        case brightness

        var title: String {
            switch self {
            case .volume: "Volume"
            case .brightness: "Brightness"
            }
        }

        var tint: Color {
            switch self {
            case .volume: .white
            case .brightness: .white
            }
        }
    }

    private var wingWidth: CGFloat {
        100 - (isHovering ? 0 : 12)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                glyph
                    .foregroundStyle(.white)
                    .symbolVariant(.fill)

                Text(kind.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
            }
            .frame(width: wingWidth, height: notchHeight - (isHovering ? 0 : 12), alignment: .leading)

            // Reserved dead zone for the camera housing.
            Color.clear
                .frame(width: max(0, notchWidth - 20))

            HStack(spacing: 8) {
                DraggableProgressBar(value: $value, tint: kind.tint, onChange: onChange)

                if case let .volume(muted) = kind, muted || value.isZero {
                    Text("muted")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                } else if showsPercentage {
                    Text("\(Int(value * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            .padding(.trailing, 4)
            .frame(width: wingWidth, height: notchHeight - (isHovering ? 0 : 12), alignment: .center)
        }
        .frame(height: notchHeight + (isHovering ? 8 : 0), alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.title)
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case let .volume(muted):
            Image(systemName: Self.speakerSymbol(value))
                .contentTransition(.interpolate)
                .symbolVariant(muted || value.isZero ? .slash : .none)
                .frame(width: 20, height: 15, alignment: .leading)
        case .brightness:
            Image(systemName: value > 0.6 ? "sun.max" : "sun.min")
                .contentTransition(.interpolate)
                .frame(width: 20, height: 15, alignment: .center)
        }
    }

    /// The reference's speaker ramp.
    static func speakerSymbol(_ value: CGFloat) -> String {
        switch value {
        case 0: "speaker"
        case 0 ... 0.3: "speaker.wave.1"
        case 0.3 ... 0.8: "speaker.wave.2"
        case 0.8 ... 1: "speaker.wave.3"
        default: "speaker.wave.2"
        }
    }
}
