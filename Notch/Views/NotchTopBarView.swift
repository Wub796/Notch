import AppKit
import SwiftUI

/// The open header: modules on the left, utilities and status on the right,
/// and an exact dead zone between them for the camera housing.
///
/// Drawn after the reference: plain outline glyphs in a quiet grey, the
/// selected one filled and white rather than tinted, the modules running out
/// from the left edge and the utilities and battery packed to the right. The
/// rail is how every screen without a dashboard card is reached.
struct NotchTopBarView: View {
    let state: NotchState

    /// The modules, left to right after Home. Media is a control of its own
    /// rather than only the dashboard's music card, so the player is one click
    /// from any screen.
    static let modules: [(tab: NotchTab, symbol: String, name: String)] = [
        (.audio, "play.circle", "Media"),
        (.shelf, "tray", "Shelf"),
        (.tools, "timer", "Tools"),
        (.telemetry, "chart.xyaxis.line", "System Stats"),
        (.notes, "doc.text", "Notes"),
        (.camera, "video", "Camera"),
    ]

    /// The left rail's control count: Home and every module. `NotchSizing`
    /// floors the slab width against this, so it is derived rather than
    /// written down twice.
    static var railControlCount: Int { modules.count + 1 }

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
        HStack(spacing: NotchSizing.topBarRailSpacing) {
            RailButton(symbol: "house", isSelected: state.tab == .home, help: "Home") {
                state.select(.home)
            }

            ForEach(Self.modules, id: \.tab) { module in
                RailButton(
                    symbol: module.symbol,
                    isSelected: state.tab == module.tab,
                    help: state.tab == module.tab ? "Back to Home" : module.name
                ) {
                    // The media control always lands on the player itself.
                    if module.tab == .audio { state.devicesSection = .now }
                    // Each module toggles home ↔ module, so the control you
                    // arrived by is also the way back.
                    state.select(state.tab == module.tab ? .home : module.tab)
                }
            }
        }
    }

    private var trailingControls: some View {
        HStack(spacing: NotchSizing.topBarRailSpacing) {
            // Only while a Focus is on: an idle mask glyph was one more grey
            // icon that said nothing at a glance.
            if let focus = state.activeFocus {
                RailButton(
                    symbol: focus.symbolName,
                    isSelected: true,
                    tint: .purple,
                    help: "Focus: \(focus.name) — open Tools"
                ) {
                    state.select(.tools)
                }
            }

            RailButton(symbol: "list.clipboard", help: "Clipboard History") {
                // A window of its own, like Settings; leaving the panel open
                // over it would float the notch on top of what you opened.
                state.collapse()
                ClipboardWindowController.shared.show(clipboard: state.clipboard)
            }

            RailButton(
                symbol: "cup.and.saucer",
                isSelected: state.keepAwake.isActive,
                tint: NotchTheme.battery,
                help: state.keepAwake.isActive ? "Allow sleep" : "Keep Mac awake"
            ) {
                withAnimation(NotchAnimations.content) {
                    state.keepAwake.toggle()
                }
            }

            RailButton(symbol: "gearshape", help: "Settings") {
                state.collapse()
                SettingsWindowController.shared.show()
            }

            if state.telemetry.hasBattery {
                BatteryIndicator(
                    percent: Int((state.telemetry.batteryPercent * 100).rounded()),
                    isCharging: state.telemetry.isCharging,
                    showsPercentage: state.settings.showBatteryPercentage
                )
                .padding(.leading, 2)
            }
        }
    }
}

/// A rail control: an outline glyph in quiet grey, filled and white while
/// selected — or filled in `tint`, for a status that is switched on —
/// brightening under the pointer. No chip, no background.
struct RailButton: View {
    let symbol: String
    var isSelected: Bool = false
    var tint: Color? = nil
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolVariant(isSelected ? .fill : .none)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(foreground)
                .frame(
                    width: NotchSizing.topBarRailIconSize,
                    height: NotchSizing.topBarRailIconSize
                )
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
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var foreground: Color {
        if isSelected { return tint ?? .white }
        return .white.opacity(isHovering ? 0.92 : 0.58)
    }
}

/// The battery as the reference draws it: the percentage, then a battery that
/// fills green with a bolt while charging. The body is a filled track rather
/// than an outline.
struct BatteryIndicator: View {
    let percent: Int
    let isCharging: Bool
    let showsPercentage: Bool

    private var level: CGFloat {
        CGFloat(min(max(percent, 0), 100)) / 100
    }

    private var fill: Color {
        if isCharging { return NotchTheme.battery }
        if percent <= 20 { return .red }
        return .white
    }

    var body: some View {
        HStack(spacing: 5) {
            if showsPercentage {
                Text("\(percent)%")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .contentTransition(.numericText())
                    .animation(NotchAnimations.content, value: percent)
                    .fixedSize()
            }

            HStack(spacing: 1.5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.white.opacity(0.22))

                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(fill)
                            .frame(width: max(proxy.size.width * level, 3))
                            .animation(NotchAnimations.content, value: level)
                    }
                    .padding(1.5)

                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8.5, weight: .black))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                    }
                }
                .frame(width: 26, height: 13)

                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(.white.opacity(0.4))
                    .frame(width: 2, height: 5)
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
            Color.clear
                .frame(width: flankWidth)

            Rectangle()
                .fill(.black)
                .frame(width: deadZoneWidth)
                .mask { NotchShape() }

            trailing(flankWidth)
                .frame(width: flankWidth, alignment: .trailing)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            // Pinned to the header's outer (leading) edge rather than centred
            // in the left flank, so it stays put as the module width changes
            // instead of drifting with the flank's midpoint — and flush with
            // that edge, because it *is* the page's leading edge: the header
            // and the module share one, so the button lines up with the month
            // on the calendar page and the hero on the weather page. It used
            // to sit 18pt in, which read as a control floating beside the page
            // rather than its first element.
            NotchBackButton {
                state.select(.home)
            }
            .padding(.top, 2)
        }
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
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
