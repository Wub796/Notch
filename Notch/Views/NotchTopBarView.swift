import AppKit
import SwiftUI

/// The strip that flanks the hardware notch when the slab is open: tab icons
/// and settings on the left, status controls on the right. Borderless — the
/// glyphs sit directly on the slab, brightening on selection and hover.
struct NotchTopBarView: View {
    let state: NotchState

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 0) {
            leadingIcons
                .padding(.leading, 18)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Reserved dead zone: nothing is drawn behind the camera housing.
            Color.clear
                .frame(width: state.notchSize.width)

            trailingIcons
                .padding(.trailing, 18)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var leadingIcons: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
                BareIconButton(
                    systemImage: tab.systemImage,
                    isActive: state.tab == tab,
                    help: tab.title,
                    badge: tab == .shelf ? state.shelf.items.count : 0
                ) {
                    state.select(tab)
                }
            }

            BareIconButton(
                systemImage: "gearshape",
                isActive: false,
                help: "Settings"
            ) {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
    }

    private var trailingIcons: some View {
        HStack(spacing: 4) {
            if state.telemetry.hasBattery {
                battery
            }

            BareIconButton(
                systemImage: state.keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                isActive: state.keepAwake.isActive,
                help: state.keepAwake.isActive ? "Allow sleep" : "Keep Mac awake"
            ) {
                NotchTheme.Haptics.generic()
                withAnimation(NotchAnimations.content) {
                    state.keepAwake.toggle()
                }
            }

            BareIconButton(
                systemImage: state.isPinned ? "pin.fill" : "pin",
                isActive: state.isPinned,
                help: state.isPinned ? "Unpin" : "Pin the notch open"
            ) {
                state.togglePin()
            }
        }
    }

    private var battery: some View {
        HStack(spacing: 3) {
            if state.settings.showBatteryPercentage {
                Text("\(Int((state.telemetry.batteryPercent * 100).rounded()))")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .contentTransition(.numericText())
            }
            Image(systemName: state.telemetry.isCharging
                ? "battery.100percent.bolt"
                : batterySymbol)
                .font(.system(size: 12.5))
                .foregroundStyle(
                    state.telemetry.isCharging ? NotchTheme.battery : NotchTheme.inkSecondary
                )
        }
        .padding(.trailing, 2)
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

/// Borderless icon button: no chrome, just the glyph, lifting in brightness
/// on hover and selection.
struct BareIconButton: View {
    let systemImage: String
    let isActive: Bool
    let help: String
    var badge: Int = 0
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(
                    isActive
                        ? NotchTheme.inkPrimary
                        : NotchTheme.inkSecondary.opacity(hovering ? 1 : 0.7)
                )
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 8, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.blue))
                            .offset(x: 5, y: -3)
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering in
            withAnimation(NotchAnimations.content) {
                hovering = isHovering
            }
        }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
