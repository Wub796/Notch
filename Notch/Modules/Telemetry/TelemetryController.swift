import Foundation
import IOKit
import Observation

/// Live hardware telemetry: CPU load and memory pressure from Mach host
/// statistics, battery wattage/health from the IOKit smart-battery service.
/// Sampling runs on a timer that exists only while the notch is expanded.
@Observable
final class TelemetryController {
    // 0...1 fractions for the circular gauges.
    private(set) var cpuUsage: Double = 0
    private(set) var memoryPressure: Double = 0

    /// Rolling CPU samples for the sparkline (most recent last).
    private(set) var cpuHistory: [Double] = []
    static let historyLength = 40

    private(set) var hasBattery = false
    private(set) var batteryPercent: Double = 0
    private(set) var batteryWatts: Double = 0
    private(set) var batteryHealth: Double = 0
    private(set) var isCharging = false

    private(set) var downloadBytesPerSecond: Double = 0
    private(set) var uploadBytesPerSecond: Double = 0

    private var timer: Timer?
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNetworkSample: (received: UInt64, sent: UInt64, at: Date)?
    private let sampleQueue = DispatchQueue(label: "com.notch.telemetry", qos: .utility)

    func start() {
        guard timer == nil else { return }
        sampleQueue.async { [weak self] in self?.sample() }
        let interval = max(NotchSettings.shared.telemetryInterval, 0.5)
        timer = Timer.scheduledRepeating(every: interval) { [weak self] in
            self?.sampleQueue.async { self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousTicks = nil
        previousNetworkSample = nil
    }

    private func sample() {
        let cpu = sampleCPURaw()
        let mem = sampleMemoryRaw()
        let bat = sampleBatteryRaw()
        let net = sampleNetworkRaw()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyCPU(cpu)
            self.applyMemory(mem)
            self.applyBattery(bat)
            self.applyNetwork(net)
        }
    }

    // MARK: - CPU (host_statistics / HOST_CPU_LOAD_INFO)

    private func sampleCPURaw() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = (
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return nil }

        let user = Double(ticks.user &- previous.user)
        let system = Double(ticks.system &- previous.system)
        let idle = Double(ticks.idle &- previous.idle)
        let nice = Double(ticks.nice &- previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }

        return min(max((user + system + nice) / total, 0), 1)
    }

    private func applyCPU(_ value: Double?) {
        guard let value else { return }
        cpuUsage = value
        cpuHistory.append(value)
        if cpuHistory.count > Self.historyLength {
            cpuHistory.removeFirst(cpuHistory.count - Self.historyLength)
        }
    }

    // MARK: - Memory (host_statistics64 / HOST_VM_INFO64)

    private func sampleMemoryRaw() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = Double(vm_kernel_page_size)
        let usedBytes = (
            Double(stats.active_count)
            + Double(stats.wire_count)
            + Double(stats.compressor_page_count)
        ) * pageSize
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else { return nil }

        return min(max(usedBytes / totalBytes, 0), 1)
    }

    private func applyMemory(_ value: Double?) {
        guard let value else { return }
        memoryPressure = value
    }

    // MARK: - Battery (IOKit AppleSmartBattery)

    private struct BatteryReading {
        var hasBattery: Bool
        var percent: Double
        var watts: Double
        var health: Double
        var isCharging: Bool
    }

    private func sampleBatteryRaw() -> BatteryReading {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else {
            return BatteryReading(hasBattery: false, percent: 0, watts: 0, health: 0, isCharging: false)
        }
        defer { IOObjectRelease(service) }

        var propertiesRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let properties = propertiesRef?.takeRetainedValue() as? [String: Any]
        else {
            return BatteryReading(hasBattery: false, percent: 0, watts: 0, health: 0, isCharging: false)
        }

        let currentCapacity = properties["CurrentCapacity"] as? Double ?? 0
        let maxCapacity = properties["MaxCapacity"] as? Double ?? 0
        let percent = maxCapacity > 0 ? min(max(currentCapacity / maxCapacity, 0), 1) : 0

        let amperage = properties["Amperage"] as? Double ?? 0
        let voltage = properties["Voltage"] as? Double ?? 0
        let watts = (amperage / 1000) * (voltage / 1000)

        let rawMax = properties["AppleRawMaxCapacity"] as? Double
            ?? properties["NominalChargeCapacity"] as? Double
            ?? 0
        let designCapacity = properties["DesignCapacity"] as? Double ?? 0
        let health = (designCapacity > 0 && rawMax > 0) ? min(max(rawMax / designCapacity, 0), 1) : 0

        let charging = properties["IsCharging"] as? Bool ?? false

        return BatteryReading(
            hasBattery: true, percent: percent, watts: watts, health: health, isCharging: charging
        )
    }

    private func applyBattery(_ reading: BatteryReading) {
        hasBattery = reading.hasBattery
        batteryPercent = reading.percent
        batteryWatts = reading.watts
        batteryHealth = reading.health
        isCharging = reading.isCharging
    }

    // MARK: - Network throughput (getifaddrs deltas over en* interfaces)

    private func sampleNetworkRaw() -> (download: Double, upload: Double)? {
        guard let totals = Self.interfaceByteCounts() else { return nil }
        let now = Date()
        defer { previousNetworkSample = (totals.received, totals.sent, now) }

        guard let previous = previousNetworkSample else { return nil }
        let dt = now.timeIntervalSince(previous.at)
        guard dt > 0 else { return nil }

        let download = totals.received >= previous.received
            ? Double(totals.received - previous.received) / dt
            : 0
        let upload = totals.sent >= previous.sent
            ? Double(totals.sent - previous.sent) / dt
            : 0
        return (download, upload)
    }

    private func applyNetwork(_ values: (download: Double, upload: Double)?) {
        guard let values else { return }
        downloadBytesPerSecond = values.download
        uploadBytesPerSecond = values.upload
    }

    private static func interfaceByteCounts() -> (received: UInt64, sent: UInt64)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0

        var cursor = addresses
        while let current = cursor {
            let interface = current.pointee
            cursor = interface.ifa_next

            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = interface.ifa_data,
                  String(cString: interface.ifa_name).hasPrefix("en")
            else { continue }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(data.ifi_ibytes)
            sent += UInt64(data.ifi_obytes)
        }

        return (received, sent)
    }
}
