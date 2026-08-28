import SwiftUI

/// Expanded state: tab bar plus the active feature module, or the AirDrop
/// zone while a drag hovers over the notch.
struct ExpandedNotchView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 10) {
            if state.isDropTargeted || state.airDrop.isResolvingDrop {
                AirDropZoneView(isResolving: state.airDrop.isResolvingDrop)
            } else {
                tabBar
                content
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        .foregroundStyle(state.tab == tab ? .white : .white.opacity(0.55))
                }
                .buttonStyle(.plain)
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
                .transition(.opacity)
        case .calendar:
            CalendarView(calendar: state.calendar)
                .transition(.opacity)
        case .telemetry:
            TelemetryView(telemetry: state.telemetry)
                .transition(.opacity)
        }
    }
}

/// Full-surface drop zone shown while a drag hovers over the notch.
struct AirDropZoneView: View {
    let isResolving: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isResolving ? "wave.3.right.circle.fill" : "airplane.circle.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, isActive: isResolving)

            Text(isResolving ? "Starting AirDrop…" : "Drop to AirDrop")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Files and text are sent immediately")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
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
