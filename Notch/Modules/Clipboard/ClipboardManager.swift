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

    private static let historyLimit = 40
    private static let pinnedKey = "clipboardPinned"

    init() {
        // Pinned items survive relaunches; unpinned history does not, which
        // keeps sensitive clipboard content from being written to disk.
        if let saved = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) {
            entries = saved.map { Entry(text: $0, copiedAt: Date(), isPinned: true) }
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
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Ignore items marked transient/concealed (password managers).
        let types = pasteboard.types ?? []
        guard !types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")),
              !types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")),
              !isSelfCopying,
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
    }

    private func persistPinned() {
        UserDefaults.standard.set(
            entries.filter(\.isPinned).map(\.text),
            forKey: Self.pinnedKey
        )
    }
}
