import Foundation
import IOKit.hid
import OSLog

/// Detects the space bar on the lock screen through raw IOKit HID reads, which
/// is the only channel left once Secure Event Input starts suppressing ordinary
/// keyboard taps.
///
/// Ported from Glance (`SpaceKeyMonitor.swift`, MIT © Jonathan Zhou).
///
/// Notch is not in Input Monitoring in System Settings, and that is correct
/// rather than a bug: TCC resolves that gate against Accessibility first, and
/// the feature already needs Accessibility to type the password, so
/// `IOHIDCheckAccess` reports granted without ever registering the app there.
///
/// Not a keylogger: it runs only while the screen is locked *and* the user has
/// opted into the space trigger, and the callback checks nothing but whether
/// the key is the space bar.
final class SpaceKeyMonitor {
    /// Traces the Input Monitoring handshake, which is otherwise invisible —
    /// the TCC decision happens out of process, so a refusal here is a silent
    /// no-op on the lock screen.
    static let log = Logger(subsystem: "com.notchapp.Notch", category: "faceID.inputmonitoring")

    /// Fires on key-down only, never on release and never on auto-repeat.
    var onSpaceKeyDown: (() -> Void)?

    private var manager: IOHIDManager?

    // MARK: - Input Monitoring permission (static, callable without an instance)

    /// `denied` matters on its own: once set, no API can re-prompt — only
    /// System Settings can undo it.
    enum InputMonitoringAccess {
        case granted
        case denied
        case notDetermined
    }

    static var inputMonitoringAccess: InputMonitoringAccess {
        let raw = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch raw {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .notDetermined
        }
    }

    /// Never prompts. True whenever Accessibility is granted, for the reason in
    /// the file header.
    static func hasInputMonitoringAccess() -> Bool {
        inputMonitoringAccess == .granted
    }

    /// True when launched by Xcode's Run button, where TCC decisions are
    /// attributed to Xcode rather than to Notch — so permission behaviour must
    /// be tested from an independently launched copy.
    static var isLaunchedByXcode: Bool {
        ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
    }

    /// Near-always a no-op, since Accessibility has already satisfied the
    /// requirement. Skipped under Xcode, where the request would be attributed
    /// to Xcode instead.
    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        guard !isLaunchedByXcode else {
            log.error("requestAccess skipped — launched by Xcode, the request would be attributed to Xcode")
            return hasInputMonitoringAccess()
        }
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        log.info("requestAccess -> \(granted, privacy: .public)")
        return granted
    }

    // MARK: - Lifecycle

    /// Idempotent, and fails closed if access was revoked between the caller's
    /// check and here.
    func start() {
        guard manager == nil else { return }

        let created = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Physical keyboards only, not every HID device that happens to be attached.
        let match: [String: Int] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(created, match as CFDictionary)

        // A capture-less C callback with `self` threaded through the context
        // pointer. `passUnretained` is safe because this object always `stop()`s
        // (unregistering the callback) before it can be deallocated.
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(created, { context, _, _, value in
            guard let context else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
                  IOHIDElementGetUsage(element) == UInt32(kHIDUsage_KeyboardSpacebar),
                  IOHIDValueGetIntegerValue(value) == 1 // key-down only
            else { return }
            let monitor = Unmanaged<SpaceKeyMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.onSpaceKeyDown?()
            }
        }, context)

        IOHIDManagerScheduleWithRunLoop(created, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        // Ground truth about HID access, unlike `IOHIDCheckAccess`, and logged
        // because a failure here is otherwise a silent no-op on the lock screen.
        let result = IOHIDManagerOpen(created, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            Self.log.error(
                "IOHIDManagerOpen failed (0x\(String(result, radix: 16), privacy: .public)) — the space key won't be seen"
            )
            IOHIDManagerUnscheduleFromRunLoop(created, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return
        }
        Self.log.info("listening for space on the lock screen")
        manager = created
    }

    /// Stops listening. Idempotent.
    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }
}
