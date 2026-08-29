import SwiftUI

/// The expanded slab. A single black surface: a strip of borderless icons
/// flanking the hardware notch along the top, and the active module beneath
/// it. No dividers, no centered controls.
struct ExpandedNotchView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            // Tall enough to drop the icons clear of the screen's top edge on
            // every display, not just notched ones.
            header
                .frame(height: max(state.notchSize.height, 38))

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
            .padding(.horizontal, 42)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Everything stays inside the slab, whatever a module reports.
        .clipped()
    }

    @ViewBuilder
    private var header: some View {
        switch state.tab {
        case .media:
            DetailHeaderView(state: state) {
                sourcePill
            }
        case .weather:
            DetailHeaderView(state: state) {
                weatherHeaderTrailing
            }
        case .calendar:
            DetailHeaderView(state: state) {
                calendarHeaderTrailing
            }
        default:
            NotchTopBarView(state: state)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.tab {
        case .home:
            HomeDashboardView(state: state, namespace: namespace)
                .transition(.opacity)
        case .media:
            MediaPlayerView(state: state, namespace: namespace)
                .transition(.opacity)
        case .weather:
            WeatherDetailView(state: state)
                .transition(.opacity)
        case .calendar:
            CalendarDetailView(state: state)
                .transition(.opacity)
        case .shelf:
            ShelfView(shelf: state.shelf)
                .transition(.opacity)
        case .clipboard:
            ClipboardView(clipboard: state.clipboard)
                .transition(.opacity)
        case .tools:
            ToolsView(state: state)
                .transition(.opacity)
        case .notes:
            NotesView(notes: state.notes)
                .transition(.opacity)
        case .telemetry:
            TelemetryView(telemetry: state.telemetry)
                .transition(.opacity)
        }
    }

    // MARK: - Detail headers

    /// The media header's right-hand pill: source app icon + name, standing in
    /// for the reference's play-count pill.
    private var sourcePill: some View {
        HStack(spacing: 6) {
            if let icon = state.media.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .clipShape(Circle())
            } else {
                Image(systemName: state.media.isPlaying ? "play.fill" : "music.note")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NotchTheme.inkPrimary)
            }
            Text(state.media.sourceAppName ?? "Not Playing")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Source: \(state.media.sourceAppName ?? "none")")
    }

    private var weatherHeaderTrailing: some View {
        HStack(spacing: 8) {
            Text(updatedLabel)
                .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(NotchTheme.inkMuted)

            NotchIconButton(systemImage: "arrow.clockwise", help: "Refresh weather") {
                state.weather.refresh(force: true)
            }
        }
    }

    private var updatedLabel: String {
        guard let snapshot = state.weather.snapshot else { return "No data yet" }
        let ago = Date().timeIntervalSince(snapshot.fetchedAt)
        if ago < 60 { return "Updated just now" }
        return "Updated \(Int(ago / 60))m ago"
    }

    private var calendarHeaderTrailing: some View {
        HStack(spacing: 12) {
            NotchIconButton(
                systemImage: state.calendar.isMonthView ? "square.grid.2x2.fill" : "square.grid.2x2",
                isActive: state.calendar.isMonthView,
                help: state.calendar.isMonthView ? "Show week view" : "Show month view"
            ) {
                state.calendar.isMonthView.toggle()
            }
            NotchIconButton(systemImage: "chevron.left", help: "Previous day") {
                state.calendar.moveSelectedDay(by: -1)
            }

            TodayPillButton {
                state.calendar.moveSelectedDay(to: Date())
            }

            NotchIconButton(systemImage: "chevron.right", help: "Next day") {
                state.calendar.moveSelectedDay(by: 1)
            }
        }
    }
}

/// Pill button that jumps the calendar selection to today.
private struct TodayPillButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("Today")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(isHovering ? 0.2 : 0.12)))
                .overlay {
                    Capsule().strokeBorder(.white.opacity(isHovering ? 0.55 : 0.35), lineWidth: 0.75)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in
            withAnimation(NotchAnimations.content) {
                isHovering = hovering
            }
        }
        .help("Jump to today")
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
