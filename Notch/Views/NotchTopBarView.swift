import AppKit
import SwiftUI

/// The home top bar: a settings gear and shelf tray on the left, system status
/// icons on the right. No tab navigation — the dashboard's music/weather/
/// calendar sections drill into the detail screens, matching the reference.
struct NotchTopBarView: View {
    let state: NotchState

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 0) {
            leadingControls
                .frame(maxWidth: .infinity, alignment: .leading)

            // Reserved dead zone: nothing is drawn behind the camera housing.
            Color.clear
                .frame(width: state.notchSize.width)

            trailingControls
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var leadingControls: some View {
        HStack(spacing: 16) {
            NotchIconButton(
                systemImage: "gearshape",
                isActive: false,
                help: "Settings"
            ) {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }

            NotchIconButton(
                systemImage: "archivebox",
                isActive: state.tab == .shelf,
                help: state.tab == .shelf ? "Back to Home" : "Shelf",
                activeTint: .blue
            ) {
                // The tray toggles home ↔ shelf — the only affordance that
                // reaches the shelf, so it must also be the way back.
                state.select(state.tab == .shelf ? .home : .shelf)
            }
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 16) {
            if state.telemetry.hasBattery {
                battery
            }

            audioOutput

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

            // Charging state — a status indicator, not a control.
            Image(systemName: "battery.100percent.bolt")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    state.telemetry.isCharging ? NotchTheme.battery : NotchTheme.inkMuted
                )
                .frame(width: 28, height: 28)
                .help(state.telemetry.isCharging ? "Battery charging" : "On battery")
                .accessibilityLabel(state.telemetry.isCharging ? "Battery charging" : "On battery")
        }
    }

    private var audioOutput: some View {
        let device = state.audio.devices.first {
            $0.id == state.audio.currentDeviceID
        }
        return NotchIconButton(
            systemImage: state.audio.currentSymbol,
            isActive: false,
            help: device.map { "Audio: \($0.name)" } ?? "Audio output"
        ) {
            state.audio.cycleToNextDevice()
        }
    }

    private var battery: some View {
        HStack(spacing: 3) {
            if state.settings.showBatteryPercentage {
                Text("\(Int((state.telemetry.batteryPercent * 100).rounded()))")
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .contentTransition(.numericText())
            }
            Image(systemName: batterySymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    state.telemetry.isCharging ? NotchTheme.battery : NotchTheme.inkSecondary
                )
        }
        .padding(.horizontal, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(
            "\(Int((state.telemetry.batteryPercent * 100).rounded())) percent"
            + (state.telemetry.isCharging ? ", charging" : "")
        )
    }

    private var batterySymbol: String {
        switch state.telemetry.batteryPercent {
        case ..<0.15: "battery.0percent"
        case ..<0.4: "battery.25percent"
        case ..<0.65: "battery.50percent"
        case ..<0.9: "battery.75percent"
        default: "battery.100percent"
        }
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
                .frame(width: state.notchSize.width)

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
