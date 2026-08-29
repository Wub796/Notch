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

    private var hudTimer: Timer?
    private var lastSeenLevel: Float = -1

    /// Fired when the level changes without the app asking — i.e. the user
    /// pressed a brightness key — so the notch can raise its HUD.
    var onExternalChange: ((Float) -> Void)?
    private var isSelfSetting = false

    /// macOS posts no brightness-change notification, so without an event tap
    /// the only way to notice a key press is to sample. This is a single
    /// framework read at 4 Hz, and it is only used when HUD replacement is
    /// off — with the media-key interceptor running, the key press itself
    /// drives the HUD and nothing polls at all.
    func startHUDMonitoring() {
        guard isAvailable, hudTimer == nil else { return }
        refresh()
        lastSeenLevel = brightness
        hudTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let previous = self.brightness
            self.refresh()
            guard !self.isSelfSetting,
                  abs(self.brightness - previous) > 0.005,
                  abs(self.brightness - self.lastSeenLevel) > 0.005
            else { return }
            self.lastSeenLevel = self.brightness
            self.onExternalChange?(self.brightness)
        }
    }

    func stopHUDMonitoring() {
        hudTimer?.invalidate()
        hudTimer = nil
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
        lastSeenLevel = clamped
        isSelfSetting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isSelfSetting = false
        }

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
