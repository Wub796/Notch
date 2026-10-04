import CoreData
import Foundation
import ObjectiveC

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    print("PASS \(message)")
}

func wait(_ seconds: TimeInterval = 0.3) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

expect(ClockTimerStore.isAccessDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)),
       "FileHandle permission error is classified as Full Disk Access required")
expect(ClockTimerStore.isAccessDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
       userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])),
       "Nested macOS privacy denial is classified correctly")

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("NotchTimerTests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let preferences = temporary.appendingPathComponent("timers.plist")
let database = temporary.appendingPathComponent("local.sqlite")
let now = Date()

func entry(_ id: String, state: Int = 2, duration: Double = 120, modified: Date? = Date()) -> [String: Any] {
    var raw: [String: Any] = ["MTTimerID": id, "MTTimerState": state, "MTTimerDuration": duration,
                              "MTTimerFireTime": ["$MTTimerTimeInterval": ["MTTimerTimeInterval": duration]]]
    if let modified { raw["MTTimerLastModifiedDate"] = modified }
    return ["$MTTimer": raw]
}
func writePreferences(_ entries: [[String: Any]], migrated: Bool = false) throws {
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["MTTimerStorageMigratedToCoreData": migrated, "MTTimers": ["MTTimers": entries]],
        format: .binary, options: 0
    )
    try data.write(to: preferences, options: .atomic)
}

try writePreferences([entry("running", modified: now.addingTimeInterval(-20)), entry("stopped", state: 1),
                      entry("unanchored", modified: nil), entry("invalid", duration: .infinity)])
let legacy = ClockTimerStore(databaseURL: database, preferencesURL: preferences)
let readings = try legacy.read(now: now)
expect(readings.count == 1, "Legacy parser excludes inactive, unanchored and non-finite timers")
expect(abs(readings[0].remaining - 100) < 0.01, "Legacy countdown uses the original deadline")
try writePreferences([entry("paused", state: 3)])
let pausedLegacy = try legacy.read()
expect(pausedLegacy[0].isPaused, "Legacy paused state is preserved")

// Real installed model and decoder, against a disposable store we own.
let bundle = Bundle(path: "/System/Library/PrivateFrameworks/MobileTimer.framework")!
expect(bundle.load(), "Installed Clock framework loads")
let model = NSManagedObjectModel(contentsOf: bundle.url(forResource: "MobileTimer", withExtension: "momd")!)!
let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
let persistentStore = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: database)
let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
context.persistentStoreCoordinator = coordinator
let object = NSEntityDescription.insertNewObject(forEntityName: "MTCDTimer", into: context)
let identifier = UUID()
object.setValue(identifier, forKey: "mtid")
object.setValue(120.0, forKey: "duration")
object.setValue(now, forKey: "lastModifiedDate")
object.setValue(3, forKey: "state")
object.setValue("Tea", forKey: "title")

let timeClass: AnyClass = NSClassFromString("MTTimerTimeInterval")!
let timeObject = (timeClass as AnyObject).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue() as! NSObject
let selector = NSSelectorFromString("initWithTimeInterval:")
let method = class_getInstanceMethod(timeClass, selector)!
typealias IntervalInitializer = @convention(c) (AnyObject, Selector, Double) -> AnyObject
let initialize = unsafeBitCast(method_getImplementation(method), to: IntervalInitializer.self)
let time = initialize(timeObject, selector, 87)
object.setValue(try NSKeyedArchiver.archivedData(withRootObject: time, requiringSecureCoding: true), forKey: "fireTime")
try context.save()
try writePreferences([entry("stale")], migrated: true)
let databaseBefore = try Data(contentsOf: database)
let walURL = URL(fileURLWithPath: database.path + "-wal")
let walBefore = try Data(contentsOf: walURL)
let live = try legacy.read()
let databaseAfter = try Data(contentsOf: database)
let walAfter = try Data(contentsOf: walURL)
expect(databaseBefore == databaseAfter && walBefore == walAfter, "Read-only Clock query does not alter the database or WAL")
expect(live.count == 1 && live[0].identifier.lowercased() == identifier.uuidString.lowercased(), "Migrated store replaces stale preferences")
expect(live[0].isPaused && abs(live[0].remaining - 87) < 0.01, "Installed decoder preserves actual paused remaining time")
expect(live[0].title == "Tea", "Clock timer title is decoded")

let monitor = ClockTimerMonitor(store: legacy)
monitor.start()
wait(0.7)
expect(monitor.access == .ready && monitor.snapshot?.isPaused == true, "Monitor publishes migrated Clock timer")
// Ask the installed timer model to construct a resume, not a guessed deadline.
let timerClass: AnyClass = NSClassFromString("MTTimer")!
let allocated = (timerClass as AnyObject).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue() as! NSObject
let pausedTimer = allocated.perform(NSSelectorFromString("initWithMTCDTimer:"), with: object)!.takeRetainedValue() as! NSObject
let resumeSelector = NSSelectorFromString("timerByUpdatingWithState:")
typealias StateUpdate = @convention(c) (AnyObject, Selector, UInt) -> AnyObject
let resume = unsafeBitCast(method_getImplementation(class_getInstanceMethod(timerClass, resumeSelector)!), to: StateUpdate.self)
let resumed = resume(pausedTimer, resumeSelector, 2) as! NSObject
object.setValue(2, forKey: "state")
object.setValue(try NSKeyedArchiver.archivedData(withRootObject: resumed.value(forKey: "fireTime")!, requiringSecureCoding: true), forKey: "fireTime")
try context.save()
wait(0.7)
expect(monitor.snapshot?.isPaused == false && (monitor.snapshot?.remaining ?? 0) > 85,
       "Database resume uses Clock's actual deadline, not lastModified plus duration")
let beforeTick = monitor.snapshot!.remaining
wait(0.4)
expect(monitor.snapshot!.remaining < beforeTick, "Resumed Clock countdown advances between store writes")
object.setValue(1, forKey: "state")
try context.save()
wait(0.7)
expect(monitor.snapshot == nil, "WAL write removes cancelled timer without polling")
monitor.stop()
try coordinator.remove(persistentStore)

let fallbackDatabase = temporary.appendingPathComponent("missing.sqlite")
let fallback = ClockTimerStore(databaseURL: fallbackDatabase, preferencesURL: preferences)
try writePreferences([entry("new", duration: 0.5)])
let fallbackMonitor = ClockTimerMonitor(store: fallback)
fallbackMonitor.start()
wait(0.2)
expect(fallbackMonitor.snapshot != nil, "Legacy timer appears on launch")
wait(0.7)
expect(fallbackMonitor.snapshot == nil, "Expired timer clears without a daemon write")
try writePreferences([entry("old", duration: 40), entry("expired", duration: 1, modified: Date().addingTimeInterval(-2))])
wait(0.4)
expect(fallbackMonitor.snapshot?.identifier == "old", "Expired newest timer cannot hide an older active timer")
try writePreferences([entry("paused", state: 3, duration: 50)])
wait(0.4)
let held = fallbackMonitor.snapshot?.remaining
wait(0.4)
expect(fallbackMonitor.snapshot?.isPaused == true && fallbackMonitor.snapshot?.remaining == held, "Paused monitor holds remaining time")
fallbackMonitor.stop()
try writePreferences([entry("after-stop")])
wait(0.3)
expect(fallbackMonitor.snapshot == nil, "Stopped monitor ignores later file changes")

let failureMonitor = ClockTimerMonitor(store: fallback, reader: { throw ClockTimerStore.Failure.fullDiskAccessRequired })
failureMonitor.start()
wait()
expect(failureMonitor.access == .fullDiskAccessRequired && failureMonitor.snapshot == nil, "Protected storage reports access requirement, never stale timers")
failureMonitor.stop()

let local = TimerManager()
local.togglePause()
expect(!local.isRunning, "Pause on idle local timer cannot create a phantom activity")
local.start(duration: .infinity)
expect(!local.isRunning, "Local timer rejects infinite duration")
local.start(duration: 20)
local.togglePause()
let paused = local.remaining
wait()
expect(local.remaining == paused, "Local countdown stays frozen while paused")
local.togglePause()
expect(!local.isPaused && local.isRunning, "Local timer resumes")
local.cancel()
expect(!local.isRunning && local.pausedRemaining == 0, "Local cancel resets all countdown state")
expect(TimerManager.timeString(.nan) == "0:00" && TimerManager.timeString(-2) == "0:00", "Formatting safely handles invalid timer values")
expect(TimerManager.timeString(60.1) == "1:01", "Countdown display rounds up")
print("All timer regression checks passed.")
