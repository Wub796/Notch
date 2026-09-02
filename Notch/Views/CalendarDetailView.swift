import SwiftUI

/// Week-at-a-glance calendar detail per the reference: a large date header, a
/// Monday-first week strip with the selected day highlighted, and either the
/// day's events or an "All Clear" state. The header's grid toggle swaps the
/// week strip for a full month grid.
struct CalendarDetailView: View {
    let state: NotchState

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        // Budget: NotchState.moduleContentSize, about 132pt tall. Stacking the
        // date header, week strip and agenda vertically needed roughly 200 and
        // silently clipped everything under the strip, so the week view is
        // laid out across instead: the date on the left, the strip and the
        // day's events beside it. The month grid takes the whole panel.
        Group {
            if state.calendar.isMonthView {
                monthGrid
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    calendarToolbar
                    weekStrip
                    bodyContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.notchSpring, value: state.calendar.isMonthView)
        .onAppear {
            state.calendar.refresh()
        }
    }

    // MARK: - Calendar toolbar

    /// Keeps the month and year together on the left while leaving the
    /// calendar controls on the right. The compact header avoids repeating the
    /// selected day and weekday already shown by the calendar grid.
    private var calendarToolbar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: -2) {
                Text(state.calendar.selectedDate.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .fixedSize()
                Text(state.calendar.selectedDate.formatted(.dateTime.year()))
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .fixedSize()
            }

            Spacer(minLength: 8)
            calendarControls
        }
        .frame(maxWidth: .infinity)
        .contentTransition(.numericText())
        .animation(.notchSpring, value: state.calendar.selectedDate)
    }

    @ViewBuilder
    private var calendarControls: some View {
        HStack(spacing: 8) {
            NotchIconButton(
                systemImage: "chevron.left",
                help: "Previous month"
            ) {
                state.calendar.moveSelectedDay(by: -28)
            }
            NotchIconButton(
                systemImage: "chevron.right",
                help: "Next month"
            ) {
                state.calendar.moveSelectedDay(by: 28)
            }
        }
    }

    /// The month grid's page-by-month chevron, hugged close to the title.
    private func monthButton(
        _ systemImage: String,
        _ help: String,
        _ action: @escaping () -> Void
    ) -> some View {
        NotchIconButton(systemImage: systemImage, help: help, size: 24, action: action)
    }

    /// Small chevron that nudges the year, sitting on the year's baseline.
    private func yearButton(
        _ systemImage: String,
        _ help: String,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(NotchTheme.inkSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(state.calendar.selectedWeek.enumerated()), id: \.offset) { _, day in
                WeekDayCell(
                    day: day,
                    isSelected: calendar.isDate(day, inSameDayAs: state.calendar.selectedDate),
                    isToday: calendar.isDateInToday(day)
                ) {
                    state.calendar.moveSelectedDay(to: day)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Month grid

    @ViewBuilder
    private var monthGrid: some View {
        if let month = calendar.dateInterval(of: .month, for: state.calendar.selectedDate) {
            // Align the 1st to a Monday-first column.
            let leadingDays = (calendar.component(.weekday, from: month.start) + 5) % 7
            let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: month.start)
                ?? month.start
            let days = (0 ..< 42).compactMap {
                calendar.date(byAdding: .day, value: $0, to: gridStart)
            }

            VStack(alignment: .leading, spacing: 8) {
                // The month grid has no toolbar of its own (the week view's
                // date header is only shown there), so carry the month and year
                // here as a full pager: flanking chevrons page by month, and a
                // small stepper under the year pages by year — a single click
                // per month or year instead of many week-long hops.
                HStack(alignment: .center, spacing: 10) {
                    monthButton("chevron.left", "Previous month") {
                        state.calendar.moveSelectedMonth(-1)
                    }

                    Spacer(minLength: 4)

                    VStack(spacing: 1) {
                        Text(state.calendar.selectedDate.formatted(.dateTime.month(.wide)))
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(NotchTheme.inkPrimary)
                        HStack(spacing: 6) {
                            yearButton("chevron.left", "Previous year") {
                                state.calendar.moveSelectedYear(-1)
                            }
                            Text(state.calendar.selectedDate.formatted(.dateTime.year()))
                                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(NotchTheme.inkSecondary)
                            yearButton("chevron.right", "Next year") {
                                state.calendar.moveSelectedYear(1)
                            }
                        }
                    }
                    .contentTransition(.numericText())
                    .animation(.notchSpring, value: state.calendar.selectedDate)

                    Spacer(minLength: 4)

                    monthButton("chevron.right", "Next month") {
                        state.calendar.moveSelectedMonth(1)
                    }
                }

                HStack(spacing: 4) {
                    ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { _, letter in
                        Text(String(letter))
                            .font(.notchBody)
                            .foregroundStyle(NotchTheme.inkSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                    spacing: 2
                ) {
                    ForEach(days, id: \.self) { day in
                        MonthDayCell(
                            day: day,
                            inMonth: month,
                            isSelected: calendar.isDate(day, inSameDayAs: state.calendar.selectedDate),
                            isToday: calendar.isDateInToday(day)
                        ) {
                            state.calendar.moveSelectedDay(to: day)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        let events = state.calendar.itemsOnSelectedDay

        if events.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(calendarGreen))
                    .accessibilityHidden(true)

                Text("All Clear")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)

                Text(state.calendar.accessState == .granted
                     ? "You have no events or reminders scheduled."
                     : "Calendar access is off, so nothing can be shown.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { event in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(cgColor: event.calendarColor ?? .init(gray: 0.7, alpha: 1)))
                            .frame(width: 3, height: 26)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(NotchTheme.inkPrimary)
                                .lineLimit(1)
                            Text(event.start.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(NotchTheme.inkSecondary)
                        }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(NotchTheme.surface)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var calendarGreen: Color {
        Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    }

}

/// A tappable day in the week strip, with hover feedback and the selected
/// highlight.
private struct WeekDayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.notchBody.weight(.heavy))
                    .foregroundStyle(isSelected ? .white : NotchTheme.inkSecondary)
                    .fixedSize()
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(isSelected ? .white : NotchTheme.inkPrimary)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                          ? Color.blue
                          : (isHovering ? NotchTheme.surfaceHover : Color.clear))
            }
            .overlay(alignment: .top) {
                // Today, when it is not the day being looked at, keeps a dot
                // so the strip still says where "now" is.
                if isToday && !isSelected {
                    Circle()
                        .fill(.blue)
                        .frame(width: 5, height: 5)
                        .offset(y: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in
            withAnimation(NotchAnimations.content) { isHovering = hovering }
        }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A tappable day in the month grid, dimmed outside the month.
private struct MonthDayCell: View {
    let day: Date
    let inMonth: DateInterval
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(
                    size: 16,
                    weight: isSelected ? .heavy : .semibold,
                    design: .rounded
                ).monospacedDigit())
                .fixedSize()
                .foregroundStyle(
                    isInMonth ? (isSelected ? .white : NotchTheme.inkPrimary) : NotchTheme.inkMuted
                )
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    // The reference marks the selected day with a circle, not
                    // a rounded rectangle as the week strip does.
                    Circle()
                        .fill(isSelected ? Color.blue : (isHovering ? NotchTheme.surfaceHover : Color.clear))
                        .frame(width: 32, height: 32)
                }
                .overlay {
                    if isToday && !isSelected {
                        // Sized, not stretched: a Circle filling a cell that is
                        // wider than it is tall draws as an ellipse.
                        Circle()
                            .strokeBorder(Color.blue, lineWidth: 1.5)
                            .frame(width: 32, height: 32)
                            .padding(1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering in
            withAnimation(NotchAnimations.content) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
    }

    private var isInMonth: Bool {
        Calendar.current.isDate(day, equalTo: inMonth.start, toGranularity: .month)
    }
}
