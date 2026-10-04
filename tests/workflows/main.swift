import AppKit
import Foundation

// Test-only settings; production models still compile in the full app build.
final class NotchSettings {
    static let shared = NotchSettings()
    var clipboardHistoryEnabled = true
    var clipboardMaxCapacity = 25
    var instantAirDrop = false
    var autoClearShelf = false
    var volumeHUDEnabled = false
    var liveActivitiesEnabled = true
    var screenLockActivityEnabled = true
    var sneakPeekEnabled = true
    var sneakPeekDuration = 3.5
    var focusChangeEnabled = true
    var desktopChangeEnabled = true
    var showAccessoryBattery = true
    var brightnessHUDEnabled = true
    var powerEventEnabled = true
    var lowBatteryThreshold = 20
}
enum FileCatcher { enum Source: Equatable { case download, screenshot } }
enum EyeBreakManager { static let breakDuration: TimeInterval = 20 }

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    print("PASS \(message)")
}
func wait(_ seconds: TimeInterval = 0.05) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

let suite = "NotchWorkflowTests-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let notes = NotesManager(defaults: defaults)
expect(!notes.hasUnsavedChanges, "Loaded notes are not dirty")
notes.text = "One last edit"
expect(notes.hasUnsavedChanges && defaults.string(forKey: "scratchpadText") == nil, "Typing marks pending save before debounce")
notes.flush()
expect(!notes.hasUnsavedChanges && NotesManager(defaults: defaults).text == "One last edit", "Lifecycle flush preserves an immediate final edit")
let saved = notes.lastSavedAt
notes.flush()
expect(notes.lastSavedAt == saved, "Repeated flush does not pretend another save happened")
notes.text += " with more words"
expect(notes.hasUnsavedChanges, "New edit invalidates old Saved status")
wait(0.7)
expect(!notes.hasUnsavedChanges && NotesManager(defaults: defaults).text == notes.text, "Debounced autosave writes the latest text")
notes.clear()
expect(notes.canUndoClear && NotesManager(defaults: defaults).text.isEmpty, "Clear saves immediately and offers undo")
notes.undoClear()
expect(notes.text == "One last edit with more words" && !notes.canUndoClear, "Undo Clear restores the complete note")
notes.clear()
notes.text = "New note"
notes.undoClear()
expect(notes.text == "New note" && !notes.canUndoClear, "Undo Clear never overwrites newer typing")
notes.flush()

let pasteboard = NSPasteboard.withUniqueName()
defer { pasteboard.releaseGlobally() }
var enabled = true
var capacity = 2
let clipboard = ClipboardManager(pasteboard: pasteboard, defaults: defaults,
                                 isEnabled: { enabled }, capacity: { capacity })
func copy(_ text: String, concealed: Bool = false) {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    if concealed { pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) }
}
func collect(_ text: String) {
    copy(text)
    wait(1.08)
}
copy("before recording")
clipboard.start()
wait(1.08)
expect(clipboard.entries.isEmpty, "Recording does not ingest pre-existing clipboard content")
collect("Pinned")
let originalID = clipboard.entries[0].id
clipboard.togglePin(clipboard.entries[0])
collect("Recent one")
collect("Recent two")
expect(clipboard.entries.count == 3 && clipboard.entries[0].isPinned, "Pins do not consume the recent-copy budget")
collect("Pinned")
expect(clipboard.entries[0].id == originalID && clipboard.entries[0].isPinned, "Re-copy preserves row identity and pin ordering")
let persisted = ClipboardManager(pasteboard: pasteboard, defaults: defaults)
expect(persisted.entries.count == 1 && persisted.entries[0].copiedAt == clipboard.entries[0].copiedAt,
       "Re-copy persists the actual updated pin timestamp, never recent text")
capacity = 1
clipboard.trimToCapacity()
expect(clipboard.entries.count == 2 && clipboard.entries[1].text == "Recent two", "Capacity reduction immediately removes oldest recent copies only")
copy("password", concealed: true)
wait(1.08)
expect(!clipboard.entries.contains(where: { $0.text == "password" }), "Concealed clipboard content is never recorded")
clipboard.stop()
enabled = false
copy("while disabled")
enabled = true
clipboard.start()
wait(1.08)
expect(!clipboard.entries.contains(where: { $0.text == "while disabled" }), "Re-enabling never collects a copy made while history was disabled")
clipboard.copyBack(clipboard.entries[0])
collect("immediate external copy")
expect(clipboard.entries.contains(where: { $0.text == "immediate external copy" }), "An external copy after Copy Back is not swallowed")
clipboard.togglePin(clipboard.entries[0])
expect(clipboard.entries.filter { !$0.isPinned }.count == 1, "Unpinning also respects the recent-history capacity")
clipboard.clearUnpinned()
expect(clipboard.entries.isEmpty, "Clear Unpinned removes recent entries")
clipboard.stop()

let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchShelfTests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let file = folder.appendingPathComponent("sample.txt")
try Data("Shelf fixture".utf8).write(to: file)
let shelf = ShelfController()
shelf.add([file, file, folder.appendingPathComponent("./sample.txt"), URL(string: "https://example.com")!])
expect(shelf.items.count == 1 && shelf.items[0].url == file, "Shelf deduplicates one batch and accepts only local files")
shelf.add([file])
expect(shelf.items.count == 1, "Later drops cannot duplicate an existing shelf file")
shelf.clear()
expect(FileManager.default.fileExists(atPath: file.path), "Clearing shelf never deletes the source file")

func volumeMonitoring(_ manager: LiveActivityManager) -> Bool {
    let source = Mirror(reflecting: manager).children.first { $0.label == "volumeMonitor" }!.value
    return Mirror(reflecting: source).children.first { $0.label == "isRunning" }!.value as! Bool
}
let activities = LiveActivityManager()
activities.start()
expect(!volumeMonitoring(activities), "Launch with HUD disabled does not attach volume listeners")
NotchSettings.shared.volumeHUDEnabled = true
activities.syncVolumeMonitoring()
expect(volumeMonitoring(activities), "Re-enabling HUD attaches real CoreAudio listeners without relaunch")
activities.showVolume(level: 0.5, muted: false)
expect(activities.transient?.kind == "volume", "Enabled volume HUD publishes its activity")
NotchSettings.shared.volumeHUDEnabled = false
activities.syncVolumeMonitoring()
expect(!volumeMonitoring(activities) && activities.transient == nil, "Disabling HUD detaches listeners and immediately clears its activity")
activities.stop()
print("All workflow regression checks passed.")
