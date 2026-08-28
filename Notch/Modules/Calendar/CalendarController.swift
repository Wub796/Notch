import EventKit
import Foundation
import Observation

/// EventKit-backed timeline of everything happening in the next 24 hours,
/// with virtual-meeting links (Zoom, Teams, Meet, Webex…) extracted for
/// one-click joining.
@Observable
final class CalendarController {
    struct ScheduleItem: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let calendarColor: CGColor?
        let meetingURL: URL?
    }

    enum AccessState {
        case undetermined
        case granted
        case denied
    }

    private(set) var accessState: AccessState = .undetermined
    private(set) var items: [ScheduleItem] = []

    private let store = EKEventStore()

    private static let meetingHosts = [
        "zoom.us",
        "teams.microsoft.com",
        "teams.live.com",
        "meet.google.com",
        "webex.com",
        "whereby.com",
        "around.co",
    ]

    /// Requests access on first use, then reloads the next-24h window.
    /// Called each time the notch expands; EventKit queries are cheap and this
    /// keeps the timeline current without any background refresh timer.
    func refresh() {
        switch accessState {
        case .denied:
            return
        case .granted:
            loadEvents()
        case .undetermined:
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.accessState = granted ? .granted : .denied
                    if granted {
                        self.loadEvents()
                    }
                }
            }
        }
    }

    private func loadEvents() {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now,
            end: now.addingTimeInterval(24 * 60 * 60),
            calendars: nil
        )

        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        items = events.map { event in
            ScheduleItem(
                id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "Untitled event",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarColor: event.calendar?.cgColor,
                meetingURL: Self.detectMeetingURL(in: event)
            )
        }
    }

    // MARK: - Meeting link detection

    static func detectMeetingURL(in event: EKEvent) -> URL? {
        var candidates: [URL] = []
        if let url = event.url {
            candidates.append(url)
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in [event.location, event.notes].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            detector?.enumerateMatches(in: text, range: range) { match, _, _ in
                if let url = match?.url {
                    candidates.append(url)
                }
            }
        }

        return candidates.first { url in
            guard let host = url.host?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        }
    }
}
