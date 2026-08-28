import Foundation
import Observation

/// A persistent scratchpad in the notch (Sapphire's notes module). Plain
/// text, saved to defaults, debounced so typing doesn't thrash the disk.
@Observable
final class NotesManager {
    var text: String {
        didSet { scheduleSave() }
    }

    private(set) var lastSavedAt: Date?

    private var saveWork: DispatchWorkItem?
    private static let storageKey = "scratchpadText"

    init() {
        text = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
    }

    var characterCount: Int {
        text.count
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    func clear() {
        text = ""
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(self.text, forKey: Self.storageKey)
            self.lastSavedAt = Date()
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
}
