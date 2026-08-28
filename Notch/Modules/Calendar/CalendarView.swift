import AppKit
import SwiftUI

/// Scrolling timeline of the next 24 hours. Events in progress are marked
/// "Now", the next upcoming event carries a live countdown, and events with a
/// detected meeting link get a one-click Join button. Countdown labels
/// refresh every minute via TimelineView.
struct CalendarView: View {
    let calendar: CalendarController

    var body: some View {
        Group {
            switch calendar.accessState {
            case .denied:
                VStack(spacing: 10) {
                    message(
                        icon: "calendar.badge.exclamationmark",
                        title: "Calendar access denied",
                        subtitle: "Notch needs calendar access to show your next 24 hours"
                    )
                    Button {
                        if let url = URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Open Privacy Settings")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(NotchTheme.surfaceHover))
                            .foregroundStyle(NotchTheme.inkPrimary)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .hoverLift(1.04)
                    .padding(.bottom, 8)
                }
            case .undetermined:
                message(
                    icon: "calendar",
                    title: "Requesting calendar access…",
                    subtitle: "Your next 24 hours will appear here"
                )
            case .granted where calendar.items.isEmpty:
                message(
                    icon: "sparkles",
                    title: "Nothing scheduled",
                    subtitle: "You're free for the next 24 hours"
                )
            case .granted:
                TimelineView(.everyMinute) { context in
                    timeline(now: context.date)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(NotchTheme.inkMuted)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.inkPrimary.opacity(0.8))
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeline(now: Date) -> some View {
        let nextUpcomingID = calendar.items
            .first { !$0.isAllDay && $0.start > now }?
            .id
        let todayItems = calendar.items.filter { Calendar.current.isDateInToday($0.start) }
        let laterItems = calendar.items.filter { !Calendar.current.isDateInToday($0.start) }

        return ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 7) {
                if !todayItems.isEmpty {
                    dayHeader("Today")
                    ForEach(todayItems) { item in
                        EventRow(item: item, now: now, isNextUpcoming: item.id == nextUpcomingID)
                    }
                }
                if !laterItems.isEmpty {
                    dayHeader("Tomorrow")
                        .padding(.top, todayItems.isEmpty ? 0 : 5)
                    ForEach(laterItems) { item in
                        EventRow(item: item, now: now, isNextUpcoming: item.id == nextUpcomingID)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func dayHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(NotchTheme.inkMuted)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct EventRow: View {
    let item: CalendarController.ScheduleItem
    let now: Date
    let isNextUpcoming: Bool

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private var isOngoing: Bool {
        !item.isAllDay && item.start <= now && now < item.end
    }

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(calendarColor)
                .frame(width: isOngoing ? 4 : 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotchTheme.inkPrimary)
                        .lineLimit(1)
                    statusChip
                }
                Text(timeLabel)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(NotchTheme.inkSecondary)
            }

            Spacer(minLength: 8)

            if let url = item.meetingURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Join", systemImage: "video.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.green.opacity(0.85)))
                        .foregroundStyle(.black)
                }
                .buttonStyle(PressableButtonStyle())
                .hoverLift(1.05)
                .accessibilityLabel("Join \(item.title)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isOngoing ? NotchTheme.surfaceHover : NotchTheme.surface)
        }
        .overlay {
            if isOngoing {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(calendarColor.opacity(0.5), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if isOngoing {
            chip("Now", tint: .green)
        } else if isNextUpcoming {
            chip(Self.countdownLabel(to: item.start, from: now), tint: .orange)
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .contentTransition(.numericText())
    }

    private var calendarColor: Color {
        if let cgColor = item.calendarColor, let nsColor = NSColor(cgColor: cgColor) {
            return Color(nsColor: nsColor)
        }
        return .accentColor
    }

    private var timeLabel: String {
        if item.isAllDay {
            return "All day"
        }
        let start = Self.timeFormatter.string(from: item.start)
        let end = Self.timeFormatter.string(from: item.end)
        return "\(start) – \(end)"
    }

    static func countdownLabel(to date: Date, from now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        switch minutes {
        case ..<1:
            return "now"
        case ..<60:
            return "in \(minutes) min"
        default:
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "in \(hours) h" : "in \(hours) h \(remainder) min"
        }
    }
}
