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
                VStack(alignment: .leading, spacing: 16) {
                    dateHeader
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

    // MARK: - Date header

    /// The big blue day number beside its weekday, month and year, as in the
    /// reference. The month carries the weight and the year sits under it a
    /// size down; all three lines share the same left edge.
    private var dateHeader: some View {
        let selected = state.calendar.selectedDate

        return HStack(alignment: .center, spacing: 12) {
            Text("\(calendar.component(.day, from: selected))")
                .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.blue)
                .fixedSize()

            VStack(alignment: .leading, spacing: -1) {
                Text(weekdayName(of: selected).uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .fixedSize()

                Text(selected.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)
                    .fixedSize()

                Text(selected.formatted(.dateTime.year()))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
                    .fixedSize()
            }

            Spacer(minLength: 0)
        }
        .contentTransition(.numericText())
        .animation(.notchSpring, value: state.calendar.selectedDate)
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
            }
        }
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

            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { _, letter in
                        Text(String(letter))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
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

    private func weekdayName(of date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
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
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
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
