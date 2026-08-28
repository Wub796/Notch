import SwiftUI

/// The expanded slab. A single clean surface: a strip of borderless icons
/// flanking the hardware notch along the top, and the active module beneath
/// it. No dividers, no centered controls.
struct ExpandedNotchView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            NotchTopBarView(state: state)
                .frame(height: max(state.notchSize.height, 28))

            Group {
                if state.isDropTargeted || state.shelf.isResolvingDrop {
                    DropZoneView(
                        isResolving: state.shelf.isResolvingDrop,
                        instantAirDrop: state.settings.instantAirDrop
                    )
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Everything stays inside the slab, whatever a module reports.
        .clipped()
        .background {
            // Ambient backdrop on media-bearing tabs: the artwork itself,
            // blurred into a glow behind the glass.
            if state.tab == .home || state.tab == .media {
                Group {
                    if let artwork = state.media.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 70)
                            .saturation(1.6)
                            .opacity(0.2)
                    } else {
                        Ellipse()
                            .fill(state.media.accent)
                            .opacity(0.08)
                            .blur(radius: 60)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.tab {
        case .home:
            HomeDashboardView(state: state, namespace: namespace)
                .transition(.opacity)
        case .media:
            MediaPlayerView(media: state.media, namespace: namespace)
                .transition(.opacity)
        case .shelf:
            ShelfView(shelf: state.shelf)
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

/// Full-surface drop zone shown while a drag hovers over the notch, with a
/// marching-ants border while active.
struct DropZoneView: View {
    let isResolving: Bool
    let instantAirDrop: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dashPhase: CGFloat = 0

    private var title: String {
        if isResolving {
            return instantAirDrop ? "Starting AirDrop…" : "Adding to Shelf…"
        }
        return instantAirDrop ? "Drop to AirDrop" : "Drop to add to Shelf"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isResolving
                ? "wave.3.right.circle.fill"
                : (instantAirDrop ? "airplane.circle.fill" : "tray.and.arrow.down.fill"))
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, isActive: isResolving)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(instantAirDrop
                    ? "Files and text are sent immediately"
                    : "Items stay until you send or clear them")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    .blue.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5], dashPhase: dashPhase)
                )
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.blue.opacity(0.08))
                }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                dashPhase = -12
            }
        }
    }
}
