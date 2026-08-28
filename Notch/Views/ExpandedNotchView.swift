import SwiftUI

/// Expanded state: header strip, tab bar, and the active feature module — or
/// the drop zone while a drag hovers over the notch. An ambient glow in the
/// artwork accent breathes behind the media tab.
struct ExpandedNotchView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 10) {
            if state.isDropTargeted || state.shelf.isResolvingDrop {
                DropZoneView(
                    isResolving: state.shelf.isResolvingDrop,
                    instantAirDrop: state.settings.instantAirDrop
                )
            } else {
                NotchHeaderView(state: state)
                tabBar
                content
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            if state.tab == .media, state.media.artwork != nil {
                Ellipse()
                    .fill(state.media.accent)
                    .opacity(0.13)
                    .blur(radius: 55)
                    .frame(width: 440, height: 220)
                    .offset(y: -30)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.notchSpring, value: state.tab)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    state.select(tab)
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if state.tab == tab {
                                Capsule()
                                    .fill(.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "tabHighlight", in: namespace)
                            }
                        }
                        .foregroundStyle(state.tab == tab ? NotchTheme.inkPrimary : NotchTheme.inkSecondary)
                        .overlay(alignment: .topTrailing) {
                            if tab == .shelf, state.shelf.items.count > 0 {
                                Text("\(state.shelf.items.count)")
                                    .font(.system(size: 8, weight: .heavy).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(.blue))
                                    .offset(x: 6, y: -5)
                            }
                        }
                }
                .buttonStyle(PressableButtonStyle())
            }
            Spacer()
        }
        .animation(.notchSpring, value: state.tab)
    }

    @ViewBuilder
    private var content: some View {
        switch state.tab {
        case .media:
            MediaPlayerView(media: state.media, namespace: namespace)
                .transition(.glass)
        case .shelf:
            ShelfView(shelf: state.shelf)
                .transition(.glass)
        case .calendar:
            CalendarView(calendar: state.calendar)
                .transition(.glass)
        case .telemetry:
            TelemetryView(telemetry: state.telemetry)
                .transition(.glass)
        }
    }
}

/// Full-surface drop zone shown while a drag hovers over the notch.
struct DropZoneView: View {
    let isResolving: Bool
    let instantAirDrop: Bool

    private var title: String {
        if isResolving {
            return instantAirDrop ? "Starting AirDrop…" : "Adding to Shelf…"
        }
        return instantAirDrop ? "Drop to AirDrop" : "Drop to add to Shelf"
    }

    private var subtitle: String {
        instantAirDrop
            ? "Files and text are sent immediately"
            : "Items stay on the shelf until you send or clear them"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isResolving
                ? "wave.3.right.circle.fill"
                : (instantAirDrop ? "airplane.circle.fill" : "tray.and.arrow.down.fill"))
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, isActive: isResolving)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    .blue.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.blue.opacity(0.08))
                }
        }
    }
}
