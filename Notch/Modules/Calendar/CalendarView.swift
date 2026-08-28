import AppKit
import SwiftUI

/// Scrolling timeline of the next 24 hours, with one-click join buttons for
/// events that carry a virtual meeting link.
struct CalendarView: View {
    let calendar: CalendarController

    var body: some View {
        Group {
            switch calendar.accessState {
            case .denied:
                message(
                    icon: "calendar.badge.exclamationmark",
                    title: "Calendar access denied",
                    subtitle: "Enable it in System Settings → Privacy & Security → Calendars"
                )
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
                timeline
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.35))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timeline: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 7) {
                ForEach(calendar.items) { item in
                    EventRow(item: item)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct EventRow: View {
    let item: CalendarController.ScheduleItem

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(calendarColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timeLabel)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
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
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(0.06))
        }
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
}
