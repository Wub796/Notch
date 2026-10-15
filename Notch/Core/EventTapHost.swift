import ApplicationServices
import Foundation

/// Runs one `CGEventTap` on a private thread and keeps it armed.
///
/// The system gives a tap callback a deadline and disables a tap that misses
/// it — at which point every volume and brightness key falls straight through
/// to the system HUD, the opposite of what a media-key interceptor is for. A
/// tap served from the main run loop is served late precisely when the app is
/// busy, which is a normal state here: an open notch runs a 30Hz meter, a 10Hz
/// progress tick, SwiftUI redraws and animation. So the source goes on a
/// private run loop with its own thread, where nothing the app does to the main
/// thread can delay the callback.
///
/// Being disabled is recoverable two ways, and this type owns both: the system
/// sends a disable event, which is re-armed on the tap's own thread, and a tap
/// that will not come back has to be destroyed and rebuilt, because `tapEnable`
/// on an invalidated port reports success and changes nothing. `isEnabled` is
/// the honest answer to "is this tap still working", which the owner polices —
/// a tap that exists is not the same as a tap that is receiving.
///
/// Split out of `MediaKeyInterceptor` so that file is the key policy and the
/// actions, not the run-loop plumbing as well.
final class EventTapHost {
    /// Called on the tap thread. Return nil to swallow the event, or the event
    /// untouched to pass it on.
    typealias Handler = (CGEvent) -> Unmanaged<CGEvent>?

    private let handler: Handler

    /// Guards the four fields below: written on the main thread, read from the
    /// tap thread and from `teardown`. Every use is a field read or write; no
    /// lock is held across a dispatch or a blocking call.
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var armedAt = Date.distantPast

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Whether a tap exists *and* the system still has it enabled.
    var isEnabled: Bool {
        lock.lock()
        let tap = eventTap
        lock.unlock()
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    var hasTap: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventTap != nil
    }

    /// How long since the tap was created. A tap that has only just been built
    /// is not necessarily enabled for the first moment, because the run loop
    /// serving it has not started.
    var ageSinceArmed: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(armedAt)
    }

    /// Creates the tap and starts serving it. False when the system refuses to
    /// create one — missing Accessibility trust is the usual reason.
    @discardableResult
    func start(eventsOfInterest mask: CGEventMask) -> Bool {
        guard !hasTap else { return true }

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, context in
                guard let context else { return Unmanaged.passRetained(event) }
                let host = Unmanaged<EventTapHost>.fromOpaque(context).takeUnretainedValue()
                return host.handle(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let tap else { return false }
        lock.lock()
        eventTap = tap
        armedAt = Date()
        lock.unlock()

        serve(tap)
        return true
    }

    /// Re-arms a tap the system switched off. False when it would not take,
    /// which means the port is dead and has to be replaced.
    @discardableResult
    func rearm() -> Bool {
        lock.lock()
        let tap = eventTap
        lock.unlock()
        guard let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Takes the tap down: no more events, no thread left running.
    func stop() {
        lock.lock()
        let tap = eventTap
        let loop = tapRunLoop
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        armedAt = .distantPast
        lock.unlock()

        // Disable first so no more events are handed to a thread that is on its
        // way out, then stop the loop the source lives on. Both are safe from
        // another thread; the source itself is removed by the tap thread once
        // the loop it is scheduled on returns.
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let loop {
            CFRunLoopStop(loop)
            CFRunLoopWakeUp(loop)
        }
    }

    deinit { stop() }

    // MARK: - Tap thread

    /// Runs the tap's source on a private run loop.
    private func serve(_ tap: CFMachPort) {
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return
        }
        lock.lock()
        runLoopSource = source
        lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let loop = CFRunLoopGetCurrent()
            self?.lock.lock()
            self?.tapRunLoop = loop
            self?.lock.unlock()
            ready.signal()

            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            // Runs until `stop()` stops it. Whatever it returns for, the source
            // is taken off the loop on the thread that owns it.
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        thread.name = "com.notchapp.Notch.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        // Waits only for the loop to be published, which is the thread's first
        // action and cannot block. It matters because `stop()` reaches the loop
        // through that handle: a rebuild that immediately followed a start
        // would otherwise leave a thread running a loop nothing can reach. The
        // timeout is a safety net, not a deadline — a missed arm is picked up by
        // the owner's health check.
        _ = ready.wait(timeout: .now() + 2)
    }

    /// Dispatches one event to the handler from the tap thread.
    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // A disabled tap (callback timeout, or user input while it was blocked)
        // has to be re-armed or the keys stop working entirely. Re-armed here,
        // on the tap's own thread: hopping this to main would delay the one part
        // of the recovery that matters by exactly the load that disabled the tap
        // in the first place.
        if event.type == .tapDisabledByTimeout || event.type == .tapDisabledByUserInput {
            rearm()
            return Unmanaged.passRetained(event)
        }
        return handler(event)
    }
}
