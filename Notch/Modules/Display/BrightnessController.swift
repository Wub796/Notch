import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import Observation

/// Reads and sets the built-in display's brightness.
///
/// Loads both DisplayServices and CoreDisplay dynamically so brightness
/// control works reliably across all Apple Silicon and Intel Mac models.
@Observable
final class BrightnessController {
    private(set) var brightness: Float = 0.5
    private(set) var isAvailable = false

    private typealias DSGetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CDGetBrightnessFunc = @convention(c) (CGDirectDisplayID) -> Double
    private typealias CDSetBrightnessFunc = @convention(c) (CGDirectDisplayID, Double) -> Void

    private var dsGetBrightness: DSGetBrightnessFunc?
    private var dsSetBrightness: DSSetBrightnessFunc?
    private var dsGetLinearBrightness: DSGetBrightnessFunc?
    private var dsSetLinearBrightness: DSSetBrightnessFunc?

    private var cdGetUserBrightness: CDGetBrightnessFunc?
    private var cdSetUserBrightness: CDSetBrightnessFunc?
    private var cdGetLinearBrightness: CDGetBrightnessFunc?
    private var cdSetLinearBrightness: CDSetBrightnessFunc?

    init() {
        // 1. Try DisplayServices.framework
        if let dsHandle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        ) {
            if let sym = dlsym(dsHandle, "DisplayServicesGetBrightness") {
                dsGetBrightness = unsafeBitCast(sym, to: DSGetBrightnessFunc.self)
            }
            if let sym = dlsym(dsHandle, "DisplayServicesSetBrightness") {
                dsSetBrightness = unsafeBitCast(sym, to: DSSetBrightnessFunc.self)
            }
            if let sym = dlsym(dsHandle, "DisplayServicesGetLinearBrightness") {
                dsGetLinearBrightness = unsafeBitCast(sym, to: DSGetBrightnessFunc.self)
            }
            if let sym = dlsym(dsHandle, "DisplayServicesSetLinearBrightness") {
                dsSetLinearBrightness = unsafeBitCast(sym, to: DSSetBrightnessFunc.self)
            }
        }

        // 2. Try CoreDisplay.framework
        if let cdHandle = dlopen(
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            RTLD_NOW
        ) {
            if let sym = dlsym(cdHandle, "CoreDisplay_Display_GetUserBrightness") {
                cdGetUserBrightness = unsafeBitCast(sym, to: CDGetBrightnessFunc.self)
            }
            if let sym = dlsym(cdHandle, "CoreDisplay_Display_SetUserBrightness") {
                cdSetUserBrightness = unsafeBitCast(sym, to: CDSetBrightnessFunc.self)
            }
            if let sym = dlsym(cdHandle, "CoreDisplay_Display_GetLinearBrightness") {
                cdGetLinearBrightness = unsafeBitCast(sym, to: CDGetBrightnessFunc.self)
            }
            if let sym = dlsym(cdHandle, "CoreDisplay_Display_SetLinearBrightness") {
                cdSetLinearBrightness = unsafeBitCast(sym, to: CDSetBrightnessFunc.self)
            }
        }

        isAvailable = dsSetBrightness != nil || dsSetLinearBrightness != nil || cdSetUserBrightness != nil || cdSetLinearBrightness != nil
        refresh()
    }

    private var displayID: CGDirectDisplayID {
        if let screen = NSScreen.main,
           let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return num
        }
        return CGMainDisplayID()
    }

    /// Which brightness API pair is actually functional on this Mac, resolved
    /// once by probing each getter. The read and the write MUST share one API
    /// and one scale: macOS 27 broke CoreDisplay's brightness symbols — they
    /// answer 1.0 for any real level — so a CoreDisplay-first read made the
    /// notch think the display was always at maximum, and a CoreDisplay-only
    /// write silently did nothing. DisplayServices is the pair that answers on
    /// that version, and the probe picks the first getter that reports a real
    /// level, which keeps read and write from ever disagreeing about scale or
    /// targeting a dead API.
    private enum BrightnessAPI {
        case displayServicesUser
        case displayServicesLinear
        case coreDisplayUser
        case coreDisplayLinear
    }

    private var resolvedAPI: BrightnessAPI?

    private func resolveAPI() -> BrightnessAPI? {
        if let resolvedAPI { return resolvedAPI }
        let id = displayID
        let api: BrightnessAPI? = {
            if let get = dsGetBrightness {
                var level: Float = 0
                if get(id, &level) == 0, level > 0.001 { return .displayServicesUser }
            }
            if let get = dsGetLinearBrightness {
                var level: Float = 0
                if get(id, &level) == 0, level > 0.001 { return .displayServicesLinear }
            }
            if let get = cdGetUserBrightness, get(id) > 0.001 { return .coreDisplayUser }
            if let get = cdGetLinearBrightness, get(id) > 0.001 { return .coreDisplayLinear }
            return nil
        }()
        resolvedAPI = api
        return api
    }

    /// Reads the display's current brightness through the resolved API, so
    /// the value is always on the same scale the writer uses.
    func refresh() {
        let id = displayID
        guard let api = resolveAPI() else {
            if let legacy = Self.legacyBrightness() {
                brightness = legacy
                isAvailable = true
            }
            return
        }
        isAvailable = true
        switch api {
        case .displayServicesUser:
            var level: Float = 0
            if dsGetBrightness?(id, &level) == 0 {
                brightness = min(max(level, 0), 1)
            }
        case .displayServicesLinear:
            var level: Float = 0
            if dsGetLinearBrightness?(id, &level) == 0 {
                brightness = Self.userBrightness(forLinear: level)
            }
        case .coreDisplayUser:
            if let level = cdGetUserBrightness?(id), level > 0.001 {
                brightness = Float(min(max(level, 0), 1))
            }
        case .coreDisplayLinear:
            if let level = cdGetLinearBrightness?(id), level > 0.001 {
                brightness = Self.userBrightness(forLinear: Float(level))
            }
        }
    }

    /// Fallback floor for brightness writes on systems that reject a literal
    /// zero (older macOS versions hold the panel at its previous level rather
    /// than dimming it). On macOS 27+ the DisplayServices user-scale pair
    /// accepts a true `0` — verified empirically: writing 0 reads back 0 and
    /// the panel goes truly black — so the floor is only used when a write
    /// of zero is actually rejected. The linear-scale setters clamp on their
    /// own (~6% user), so they keep the floor rather than attempting zero.
    private static let absoluteMinUserBrightness: Float = 0.02
    /// Writes through the same resolved API the reader uses. A linear-scale
    /// pair gets the user level converted to linear luminance first, so the
    /// reading stays where the slider said.
    ///
    /// Returns the level the caller asked for (clamped to 0–1) so the HUD can
    /// render the bar at the user's position — including right down to 0 —
    /// without re-reading the display afterwards, which is what surfaced a
    /// stale brighter panel level as a "bounce back". A request for exactly 0
    /// is written as a literal zero through the DisplayServices user-scale
    /// pair, which reaches real black on macOS 27+; on systems that reject it
    /// the value is re-verified and a tiny floor (`absoluteMinUserBrightness`)
    /// is substituted so a rejected write can't hold the panel at a brighter
    /// level. The floor only affects what reaches the hardware, never what
    /// the slider shows.
    @discardableResult
    func setBrightness(_ newValue: Float) -> Float {
        let clamped = min(max(newValue, 0), 1)
        // Store the user-facing level as-is (so the bar tracks 0). Only the
        // value handed to the display is floored, and the zero path bypasses
        // the floor entirely to reach real black.
        brightness = clamped
        let writeValue = max(clamped, Self.absoluteMinUserBrightness)
        let id = displayID
        guard let api = resolveAPI() else {
            Self.setLegacyBrightness(writeValue)
            return clamped
        }
        switch api {
        case .displayServicesUser:
            if clamped == 0 {
                // A literal zero write is what produces real black on macOS
                // 27+. Older macOS rejects it; detect that by reading back
                // and retry with the tiny floor instead of leaving the panel
                // stuck at its previous level.
                _ = dsSetBrightness?(id, 0)
                var check: Float = 1
                if dsGetBrightness?(id, &check) == 0, check > Self.absoluteMinUserBrightness {
                    _ = dsSetBrightness?(id, Self.absoluteMinUserBrightness)
                }
            } else {
                _ = dsSetBrightness?(id, writeValue)
            }
        case .displayServicesLinear:
            _ = dsSetLinearBrightness?(id, Self.linearBrightness(forUserBrightness: writeValue))
        case .coreDisplayUser:
            cdSetUserBrightness?(id, Double(writeValue))
        case .coreDisplayLinear:
            cdSetLinearBrightness?(id, Double(Self.linearBrightness(forUserBrightness: writeValue)))
        }
        return clamped
    }

    /// Converts a linear luminance level back to the perceptual/user scale
    /// (the inverse of the 2.2-gamma encode below), for the displays whose
    /// only working API is the linear one.
    private static func userBrightness(forLinear linear: Float) -> Float {
        min(max(pow(linear, 1.0 / 2.2), 0), 1)
    }

    /// Converts a perceptual/user brightness (0–1) to the linear luminance
    /// scale the linear brightness APIs expect. Perceived brightness is
    /// roughly the 1/2.2 power of luminance, so the linear level for a given
    /// user level is its 2.2-gamma power.
    private static func linearBrightness(forUserBrightness user: Float) -> Float {
        min(max(pow(user, 2.2), 0), 1)
    }

    // MARK: - Intel fallback (IODisplay)

    private static func displayService() -> io_service_t {
        IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect")
        )
    }

    private static func legacyBrightness() -> Float? {
        let service = displayService()
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var level: Float = 0
        guard IODisplayGetFloatParameter(
            service, 0, kIODisplayBrightnessKey as CFString, &level
        ) == KERN_SUCCESS else { return nil }
        return min(max(level, 0), 1)
    }

    private static func setLegacyBrightness(_ value: Float) {
        let service = displayService()
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        IODisplaySetFloatParameter(
            service, 0, kIODisplayBrightnessKey as CFString, value
        )
    }
}
