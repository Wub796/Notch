import Foundation
import IOKit.ps

/// Event-driven observer of power source changes (plug/unplug, charge state)
/// via the IOKit power-source notification run loop source — no polling.
final class PowerMonitor {
    struct Snapshot: Equatable {
        let percent: Int
        let isCharging: Bool
        let onACPower: Bool
    }

    /// Called on the main queue whenever the power source changes.
    var onChange: ((Snapshot) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.publish()
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?
            .takeRetainedValue()
        else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    /// The run-loop source holds an unretained pointer back to this object,
    /// so it has to come off the run loop before the object goes away —
    /// otherwise the next power event calls through a dangling pointer.
    func stop() {
        guard let source = runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = nil
    }

    deinit {
        stop()
    }

    private func publish() {
        guard let snapshot = Self.snapshot() else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(snapshot)
        }
    }

    static func snapshot() -> Snapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = description[kIOPSMaxCapacityKey] as? Int ?? 100
            return Snapshot(
                percent: maxCapacity > 0 ? current * 100 / maxCapacity : 0,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                onACPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }
        return nil
    }
}
