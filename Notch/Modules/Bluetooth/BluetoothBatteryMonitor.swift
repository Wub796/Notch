import AppKit
import Foundation
import IOKit
import Observation

/// Battery levels for connected Apple accessories (AirPods, Magic Mouse,
/// Magic Keyboard, Trackpad), read by walking the IO Registry for entries
/// that publish battery percentages — the same data `ioreg -k BatteryPercent`
/// surfaces, with no extra permissions.
@Observable
final class BluetoothBatteryMonitor {
    struct Device: Identifiable, Equatable {
        let id: String
        let name: String
        /// Single combined level, or nil when the device reports per-bud.
        let percent: Int?
        let leftPercent: Int?
        let rightPercent: Int?
        let casePercent: Int?

        var symbolName: String {
            let lowered = name.lowercased()
            if lowered.contains("airpods max") { return "airpodsmax" }
            if lowered.contains("airpods pro") { return "airpodspro" }
            if lowered.contains("airpod") { return "airpods" }
            if lowered.contains("beats") || lowered.contains("headphone") {
                return "headphones"
            }
            if lowered.contains("mouse") { return "magicmouse" }
            if lowered.contains("trackpad") { return "magictrackpad" }
            if lowered.contains("keyboard") { return "keyboard" }
            return "antenna.radiowaves.left.and.right"
        }

        /// Worst level across all reported cells — what to badge.
        var lowestPercent: Int? {
            [percent, leftPercent, rightPercent, casePercent].compactMap { $0 }.min()
        }
    }

    private(set) var devices: [Device] = []

    private var timer: Timer?

    /// Sampled only while the notch is open — accessory levels change slowly
    /// and the registry walk is not free.
    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.scanRegistry()
            DispatchQueue.main.async {
                self?.devices = found
            }
        }
    }

    // MARK: - IO Registry walk

    private static func scanRegistry() -> [Device] {
        var iterator = io_iterator_t()
        let status = IORegistryCreateIterator(
            kIOMainPortDefault,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        )
        guard status == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var found: [Device] = []
        var seen = Set<String>()

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }

            var propertiesRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                entry, &propertiesRef, kCFAllocatorDefault, 0
            ) == KERN_SUCCESS,
                let properties = propertiesRef?.takeRetainedValue() as? [String: Any]
            else { continue }

            let combined = intValue(properties["BatteryPercentCombined"])
                ?? intValue(properties["BatteryPercent"])
            let left = intValue(properties["BatteryPercentLeft"])
            let right = intValue(properties["BatteryPercentRight"])
            let caseLevel = intValue(properties["BatteryPercentCase"])

            // Anything with no battery data, or a zeroed placeholder, is skipped.
            guard combined != nil || left != nil || right != nil || caseLevel != nil else {
                continue
            }

            let name = (properties["Product"] as? String)
                ?? (properties["BD_NAME"] as? String)
                ?? (properties["DeviceName"] as? String)
                ?? "Accessory"
            guard !seen.contains(name) else { continue }
            seen.insert(name)

            found.append(Device(
                id: name,
                name: name,
                percent: combined,
                leftPercent: left,
                rightPercent: right,
                casePercent: caseLevel
            ))
        }

        return found.sorted { $0.name < $1.name }
    }

    private static func intValue(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber else { return nil }
        let value = number.intValue
        return (1 ... 100).contains(value) ? value : nil
    }
}
