import AppKit
import Observation

/// Clipboard history with pinning — Sapphire's clipboard module. macOS has no
/// pasteboard-change notification, so this is the app's one genuinely
/// periodic task; it is opt-in and can be turned off in Settings.
@Observable
final class ClipboardManager {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let copiedAt: Date
        var isPinned: Bool

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.id == rhs.id && lhs.isPinned == rhs.isPinned
        }
    }

    private(set) var entries: [Entry] = []

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var isSelfCopying = false

    private static let pinnedKey = "clipboardPinned"
    /// Pinned entries are stored as `copiedAt` epoch seconds keyed by text, so
    /// a relaunch restores when each was actually copied rather than stamping
    /// them all "just now".
    private static let pinnedDatesKey = "clipboardPinnedDates"

    init() {
        // Pinned items survive relaunches; unpinned history does not, which
        // keeps sensitive clipboard content from being written to disk.
        guard let saved = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) else {
            return
        }
        let dates = UserDefaults.standard
            .dictionary(forKey: Self.pinnedDatesKey) as? [String: Double] ?? [:]
        entries = saved.map { text in
            Entry(
                text: text,
                // Falling back to "now" only for entries pinned by a build that
                // did not record the date.
                copiedAt: dates[text].map(Date.init(timeIntervalSince1970:)) ?? Date(),
                isPinned: true
            )
        }
    }

    func start() {
        guard timer == nil, NotchSettings.shared.clipboardHistoryEnabled else { return }
        timer = Timer.scheduledRepeating(every: 1.0) { [weak self] in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        // `copyBack` already recorded its own change count, so anything still
        // arriving here is somebody else's copy. Claim it *after* that test,
        // not before: advancing `lastChangeCount` up front meant a real copy
        // landing inside the 0.3s self-copy window was swallowed and never
        // reached the history at all.
        guard !isSelfCopying else { return }
        lastChangeCount = changeCount

        // Ignore items marked transient/concealed (password managers).
        let types = pasteboard.types ?? []
        guard !types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")),
              !types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")),
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        record(text)
    }

    private func record(_ text: String) {
        if let index = entries.firstIndex(where: { $0.text == text }) {
            // Re-copying an existing entry floats it back to the top.
            let existing = entries.remove(at: index)
            entries.insert(
                Entry(text: text, copiedAt: Date(), isPinned: existing.isPinned),
                at: 0
            )
        } else {
            entries.insert(Entry(text: text, copiedAt: Date(), isPinned: false), at: 0)
        }
        trim()
    }

    private func trim() {
        let capacity = NotchSettings.shared.clipboardMaxCapacity
        guard entries.count > capacity else { return }
        var kept: [Entry] = []
        for entry in entries where kept.count < capacity || entry.isPinned {
            kept.append(entry)
        }
        entries = kept
    }

    // MARK: - Actions

    func copyBack(_ entry: Entry) {
        isSelfCopying = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isSelfCopying = false
        }
    }

    func togglePin(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
        entries.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.copiedAt > rhs.copiedAt
        }
        persistPinned()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        persistPinned()
    }

    func clearUnpinned() {
        entries.removeAll { !$0.isPinned }
        persistPinned()
    }

    private func persistPinned() {
        let pinned = entries.filter(\.isPinned)
        UserDefaults.standard.set(pinned.map(\.text), forKey: Self.pinnedKey)
        UserDefaults.standard.set(
            Dictionary(
                pinned.map { ($0.text, $0.copiedAt.timeIntervalSince1970) },
                uniquingKeysWith: max
            ),
            forKey: Self.pinnedDatesKey
        )
    }
}
