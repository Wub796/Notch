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

    func refresh() {
        let id = displayID

        if let cdGetUserBrightness {
            let val = cdGetUserBrightness(id)
            if val > 0.001 {
                brightness = Float(min(max(val, 0), 1))
                isAvailable = true
                return
            }
        }

        if let dsGetBrightness {
            var level: Float = 0
            if dsGetBrightness(id, &level) == 0 && level > 0.001 {
                brightness = min(max(level, 0), 1)
                isAvailable = true
                return
            }
        }

        if let dsGetLinearBrightness {
            var level: Float = 0
            if dsGetLinearBrightness(id, &level) == 0 && level > 0.001 {
                brightness = min(max(level, 0), 1)
                isAvailable = true
                return
            }
        }

        if let cdGetLinearBrightness {
            let val = cdGetLinearBrightness(id)
            if val > 0.001 {
                brightness = Float(min(max(val, 0), 1))
                isAvailable = true
                return
            }
        }

        if let legacy = Self.legacyBrightness() {
            brightness = legacy
            isAvailable = true
        }
    }

    func setBrightness(_ newValue: Float) {
        let clamped = min(max(newValue, 0), 1)
        brightness = clamped
        let id = displayID

        if let cdSetUserBrightness {
            cdSetUserBrightness(id, Double(clamped))
        }
        if let dsSetBrightness {
            _ = dsSetBrightness(id, clamped)
        }
        if let dsSetLinearBrightness {
            _ = dsSetLinearBrightness(id, clamped)
        }
        if let cdSetLinearBrightness {
            cdSetLinearBrightness(id, Double(clamped))
        }

        Self.setLegacyBrightness(clamped)
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
