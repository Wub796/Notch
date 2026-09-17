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
            // middle of the panel's own resize. Keyed on what the header draws,
            // not on the tab: keyed on the tab, the whole rail faded out and
            // back in on every switch between two modules that share it.
            .id(headerKind)
            .transition(NotchAnimations.headerSwap)
            .animation(NotchAnimations.content, value: headerKind)
    }

    private var headerKind: String {
        switch state.tab {
        case .weather, .calendar, .audio: state.tab.rawValue
        default: "rail"
        }
    }

    @ViewBuilder
    private var header: some View {
        switch state.tab {
        case .weather:
            DetailHeaderView(state: state) { width in
                weatherHeaderTrailing(maxWidth: width)
            }
        case .calendar:
            DetailHeaderView(state: state) { width in
                calendarHeaderTrailing(maxWidth: width)
            }
        case .audio:
            DetailHeaderView(state: state) { _ in
                EmptyView()
            }
        default:
            NotchTopBarView(state: state)
        }
    }

    // MARK: - Detail headers

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
        HStack(spacing: 10) {
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
                    // Never accept compression: at the slab's minimum width
                    // the header flank was tighter than this cluster and the
                    // label ellipsized to "Tod…". fixedSize plus lineLimit(1)
                    // forces the shortfall onto the dividers' slack instead.
                    .fixedSize()
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .help("Jump to today")
            .accessibilityLabel("Today")

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
            // A tinted well rather than a dashed outline: the glyph and the
            // colour already say "drop here".
            RoundedRectangle(cornerRadius: NotchTheme.Radius.card, style: .continuous)
                .fill(.blue.opacity(0.14))
        }
    }
}
