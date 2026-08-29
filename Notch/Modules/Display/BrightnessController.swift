import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import Observation

/// Reads and sets the built-in display's brightness.
///
/// There is no public API for this. DisplayServices is the framework the
/// system's own brightness keys drive and the only thing that works on Apple
/// Silicon, so it is loaded at runtime with dlopen/dlsym — missing symbols
/// simply disable the control rather than crashing. On Intel Macs the older
/// IODisplay path is used as a fallback.
@Observable
final class BrightnessController {
    private(set) var brightness: Float = 0
    private(set) var isAvailable = false

    private typealias GetBrightnessFunc =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFunc =
        @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getBrightnessFunc: GetBrightnessFunc?
    private var setBrightnessFunc: SetBrightnessFunc?

    init() {
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        ) {
            if let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
                getBrightnessFunc = unsafeBitCast(symbol, to: GetBrightnessFunc.self)
            }
            if let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
                setBrightnessFunc = unsafeBitCast(symbol, to: SetBrightnessFunc.self)
            }
        }
        isAvailable = getBrightnessFunc != nil && setBrightnessFunc != nil
        refresh()
    }

    /// The built-in panel; external displays need DDC, which this doesn't do.
    private var displayID: CGDirectDisplayID {
        CGMainDisplayID()
    }

    private var pollTimer: Timer?

    /// The system gives no brightness-change notification, so while the notch
    /// is open the level is sampled to keep the bar in step with the F1/F2
    /// keys. Nothing runs once it closes.
    func startTracking() {
        guard isAvailable, pollTimer == nil else { return }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopTracking() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        if let getBrightnessFunc {
            var level: Float = 0
            if getBrightnessFunc(displayID, &level) == 0 {
                brightness = min(max(level, 0), 1)
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

        if let setBrightnessFunc, setBrightnessFunc(displayID, clamped) == 0 {
            return
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
