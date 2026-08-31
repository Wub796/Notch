import AppKit
import IOBluetooth

/// Paired-but-disconnected Bluetooth audio devices, listed on the Audio
/// screen so they can be connected without opening System Settings
/// (FineTune-style). Connected devices already appear in CoreAudio, so only
/// the not-connected ones are offered here.
///
/// All IOBluetooth interaction is isolated in this file and serialized on a
/// dedicated queue: IOBluetooth performs Mach-port IPC and is not safe
/// against concurrent calls.
enum BluetoothAudioDevices {
    struct PairedDevice: Identifiable, Equatable {
        /// MAC address — stable identity across sessions.
        let id: String
        let name: String
        let symbolName: String
    }

    private static let queue = DispatchQueue(label: "com.notch.bluetooth")

    /// The initializer is failable; these well-known UUIDs always construct.
    private static let a2dpSinkUUID = IOBluetoothSDPUUID(uuid16: 0x110B)!
    private static let hfpUUID = IOBluetoothSDPUUID(uuid16: 0x111E)!

    /// Paired audio devices that are not connected, sorted by name.
    static func pairedAudioDevices(completion: @escaping ([PairedDevice]) -> Void) {
        queue.async {
            let devices = list()
            DispatchQueue.main.async { completion(devices) }
        }
    }

    /// Opens the connection to a paired device. Connection completes
    /// asynchronously; success is reported by the device appearing in
    /// CoreAudio, so the caller just clears the row on the next refresh.
    static func connect(_ device: PairedDevice) {
        queue.async {
            guard let btDevice = IOBluetoothDevice(addressString: device.id) else { return }
            _ = btDevice.openConnection()
        }
    }

    private static func list() -> [PairedDevice] {
        guard let all = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        var result: [PairedDevice] = []
        for device in all {
            guard !device.isConnected(),
                  let mac = device.addressString, !mac.isEmpty
            else { continue }

            let hasA2DP = device.getServiceRecord(for: a2dpSinkUUID) != nil
            let hasHFP = device.getServiceRecord(for: hfpUUID) != nil
            guard hasA2DP || hasHFP else { continue }

            let name = device.name ?? mac
            result.append(
                PairedDevice(id: mac, name: name, symbolName: Self.symbol(for: name))
            )
        }

        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func symbol(for name: String) -> String {
        if name.contains("AirPods Pro") { return "airpodspro" }
        if name.contains("AirPods") { return "airpods" }
        if name.contains("Beats") { return "beats.headphones" }
        if name.lowercased().contains("headphone") { return "headphones" }
        if name.lowercased().contains("speaker") { return "hifispeaker" }
        return "waveform"
    }
}
