import Foundation
import Observation

/// A persistent scratchpad. Typing is debounced; leaving or quitting flushes
/// the newest text so the debounce window cannot cost an edit.
@Observable
final class NotesManager {
    var text: String {
        didSet {
            guard text != oldValue else { return }
            clearedText = nil
            scheduleSave()
        }
    }

    private(set) var lastSavedAt: Date?
    private(set) var hasUnsavedChanges = false
    private var clearedText: String?
    private var saveWork: DispatchWorkItem?
    private let defaults: UserDefaults
    private static let storageKey = "scratchpadText"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        text = defaults.string(forKey: Self.storageKey) ?? ""
    }

    deinit { saveWork?.cancel() }

    var characterCount: Int { text.count }
    var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
    var canUndoClear: Bool { clearedText != nil && text.isEmpty }

    func clear() {
        guard !text.isEmpty else { return }
        let previous = text
        text = ""
        clearedText = previous
        flush()
    }

    func undoClear() {
        guard canUndoClear, let previous = clearedText else { return }
        text = previous
        flush()
    }

    /// Safe to call repeatedly; only pending text is written.
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        guard hasUnsavedChanges else { return }
        defaults.set(text, forKey: Self.storageKey)
        lastSavedAt = Date()
        hasUnsavedChanges = false
    }

    private func scheduleSave() {
        hasUnsavedChanges = true
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
