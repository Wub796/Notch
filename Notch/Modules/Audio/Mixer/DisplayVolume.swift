import AppKit
import CoreAudio
import IOKit
import Observation

/// Volume for the speakers built into an external display.
///
/// Those speakers are not an audio device this app can move a slider on: their
/// level is set over DDC/CI, the control channel carried on the display's I2C
/// bus, which macOS exposes only through private IOKit symbols (`IOAVService*`).
/// They are resolved with `dlsym` rather than linked, for the same reason the
/// notch panel loads its SkyLight symbols that way — a missing symbol has to
/// mean "this display can't be controlled", never a launch failure on a macOS
/// that moved them.
///
/// Every call is guarded, every reply is checksummed, and a display that answers
/// nonsense is reported as unsupported rather than being driven with garbage.
/// The alternative for display volume would be nothing at all: Apple exposes no
/// public path to it.
@Observable
final class DisplayVolumeController {
    static let shared = DisplayVolumeController()

    /// Whether the notch offers display volume at all.
    ///
    /// On by default: the section only ever appears for a display that answers
    /// the control channel, so switching it on costs nothing on a Mac with no
    /// such display. It exists for the case that cannot be detected from here —
    /// a monitor that answers, but whose volume is better left alone.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    private let defaults = UserDefaults.standard

    private enum Key {
        static let isEnabled = "mixer.displayVolumeEnabled"
    }

    /// DDC/CI's address pair: displays answer on 0x37, and the control packet
    /// rides at 0x51 off it.
    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    /// VCP codes from the DDC/CI standard: volume, and mute.
    private static let volumeCode: UInt8 = 0x62
    private static let muteCode: UInt8 = 0x8D
    private static let replyLength = 11

    /// Which displays refused to answer, so a monitor without DDC is asked once
    /// rather than on every redraw.
    private var unsupported: Set<CGDirectDisplayID> = []
    private var lastKnownVolume: [CGDirectDisplayID: Float] = [:]

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Key.isEnabled) as? Bool ?? true
    }

    // MARK: - Private symbols

    private typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias WriteI2C = @convention(c) (CFTypeRef?, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn
    private typealias ReadI2C = @convention(c) (CFTypeRef?, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn

    private static let frameworkPath = "/System/Library/Frameworks/IOKit.framework/IOKit"

    private static let createWithService: CreateWithService? = {
        guard let handle = dlopen(frameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "IOAVServiceCreateWithService")
        else { return nil }
        return unsafeBitCast(symbol, to: CreateWithService.self)
    }()

    private static let writeI2C: WriteI2C? = {
        guard let handle = dlopen(frameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "IOAVServiceWriteI2C")
        else { return nil }
        return unsafeBitCast(symbol, to: WriteI2C.self)
    }()

    private static let readI2C: ReadI2C? = {
        guard let handle = dlopen(frameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "IOAVServiceReadI2C")
        else { return nil }
        return unsafeBitCast(symbol, to: ReadI2C.self)
    }()

    /// Whether this macOS still has the symbols at all. False on a release that
    /// removed or renamed them, in which case no display is offered DDC volume.
    var isAvailable: Bool {
        Self.createWithService != nil && Self.writeI2C != nil && Self.readI2C != nil
    }

    // MARK: - Displays

    /// An external display that answers the volume channel. Named rather than a
    /// tuple so it can be handed straight to a `ForEach` and compared.
    struct DisplayOption: Identifiable, Equatable {
        let id: CGDirectDisplayID
        let name: String
    }

    /// The external displays whose volume can be controlled — display ID and
    /// name, in the order the system reports them.
    func controllableDisplays() -> [DisplayOption] {
        guard isEnabled, isAvailable else { return [] }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }

        return ids.compactMap { id in
            // The built-in display has no DDC channel; its brightness and its
            // (fixed) volume are the system's own business.
            guard CGDisplayIsBuiltin(id) == 0, !unsupported.contains(id) else { return nil }
            guard let name = name(for: id) else { return nil }
            return DisplayOption(id: id, name: name)
        }
    }

    func name(for displayID: CGDirectDisplayID) -> String? {
        NSScreen.screens
            .first { screen in
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                return number?.uint32Value == displayID
            }?
            .localizedName
    }

    // MARK: - Volume

    /// The display's current volume, 0…1. `nil` when it does not answer.
    func volume(for displayID: CGDirectDisplayID) -> Float? {
        guard let reply = read(code: Self.volumeCode, from: displayID) else {
            unsupported.insert(displayID)
            return nil
        }
        let value = Float(reply.current) / 100
        lastKnownVolume[displayID] = value
        return value
    }

    @discardableResult
    func setVolume(_ volume: Float, for displayID: CGDirectDisplayID) -> Bool {
        let clamped = min(max(volume, 0), 1)
        let written = write(code: Self.volumeCode, value: UInt16((clamped * 100).rounded()), to: displayID)
        if written { lastKnownVolume[displayID] = clamped } else { unsupported.insert(displayID) }
        return written
    }

    @discardableResult
    func setMuted(_ isMuted: Bool, for displayID: CGDirectDisplayID) -> Bool {
        let written = write(code: Self.muteCode, value: isMuted ? 1 : 2, to: displayID)
        if !written { unsupported.insert(displayID) }
        return written
    }

    func isMuted(displayID: CGDirectDisplayID) -> Bool? {
        guard let reply = read(code: Self.muteCode, from: displayID) else { return nil }
        return reply.current == 1
    }

    // MARK: - DDC/CI packets

    /// A set request: `0x84` (set VCP), the code, its two-byte value, then the
    /// XOR of everything before it as the checksum DDC/CI requires.
    private func write(code: UInt8, value: UInt16, to displayID: CGDirectDisplayID) -> Bool {
        guard let service = service(for: displayID), let write = Self.writeI2C else { return false }
        var packet: [UInt8] = [
            0x84, 0x03, code,
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
            0,
        ]
        packet[5] = packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        let status = packet.withUnsafeMutableBufferPointer { buffer in
            write(service, Self.chipAddress, Self.dataAddress, buffer.baseAddress!, UInt32(buffer.count))
        }
        return status == kIOReturnSuccess
    }

    /// A read is two steps: ask for the code, then collect the reply. The reply
    /// is `0x6E` (the display's answer), a result byte, the code, its two-byte
    /// value, its type, and a checksum — so the value sits at offset 4.
    private func read(code: UInt8, from displayID: CGDirectDisplayID) -> (current: UInt16, maximum: UInt16)? {
        guard let service = service(for: displayID), let write = Self.writeI2C, let read = Self.readI2C else { return nil }

        var request: [UInt8] = [0x82, 0x01, code, 0]
        request[3] = request[0] ^ request[1] ^ request[2]
        let requestStatus = request.withUnsafeMutableBufferPointer { buffer in
            write(service, Self.chipAddress, Self.dataAddress, buffer.baseAddress!, UInt32(buffer.count))
        }
        guard requestStatus == kIOReturnSuccess else { return nil }

        var reply = [UInt8](repeating: 0, count: Self.replyLength)
        let readStatus = reply.withUnsafeMutableBufferPointer { buffer in
            read(service, Self.chipAddress, Self.dataAddress, buffer.baseAddress!, UInt32(buffer.count))
        }
        guard readStatus == kIOReturnSuccess else { return nil }

        // Checksum over the first ten bytes has to equal the eleventh, or this
        // is noise from a display that merely has an I2C bus.
        var checksum: UInt8 = 0
        for index in 0..<(Self.replyLength - 1) { checksum ^= reply[index] }
        guard checksum == reply[Self.replyLength - 1] else { return nil }
        guard reply[0] == 0x6E, reply[1] == 0x00, reply[2] == code else { return nil }

        let current = (UInt16(reply[3]) << 8) | UInt16(reply[4])
        let maximum = (UInt16(reply[6]) << 8) | UInt16(reply[7])
        return (current, maximum)
    }

    /// The `IOAVService` for a display, resolved through the framebuffer it is
    /// attached to and cached for the life of the process — the lookup walks the
    /// IOKit registry and has no business happening on a slider drag.
    private var services: [CGDirectDisplayID: CFTypeRef] = [:]

    private func service(for displayID: CGDirectDisplayID) -> CFTypeRef? {
        if let cached = services[displayID] { return cached }
        guard let create = Self.createWithService else { return nil }
        // The framebuffer's IODisplayConnect is what DDC is wired to. Asking
        // IOKit for it by display ID is the same lookup Apple's own brightness
        // and volume paths make.
        guard let connect = ioServiceForDisplay(displayID) else { return nil }
        defer { IOObjectRelease(connect) }
        guard let service = create(kCFAllocatorDefault, connect)?.takeRetainedValue() else { return nil }
        services[displayID] = service
        return service
    }

    private func ioServiceForDisplay(_ displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IODisplayConnect"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var match: io_service_t = 0
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }

            let dictionary = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?
                .takeRetainedValue() as? [String: Any]
            // The registry entry carries the display's EDID identity; matching
            // it to the CoreGraphics display is what ties an IOKit service to
            // the screen the user is looking at.
            let vendor = dictionary?["DisplayVendorID"] as? UInt32
            let product = dictionary?["DisplayProductID"] as? UInt32
            if vendor == CGDisplayVendorNumber(displayID), product == CGDisplayModelNumber(displayID) {
                match = service
                break
            }
            IOObjectRelease(service)
        }
        // The caller owns the returned service, and releases it after building
        // the IOAVService from it; every non-matching one is released here.
        return match == 0 ? nil : match
    }
}
