import SwiftUI

/// Week-at-a-glance calendar detail per the reference: a large date header, a
/// Monday-first week strip with the selected day highlighted, and either the
/// day's events or an "All Clear" state. The header's grid toggle swaps the
/// week strip for a full month grid.
struct CalendarDetailView: View {
    let state: NotchState

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        // Budget: NotchState.moduleContentSize, about 136pt tall. Stacking the
        // date header, week strip and agenda vertically needed roughly 200 and
        // silently clipped everything under the strip, so the week view is
        // laid out across instead: the date on the left, the strip and the
        // day's events beside it. The month grid takes the whole panel.
        Group {
            if state.calendar.isMonthView {
                monthGrid
            } else {
                HStack(alignment: .top, spacing: 20) {
                    dateHeader
                        .frame(width: 120, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        weekStrip
                        bodyContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private var dateHeader: some View {
        let selected = state.calendar.selectedDate

        return VStack(alignment: .leading, spacing: -2) {
            Text("\(calendar.component(.day, from: selected))")
                .font(.system(size: 46, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.blue)

            Text(weekdayName(of: selected).uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(NotchTheme.inkPrimary)

            Text(monthYear(of: selected))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTheme.inkSecondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .contentTransition(.numericText())
        .animation(.notchSpring, value: state.calendar.selectedDate)
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        HStack(spacing: 6) {
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

            // Six 17pt rows plus the weekday strip is 130, which fits the
            // panel; at 24 it was 164 and the last two weeks were clipped.
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { _, letter in
                        Text(String(letter))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.inkMuted)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7),
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
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(calendarGreen))
                    .accessibilityHidden(true)

                Text("All Clear")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.inkPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

    private func monthYear(of date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
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
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : NotchTheme.inkSecondary)
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 15, weight: isSelected ? .heavy : .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : NotchTheme.inkPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.blue : (isHovering ? NotchTheme.surfaceHover : Color.clear))
            }
            .overlay(alignment: .topTrailing) {
                if isToday && !isSelected {
                    Circle()
                        .fill(NotchTheme.battery)
                        .frame(width: 4, height: 4)
                        .offset(x: -2, y: 2)
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
                .font(.system(size: 10.5, weight: isSelected ? .heavy : .medium, design: .rounded))
                .foregroundStyle(
                    isInMonth ? (isSelected ? .white : NotchTheme.inkPrimary) : NotchTheme.inkMuted
                )
                .frame(maxWidth: .infinity)
                .frame(height: 17)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.blue : (isHovering ? NotchTheme.surfaceHover : Color.clear))
                }
                .overlay {
                    if isToday && !isSelected {
                        Circle()
                            .strokeBorder(NotchTheme.battery, lineWidth: 1)
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
