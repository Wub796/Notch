import AppKit
import Observation

/// Only pinned copies are persisted. Recent history is memory-only, and
/// polling never reads changes made while recording was switched off.
@Observable
final class ClipboardManager {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let text: String
        let copiedAt: Date
        var isPinned: Bool

        init(id: UUID = UUID(), text: String, copiedAt: Date, isPinned: Bool) {
            self.id = id
            self.text = text
            self.copiedAt = copiedAt
            self.isPinned = isPinned
        }
    }

    private(set) var entries: [Entry] = []
    private var timer: Timer?
    private var lastChangeCount: Int
    private let pasteboard: NSPasteboard
    private let defaults: UserDefaults
    private let isEnabled: () -> Bool
    private let capacity: () -> Int

    private static let pinnedKey = "clipboardPinned"
    private static let pinnedDatesKey = "clipboardPinnedDates"

    init(
        pasteboard: NSPasteboard = .general,
        defaults: UserDefaults = .standard,
        isEnabled: @escaping () -> Bool = { NotchSettings.shared.clipboardHistoryEnabled },
        capacity: @escaping () -> Int = { NotchSettings.shared.clipboardMaxCapacity }
    ) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.isEnabled = isEnabled
        self.capacity = capacity
        lastChangeCount = pasteboard.changeCount
        let saved = defaults.stringArray(forKey: Self.pinnedKey) ?? []
        let dates = defaults.dictionary(forKey: Self.pinnedDatesKey) as? [String: Double] ?? [:]
        var seen = Set<String>()
        entries = saved.filter { seen.insert($0).inserted }.map { text in
            Entry(text: text, copiedAt: dates[text].map(Date.init(timeIntervalSince1970:)) ?? Date(), isPinned: true)
        }
        sortEntries()
    }

    deinit { timer?.invalidate() }

    func start() {
        guard timer == nil, isEnabled() else { return }
        // Establish a fresh boundary each time recording is enabled. A copy
        // made while disabled must not be collected by the first new tick.
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledRepeating(every: 1.0) { [weak self] in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        guard isEnabled() else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

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
            let existing = entries.remove(at: index)
            entries.append(Entry(id: existing.id, text: text, copiedAt: Date(), isPinned: existing.isPinned))
        } else {
            entries.append(Entry(text: text, copiedAt: Date(), isPinned: false))
        }
        sortEntries()
        trimToCapacity()
        if entries.contains(where: { $0.text == text && $0.isPinned }) { persistPinned() }
    }

    /// The preference limits recent entries; pins never use up that budget.
    /// Invoked by the settings callback as well as after recording/unpinning.
    func trimToCapacity() {
        let limit = min(max(capacity(), 1), 100)
        var recentCount = 0
        entries = entries.filter { entry in
            if entry.isPinned { return true }
            recentCount += 1
            return recentCount <= limit
        }
    }

    // MARK: - Actions

    func copyBack(_ entry: Entry) {
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        // No timed self-copy window: this exact change is ours, and a real
        // copy arriving immediately afterwards must still be recorded.
        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
        sortEntries()
        trimToCapacity()
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

    private func sortEntries() {
        entries.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.copiedAt > rhs.copiedAt
        }
    }

    private func persistPinned() {
        let pinned = entries.filter(\.isPinned)
        defaults.set(pinned.map(\.text), forKey: Self.pinnedKey)
        defaults.set(Dictionary(pinned.map { ($0.text, $0.copiedAt.timeIntervalSince1970) }, uniquingKeysWith: max),
                     forKey: Self.pinnedDatesKey)
    }
}
