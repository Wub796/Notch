import Foundation
import Observation

@Observable
final class ClockTimerMonitor {
    static let shared = ClockTimerMonitor()

    struct Snapshot: Equatable {
        let identifier: String
        let title: String
        let duration: TimeInterval
        let remaining: TimeInterval
        let isPaused: Bool

        var progress: Double {
            guard duration > 0 else { return 0 }
            return max(0, min(1, 1 - remaining / duration))
        }
    }

    enum Access: Equatable {
        case checking, ready, fullDiskAccessRequired, unavailable, incompatibleStore

        var detail: String {
            switch self {
            case .checking: "Checking Clock timer access…"
            case .ready: "Connected to Clock. Siri and Clock timers appear automatically."
            case .fullDiskAccessRequired: "Allow Notch in Full Disk Access, then quit and reopen Notch. Clock's current timer database is protected by macOS."
            case .unavailable: "Clock's timer store is unavailable. Open Clock, set a timer, then check again."
            case .incompatibleStore: "This macOS timer store could not be read. Notch timers still work."
            }
        }
    }

    private(set) var snapshot: Snapshot?
    private(set) var access: Access = .checking
    var onStateChange: (() -> Void)?

    private let store: ClockTimerStore
    private let read: () throws -> [ClockTimerStore.Reading]
    private let queue = DispatchQueue(label: "com.notchapp.clock-timers", qos: .utility)
    private var monitors: [DispatchSourceFileSystemObject] = []
    private var reloadWork: DispatchWorkItem?
    private var tickTimer: Timer?
    private var deadline: Date?
    private var running = false
    private var generation = 0

    init(store: ClockTimerStore = ClockTimerStore(), reader: (() throws -> [ClockTimerStore.Reading])? = nil) {
        self.store = store
        read = reader ?? { try store.read() }
    }

    func start() {
        guard !running else { return }
        running = true
        reload()
    }

    func stop() {
        running = false
        generation += 1
        reloadWork?.cancel()
        reloadWork = nil
        tickTimer?.invalidate()
        tickTimer = nil
        stopWatching()
        deadline = nil
        publish(nil)
    }

    deinit {
        tickTimer?.invalidate()
        reloadWork?.cancel()
        monitors.forEach { $0.cancel() }
    }

    /// Disk access and Core Data never run on the UI thread. A generation
    /// prevents an earlier read (or one finishing after stop) from winning.
    func reload() {
        guard running else { return }
        generation += 1
        let request = generation
        let reader = read
        queue.async { [weak self] in
            let result = Result { try reader() }
            let sampledAt = Date()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.generation == request else { return }
                self.accept(result, sampledAt: sampledAt)
                self.watchStore()
            }
        }
    }

    private func accept(_ result: Result<[ClockTimerStore.Reading], Error>, sampledAt: Date) {
        switch result {
        case let .success(timers):
            access = .ready
            // Skip expired rows before choosing, so the next timer returns
            // even if the daemon has not removed the just-finished one yet.
            let timer = timers.filter { $0.remaining > 0 }
                .max { $0.modified < $1.modified }
            guard let timer else {
                deadline = nil
                publish(nil)
                scheduleTick()
                return
            }
            deadline = timer.isPaused ? nil : sampledAt.addingTimeInterval(timer.remaining)
            publish(Snapshot(identifier: timer.identifier, title: timer.title,
                             duration: max(timer.duration, timer.remaining), remaining: timer.remaining,
                             isPaused: timer.isPaused))
            scheduleTick()
        case let .failure(error):
            switch error as? ClockTimerStore.Failure {
            case .fullDiskAccessRequired: access = .fullDiskAccessRequired
            case .incompatibleStore: access = .incompatibleStore
            default: access = .unavailable
            }
            deadline = nil
            publish(nil)
            scheduleTick()
        }
    }

    private func publish(_ next: Snapshot?) {
        guard snapshot != next else { return }
        let layoutChanged = (snapshot == nil) != (next == nil)
            || snapshot?.isPaused != next?.isPaused
        snapshot = next
        if layoutChanged { onStateChange?() }
    }

    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = nil
        guard deadline != nil else { return }
        tickTimer = Timer.scheduledRepeating(every: 0.25) { [weak self] in
            guard let self, let deadline = self.deadline, let snapshot = self.snapshot else { return }
            let remaining = max(0, deadline.timeIntervalSinceNow)
            if remaining <= 0 {
                self.deadline = nil
                self.publish(nil)
                self.scheduleTick()
                self.reload() // Restore an older timer without waiting for a file write.
            } else {
                self.publish(Snapshot(identifier: snapshot.identifier, title: snapshot.title,
                                      duration: snapshot.duration, remaining: remaining, isPaused: false))
            }
        }
    }

    // Core Data commits go into the WAL, not necessarily the database itself.
    // Watch the directory too: checkpoints replace/delete the WAL and writes
    // to cfprefsd replace the plist's inode. No idle polling is needed.
    private func watchStore() {
        stopWatching()
        let database = store.databaseURL.path
        let paths = Set([
            database, database + "-wal", store.databaseURL.deletingLastPathComponent().path,
            store.preferencesURL.path, store.preferencesURL.deletingLastPathComponent().path,
        ])
        for path in paths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete], queue: .main
            )
            source.setEventHandler { [weak self] in self?.scheduleReload() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            monitors.append(source)
        }
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func stopWatching() {
        monitors.forEach { $0.setEventHandler {}; $0.cancel() }
        monitors.removeAll()
    }
}
