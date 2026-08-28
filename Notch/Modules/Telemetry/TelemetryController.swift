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

    private(set) var hasBattery = false
    private(set) var batteryPercent: Double = 0
    private(set) var batteryWatts: Double = 0
    private(set) var batteryHealth: Double = 0
    private(set) var isCharging = false

    private var timer: Timer?
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousTicks = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleBattery()
    }

    // MARK: - CPU (host_statistics / HOST_CPU_LOAD_INFO)

    private func sampleCPU() {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let ticks = (
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return }

        let user = Double(ticks.user &- previous.user)
        let system = Double(ticks.system &- previous.system)
        let idle = Double(ticks.idle &- previous.idle)
        let nice = Double(ticks.nice &- previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return }

        cpuUsage = min(max((user + system + nice) / total, 0), 1)
    }

    // MARK: - Memory (host_statistics64 / HOST_VM_INFO64)

    private func sampleMemory() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = Double(vm_kernel_page_size)
        let usedBytes = (
            Double(stats.active_count)
            + Double(stats.wire_count)
            + Double(stats.compressor_page_count)
        ) * pageSize
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else { return }

        memoryPressure = min(max(usedBytes / totalBytes, 0), 1)
    }

    // MARK: - Battery (IOKit AppleSmartBattery)

    private func sampleBattery() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else {
            hasBattery = false
            return
        }
        defer { IOObjectRelease(service) }

        var propertiesRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let properties = propertiesRef?.takeRetainedValue() as? [String: Any]
        else {
            hasBattery = false
            return
        }

        hasBattery = true

        let currentCapacity = properties["CurrentCapacity"] as? Double ?? 0
        let maxCapacity = properties["MaxCapacity"] as? Double ?? 0
        if maxCapacity > 0 {
            batteryPercent = min(max(currentCapacity / maxCapacity, 0), 1)
        }

        // Instantaneous power draw: signed milliamps * millivolts.
        let amperage = properties["Amperage"] as? Double ?? 0
        let voltage = properties["Voltage"] as? Double ?? 0
        batteryWatts = (amperage / 1000) * (voltage / 1000)

        // Health: real full-charge capacity vs. factory design capacity.
        let rawMax = properties["AppleRawMaxCapacity"] as? Double
            ?? properties["NominalChargeCapacity"] as? Double
            ?? 0
        let designCapacity = properties["DesignCapacity"] as? Double ?? 0
        if designCapacity > 0, rawMax > 0 {
            batteryHealth = min(max(rawMax / designCapacity, 0), 1)
        }

        isCharging = properties["IsCharging"] as? Bool ?? false
    }
}
