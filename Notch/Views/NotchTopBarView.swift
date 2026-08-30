import AppKit
import SwiftUI

/// The home top bar: the module rail on the left, system status icons on the
/// right, and an exact dead zone between them for the camera housing. The
/// dashboard's music/weather/calendar sections still drill into their own
/// detail screens; the rail is how the modules that have no dashboard card
/// — shelf, clipboard, notes, tools, stats — are reached at all.
struct NotchTopBarView: View {
    let state: NotchState

    /// Every module the rail exposes, in order.
    private static let modules: [(tab: NotchTab, symbol: String, name: String)] = [
        (.shelf, "archivebox", "Shelf"),
        (.clipboard, "doc.on.clipboard", "Clipboard"),
        (.notes, "note.text", "Notes"),
        (.audio, "hifispeaker.2.fill", "Devices"),
        (.telemetry, "gauge.with.dots.needle.50percent", "System Stats"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            leadingControls
                .frame(width: flankWidth, alignment: .leading)
                .clipped()

            // Reserved dead zone, masked to the notch silhouette so the
            // hardware notch appears to continue through the open slab.
            Rectangle()
                .fill(.black)
                .frame(width: deadZoneWidth)
                .mask { NotchShape() }

            trailingControls
                .frame(width: flankWidth, alignment: .trailing)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The width each side of the notch is allowed — same rule as the detail
    /// headers: the two flanks split everything that is not the dead zone, so
    /// the rail and status icons can never slide under the hardware notch.
    private var flankWidth: CGFloat {
        max((state.moduleContentSize.width - deadZoneWidth) / 2, 0)
    }

    /// The dead zone's drawn width: the notch size that is guaranteed to
    /// cover the real hardware cutout, measurement error included.
    private var deadZoneWidth: CGFloat {
        state.safeNotchSize.width
    }

    private var leadingControls: some View {
        // The rail is six icons; on a narrow module its flank can be too
        // small for them at the full 28pt size, which used to push the last
        // icons under the hardware notch. It shrinks to fit the flank so it
        // always stays visible beside the notch.
        HStack(spacing: railSpacing) {
            NotchIconButton(
                systemImage: "gearshape",
                isActive: false,
                help: "Settings",
                size: railIconSize
            ) {
                // Settings is an ordinary window; leaving the panel expanded
                // over it would float the notch on top of what you opened.
                state.collapse()
                SettingsWindowController.shared.show()
            }

            ForEach(Self.modules, id: \.tab) { module in
                NotchIconButton(
                    systemImage: module.symbol,
                    isActive: state.tab == module.tab,
                    help: state.tab == module.tab ? "Back to Home" : module.name,
                    activeTint: .blue,
                    size: railIconSize
                ) {
                    // Each rail icon toggles home ↔ module, so the icon you
                    // arrived by is also the way back.
                    state.select(state.tab == module.tab ? .home : module.tab)
                }
            }
        }
    }

    /// Rail icon size: the full 28pt when the flank is wide enough for six
    /// of them at the standard 13pt spacing, then 24pt, then 22pt — each tier
    /// is exactly as small as it has to be so the whole rail stays visible
    /// beside the notch instead of its rightmost icons sliding under it.
    private var railIconSize: CGFloat {
        if flankWidth >= 6 * 28 + 5 * 13 { return 28 }
        if flankWidth >= 6 * 24 + 5 * 2 { return 24 }
        return 22
    }

    /// Rail spacing, derived so six icons at `railIconSize` always fit the
    /// flank (with a 2pt floor so they never touch).
    private var railSpacing: CGFloat {
        let count: CGFloat = 6
        let maxSpacing = count * railIconSize + 5 * 13
        guard flankWidth < maxSpacing else { return 13 }
        return max((flankWidth - count * railIconSize) / 5, 2)
    }

    /// Three status controls, as in the reference: the battery pill, the
    /// active Focus, and keep-awake.
    private var trailingControls: some View {
        HStack(spacing: 14) {
            if state.telemetry.hasBattery {
                BatteryPill(
                    percent: Int((state.telemetry.batteryPercent * 100).rounded()),
                    isCharging: state.telemetry.isCharging,
                    showsPercentage: state.settings.showBatteryPercentage
                )
            }

            NotchIconButton(
                systemImage: state.activeFocus?.symbolName ?? "theatermasks",
                isActive: state.activeFocus != nil,
                help: state.activeFocus.map { "Focus: \($0.name)" } ?? "No Focus active",
                activeTint: .purple
            ) {
                state.select(.tools)
            }

            NotchIconButton(
                systemImage: state.keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                isActive: state.keepAwake.isActive,
                help: state.keepAwake.isActive ? "Allow sleep" : "Keep Mac awake",
                activeTint: NotchTheme.battery
            ) {
                withAnimation(NotchAnimations.content) {
                    state.keepAwake.toggle()
                }
            }
        }
    }
}

/// Battery drawn as an outlined pill with the level inside and a terminal
/// nub, mirroring the system menu bar treatment in the reference.
struct BatteryPill: View {
    let percent: Int
    let isCharging: Bool
    let showsPercentage: Bool

    private var fillColor: Color {
        if isCharging { return NotchTheme.battery }
        if percent <= 20 { return .red }
        return .white
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 1.2)

                // Level fill, inset inside the outline.
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(fillColor.opacity(showsPercentage ? 0.3 : 0.85))
                        .frame(width: max(proxy.size.width * CGFloat(percent) / 100, 2))
                        .animation(NotchAnimations.content, value: percent)
                }
                .padding(1.8)

                if showsPercentage {
                    Text("\(percent)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .contentTransition(.numericText())
                } else if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 29, height: 15)

            Capsule()
                .fill(.white.opacity(0.5))
                .frame(width: 2, height: 5.5)
        }
        .overlay(alignment: .leading) {
            // Charging bolt rides outside the pill when the number is inside.
            if isCharging, showsPercentage {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(NotchTheme.battery)
                    .offset(x: -8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue("\(percent) percent" + (isCharging ? ", charging" : ""))
    }
}

/// Detail-screen header: a circular back button on the left and custom
/// trailing controls on the right, over the same reserved notch dead zone.
struct DetailHeaderView<Trailing: View>: View {
    let state: NotchState
    @ViewBuilder var trailing: (CGFloat) -> Trailing

    /// The width each side of the notch is allowed: the header is as wide as
    /// the module, and the two flanks split everything that is not the dead
    /// zone. Content is pinned to this exact share, so it can never render
    /// over the dead zone and under the hardware notch — whatever the module
    /// width or the notch size, the flanks simply truncate their content.
    private var flankWidth: CGFloat {
        max((state.moduleContentSize.width - deadZoneWidth) / 2, 0)
    }

    /// The dead zone's drawn width: the notch size that is guaranteed to
    /// cover the real hardware cutout, measurement error included.
    private var deadZoneWidth: CGFloat {
        state.safeNotchSize.width
    }

    var body: some View {
        HStack(spacing: 0) {
            NotchBackButton {
                state.select(.home)
            }
            .frame(width: flankWidth, alignment: .leading)
            .clipped()

            Rectangle()
                .fill(.black)
                .frame(width: deadZoneWidth)
                .mask { NotchShape() }

            trailing(flankWidth)
                .frame(width: flankWidth, alignment: .trailing)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Circular dark back button with a white chevron, per the reference.
struct NotchBackButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(NotchTheme.inkPrimary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(isHovering ? 0.22 : 0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in
            withAnimation(NotchAnimations.content) {
                isHovering = hovering
            }
        }
        .help("Back to Home")
        .accessibilityLabel("Back to Home")
    }
}

/// A bare icon control: no chrome, just the glyph, brightening on hover and
/// selection.
struct NotchIconButton: View {
    let systemImage: String
    var isActive: Bool = false
    let help: String
    var activeTint: Color? = nil
    var size: CGFloat = 28
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: max(size * 0.46, 11), weight: isActive ? .heavy : .semibold))
                .foregroundStyle(
                    isActive
                        ? (activeTint ?? NotchTheme.inkPrimary)
                        : NotchTheme.inkSecondary.opacity(isHovering ? 1 : 0.72)
                )
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in
            withAnimation(NotchAnimations.content) {
                isHovering = hovering
            }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}
