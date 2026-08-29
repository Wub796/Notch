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
        (.tools, "wrench.and.screwdriver", "Tools"),
        (.telemetry, "gauge.with.dots.needle.50percent", "System Stats"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            leadingControls
                .frame(maxWidth: .infinity, alignment: .leading)

            // Reserved dead zone: nothing is drawn behind the camera housing.
            Color.clear
                .frame(width: state.adjustedNotchSize.width)

            trailingControls
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var leadingControls: some View {
        HStack(spacing: 13) {
            NotchIconButton(
                systemImage: "gearshape",
                isActive: false,
                help: "Settings"
            ) {
                // Settings is an ordinary window; leaving the panel expanded
                // over it would float the notch on top of what you opened.
                state.collapse()
                SettingsLauncher.open()
            }

            ForEach(Self.modules, id: \.tab) { module in
                NotchIconButton(
                    systemImage: module.symbol,
                    isActive: state.tab == module.tab,
                    help: state.tab == module.tab ? "Back to Home" : module.name,
                    activeTint: .blue
                ) {
                    // Each rail icon toggles home ↔ module, so the icon you
                    // arrived by is also the way back.
                    state.select(state.tab == module.tab ? .home : module.tab)
                }
            }
        }
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
                NotchTheme.Haptics.generic()
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
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            NotchBackButton {
                state.select(.home)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: state.adjustedNotchSize.width)

            trailing()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 34)
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
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: isActive ? .heavy : .semibold))
                .foregroundStyle(
                    isActive
                        ? (activeTint ?? NotchTheme.inkPrimary)
                        : NotchTheme.inkSecondary.opacity(isHovering ? 1 : 0.72)
                )
                .frame(width: 28, height: 28)
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
