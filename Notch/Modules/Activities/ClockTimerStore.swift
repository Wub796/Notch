import CoreData
import Foundation

/// Clock's preferences become a stale migration snapshot on newer macOS.
/// Its XPC timer server is entitlement-gated; the local store is readable only
/// with the user's Full Disk Access grant. Never open this store for writing.
struct ClockTimerStore {
    struct Reading {
        let identifier: String
        let title: String
        let duration: TimeInterval
        let remaining: TimeInterval
        let isPaused: Bool
        let modified: Date
    }

    enum Failure: Error {
        case fullDiskAccessRequired
        case unavailable
        case incompatibleStore
    }

    static let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.mobiletimerd/local.sqlite")
    static let preferencesURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.apple.mobiletimerd.plist")

    let databaseURL: URL
    let preferencesURL: URL

    init(databaseURL: URL = Self.databaseURL, preferencesURL: URL = Self.preferencesURL) {
        self.databaseURL = databaseURL
        self.preferencesURL = preferencesURL
    }

    func read(now: Date = Date()) throws -> [Reading] {
        let preferences = (try? Data(contentsOf: preferencesURL)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        let migrated = preferences?["MTTimerStorageMigratedToCoreData"] as? Bool == true
        // Do not fall back to old timers when the live store is protected.
        if migrated || FileManager.default.fileExists(atPath: databaseURL.path) {
            return try readDatabase()
        }
        guard let preferences else { throw Failure.unavailable }
        return Self.legacyReadings(preferences, now: now)
    }

    private func readDatabase() throws -> [Reading] {
        do {
            let handle = try FileHandle(forReadingFrom: databaseURL)
            try handle.close()
        } catch {
            if Self.isAccessDenied(error as NSError) {
                throw Failure.fullDiskAccessRequired
            }
            throw Failure.unavailable
        }

        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/MobileTimer.framework"),
              bundle.load(),
              let modelURL = bundle.url(forResource: "MobileTimer", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL),
              let timerClass = NSClassFromString("MTTimer") as? NSObject.Type,
              model.entitiesByName["MTCDTimer"] != nil
        else { throw Failure.incompatibleStore }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: databaseURL,
            options: [NSReadOnlyPersistentStoreOption: true,
                      NSMigratePersistentStoresAutomaticallyOption: false,
                      NSInferMappingModelAutomaticallyOption: false]
        )
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        var result: Result<[Reading], Error> = .success([])
        context.performAndWait {
            result = Result {
                let request = NSFetchRequest<NSManagedObject>(entityName: "MTCDTimer")
                request.predicate = NSPredicate(format: "state IN %@", [2, 3])
                let objects = try context.fetch(request)
                return try objects.map { object in
                    // Let the installed framework decode its own fireTime blob.
                    // Check selectors before using KVC: unknown OS schemas fail
                    // visibly rather than guessing deadlines or crashing.
                    let initializer = NSSelectorFromString("initWithMTCDTimer:")
                    let allocated = (timerClass as AnyObject).perform(NSSelectorFromString("alloc"))?
                        .takeUnretainedValue() as? NSObject
                    guard let allocated, allocated.responds(to: initializer),
                          let timer = allocated.perform(initializer, with: object)?.takeRetainedValue() as? NSObject,
                          ["timerIDString", "title", "duration", "remainingTime", "state", "lastModifiedDate"].allSatisfy({
                              timer.responds(to: NSSelectorFromString($0))
                          }),
                          let identifier = timer.value(forKey: "timerIDString") as? String,
                          let duration = timer.value(forKey: "duration") as? Double,
                          let remaining = timer.value(forKey: "remainingTime") as? Double,
                          duration.isFinite, duration > 0, remaining.isFinite
                    else { throw Failure.incompatibleStore }
                    return Reading(
                        identifier: identifier, title: timer.value(forKey: "title") as? String ?? "",
                        duration: duration, remaining: max(0, remaining),
                        isPaused: (timer.value(forKey: "state") as? Int) == 3,
                        modified: timer.value(forKey: "lastModifiedDate") as? Date ?? .distantPast
                    )
                }
            }
            context.reset()
        }
        return try result.get()
    }

    static func isAccessDenied(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileReadNoPermissionError || error.code == NSFileWriteNoPermissionError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain,
           error.code == Int(EACCES) || error.code == Int(EPERM) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isAccessDenied(underlying)
        }
        return false
    }

    static func legacyReadings(_ preferences: [String: Any], now: Date) -> [Reading] {
        let container = preferences["MTTimers"] as? [String: Any]
        let entries = container?["MTTimers"] as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            guard let raw = entry["$MTTimer"] as? [String: Any],
                  let identifier = raw["MTTimerID"] as? String, !identifier.isEmpty,
                  let state = raw["MTTimerState"] as? Int, state == 2 || state == 3,
                  let duration = raw["MTTimerDuration"] as? Double, duration.isFinite, duration > 0
            else { return nil }
            let fireTime = raw["MTTimerFireTime"] as? [String: Any]
            let interval = (fireTime?["$MTTimerTimeInterval"] as? [String: Any])?["MTTimerTimeInterval"] as? Double
            let fireDate = (fireTime?["$MTTimerTimeDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date
            let modified = raw["MTTimerLastModifiedDate"] as? Date
            let length = max(0, min(duration, interval ?? duration))
            let remaining: Double
            if state == 3 { remaining = length }
            else if let fireDate { remaining = fireDate.timeIntervalSince(now) }
            else if let modified { remaining = modified.addingTimeInterval(length).timeIntervalSince(now) }
            else { return nil } // No anchor is not a fresh countdown.
            guard remaining.isFinite else { return nil }
            return Reading(identifier: identifier, title: raw["MTTimerTitle"] as? String ?? "",
                           duration: duration, remaining: max(0, remaining), isPaused: state == 3,
                           modified: modified ?? .distantPast)
        }
    }
}
