import AppKit
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

    /// The day highlighted in the calendar detail view. Moving it outside the
    /// range currently loaded triggers a refetch, which is what makes any day
    /// but today show anything at all.
    var selectedDate = Date() {
        didSet {
            guard accessState == .granted,
                  !Calendar.current.isDate(selectedDate, equalTo: oldValue, toGranularity: .month)
            else { return }
            loadEvents()
        }
    }

    /// Whether the calendar detail shows the month grid instead of the week.
    var isMonthView = false

    /// Days in the week (Monday-first) that contains `selectedDate`.
    var selectedWeek: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return []
        }
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    /// Events whose start falls on the selected day.
    var itemsOnSelectedDay: [ScheduleItem] {
        items.filter { Calendar.current.isDate($0.start, inSameDayAs: selectedDate) }
    }

    func moveSelectedDay(by days: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = date
        }
    }

    func moveSelectedDay(to date: Date) {
        selectedDate = date
    }

    /// Steps `selectedDate` to a neighbouring month, keeping the day of the
    /// month (clamped, so 31 Jan can move to Feb 28 rather than rolling over
    /// into March). Page-by-month is what the month grid's chevrons use.
    func moveSelectedMonth(_ offset: Int) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: selectedDate)
        guard let firstOfMonth = cal.date(from: DateComponents(year: comps.year, month: comps.month)),
              let targetFirst = cal.date(byAdding: .month, value: offset, to: firstOfMonth),
              let daysInMonth = cal.range(of: .day, in: .month, for: targetFirst)?.count,
              let day = cal.date(bySetting: .day, value: min(comps.day ?? 1, daysInMonth), of: targetFirst)
        else { return }
        moveSelectedDay(to: day)
    }

    /// Steps `selectedDate` by whole years (Feb 29 clamps to Feb 28).
    func moveSelectedYear(_ offset: Int) {
        guard let target = Calendar.current.date(byAdding: .year, value: offset, to: selectedDate) else { return }
        moveSelectedDay(to: target)
    }

    /// The next event starting within the live-activity window, published in
    /// the collapsed notch wings.
    private(set) var upcomingSoon: ScheduleItem?

    private let store = EKEventStore()
    private var upcomingWork: [DispatchWorkItem] = []
    private static let upcomingWindow: TimeInterval = 15 * 60
    private static let upcomingGrace: TimeInterval = 5 * 60

    init() {
        // Wake on external calendar edits so the timeline and the
        // meeting-soon activity stay correct without polling.
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            guard let self, self.accessState == .granted else { return }
            self.loadEvents()
        }
    }

    /// If access was granted in an earlier launch, load immediately so the
    /// meeting-soon activity works before the notch is ever expanded.
    func bootstrapIfAuthorized() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            accessState = .granted
            loadEvents()
        case .denied, .restricted:
            accessState = .denied
        default:
            accessState = .undetermined
        }
    }

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
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted, .writeOnly:
            accessState = .denied
            return
        case .fullAccess, .authorized:
            accessState = .granted
            loadEvents()
        case .notDetermined:
            requestAccess()
        @unknown default:
            break
        }
    }

    /// Explicit entry point to prompt the user for calendar permissions.
    func requestAccess(completion: (() -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.accessState = granted ? .granted : .denied
                    if granted {
                        self.loadEvents()
                    }
                    completion?()
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.accessState = granted ? .granted : .denied
                    if granted {
                        self.loadEvents()
                    }
                    completion?()
                }
            }
        }
    }

    /// Loads the whole month around `selectedDate`, unioned with the next 24
    /// hours.
    ///
    /// This used to fetch only the next 24 hours, which meant the calendar
    /// screen was empty for every day except today — the events were never
    /// requested, so no amount of navigating could show them. The 24-hour part
    /// is still needed on its own because the meeting-soon activity has to
    /// work when the selected month is somewhere else entirely.
    private func loadEvents() {
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: selectedDate)

        // The month grid draws leading and trailing days from the neighbouring
        // months, so pad a week either side or those cells look empty.
        let padding: TimeInterval = 7 * 24 * 60 * 60
        let start = min(now, (month?.start ?? now).addingTimeInterval(-padding))
        let end = max(now.addingTimeInterval(24 * 60 * 60),
                      (month?.end ?? now).addingTimeInterval(padding))

        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let events = self.store.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }

            let mapped = events.map { event in
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

            DispatchQueue.main.async { [weak self] in
                self?.items = mapped
                self?.armUpcomingWatch()
            }
        }
    }

    // MARK: - Meeting-soon live activity

    /// One-shot timers (not polling) that raise/lower the meeting-soon
    /// activity: show at start − 15 min, clear at start + 5 min, then re-arm
    /// for the following event.
    private func armUpcomingWatch() {
        guard NotchSettings.shared.liveActivitiesEnabled else {
            upcomingSoon = nil
            return
        }

        upcomingWork.forEach { $0.cancel() }
        upcomingWork.removeAll()

        let now = Date()
        // The window now spans a month, so this has to exclude everything
        // before now rather than relying on the fetch range to do it.
        let candidate = items.first {
            !$0.isAllDay
                && $0.start.timeIntervalSince(now) > -Self.upcomingGrace
                && $0.start.timeIntervalSince(now) < 24 * 60 * 60
        }

        guard let event = candidate else {
            upcomingSoon = nil
            return
        }

        let showAt = event.start.addingTimeInterval(-Self.upcomingWindow)
        let clearAt = event.start.addingTimeInterval(Self.upcomingGrace)

        if now >= showAt {
            upcomingSoon = event
        } else {
            upcomingSoon = nil
            schedule(at: showAt) { [weak self] in
                self?.upcomingSoon = event
            }
        }

        schedule(at: clearAt) { [weak self] in
            self?.upcomingSoon = nil
            self?.loadEvents()
        }
    }

    private func schedule(at date: Date, _ action: @escaping () -> Void) {
        let work = DispatchWorkItem(block: action)
        upcomingWork.append(work)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(date.timeIntervalSinceNow, 0),
            execute: work
        )
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
