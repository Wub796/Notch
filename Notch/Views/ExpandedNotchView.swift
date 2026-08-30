import SwiftUI

/// The open slab's header: a strip of borderless icons flanking the hardware
/// notch, or a detail screen's back button and its own trailing controls. The
/// module below it is drawn by `NotchLayoutView`, so the header and the closed
/// notch's live-activity strip are siblings that swap in place — that is what
/// lets the two states share one animating layout.
struct ExpandedNotchView: View {
    let state: NotchState
    let namespace: Namespace.ID

    var body: some View {
        header
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The rail and a detail screen's back button are different views,
            // so without this the strip cuts from one to the other in the
            // middle of the panel's own resize.
            .id(state.tab)
            .transition(.opacity)
            .animation(NotchAnimations.content, value: state.tab)
    }

    @ViewBuilder
    private var header: some View {
        switch state.tab {
        case .media:
            DetailHeaderView(state: state) { width in
                sourcePill(maxWidth: width)
            }
        case .weather:
            DetailHeaderView(state: state) { width in
                weatherHeaderTrailing(maxWidth: width)
            }
        case .calendar:
            DetailHeaderView(state: state) { width in
                calendarHeaderTrailing(maxWidth: width)
            }
        case .audio:
            // The Devices screen draws its own title and section switch, so
            // the strip carries only the way back — the module rail here would
            // have been a second, competing set of destinations.
            DetailHeaderView(state: state) { _ in
                EmptyView()
            }
        default:
            NotchTopBarView(state: state)
        }
    }

    // MARK: - Detail headers

    /// The media header's right-hand pill: source app icon + name, standing in
    /// for the reference's play-count pill. The label truncates rather than
    /// overflowing, so the pill always stays inside its flank and never under
    /// the hardware notch.
    private func sourcePill(maxWidth: CGFloat) -> some View {
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
                .font(.notchFootnote.weight(.semibold))
                .foregroundStyle(NotchTheme.inkPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.12)))
        .frame(maxWidth: maxWidth, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Source: \(state.media.sourceAppName ?? "none")")
    }

    private func weatherHeaderTrailing(maxWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            forecastChip("Hourly", isActive: !state.showsDailyForecast) {
                state.showsDailyForecast = false
            }
            forecastChip("5 Days", isActive: state.showsDailyForecast) {
                state.showsDailyForecast = true
            }

            NotchIconButton(systemImage: "arrow.clockwise", help: "Refresh weather") {
                state.weather.refresh(force: true)
            }
        }
        .frame(maxWidth: maxWidth, alignment: .trailing)
    }

    /// Flat chips rather than a segmented picker: the picker's chrome reads as
    /// a form control in a panel that has none.
    private func forecastChip(
        _ title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.notchEyebrow)
                .tracking(0.6)
                .lineLimit(1)
                .foregroundStyle(isActive ? NotchTheme.inkPrimary : NotchTheme.inkMuted)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(isActive ? 0.16 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// The reference separates the view toggle from the day controls with thin
    /// rules, and spells "Today" out rather than using a pill.
    private func calendarHeaderTrailing(maxWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            NotchIconButton(
                systemImage: state.calendar.isMonthView ? "calendar" : "square.grid.2x2",
                isActive: state.calendar.isMonthView,
                help: state.calendar.isMonthView ? "Show week view" : "Show month view"
            ) {
                state.calendar.isMonthView.toggle()
            }

            headerDivider

            NotchIconButton(systemImage: "chevron.left", help: "Previous day") {
                state.calendar.moveSelectedDay(by: state.calendar.isMonthView ? -7 : -1)
            }

            headerDivider

            Button {
                state.calendar.moveSelectedDay(to: Date())
            } label: {
                Text("Today")
                    .font(.notchBody.weight(.bold))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .help("Jump to today")

            headerDivider

            NotchIconButton(systemImage: "chevron.right", help: "Next day") {
                state.calendar.moveSelectedDay(by: state.calendar.isMonthView ? 7 : 1)
            }
        }
        .frame(maxWidth: maxWidth, alignment: .trailing)
    }

    private var headerDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(width: 1, height: 16)
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
                    .font(.notchBody)
                    .foregroundStyle(NotchTheme.inkPrimary)
                Text(instantAirDrop
                    ? "Files and text are sent immediately"
                    : "Items stay until you send or clear them")
                    .font(.notchCaption)
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: NotchTheme.Radius.card, style: .continuous)
                .strokeBorder(
                    .blue.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5], dashPhase: dashPhase)
                )
                .background {
                    RoundedRectangle(cornerRadius: NotchTheme.Radius.card, style: .continuous)
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
