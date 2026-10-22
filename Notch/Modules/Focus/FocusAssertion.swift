import Foundation
import ObjectiveC

/// Turns macOS Focus on and off.
///
/// There is no public API for this. The system's own answer is the assertion
/// service in `DoNotDisturb.framework` — the one Control Center's Focus item
/// talks to — so that is what this uses, loaded at runtime and called through
/// its selectors rather than linked. An app that links a private framework
/// fails to launch the day Apple renames something; load-then-ask degrades to
/// "Focus can't be changed from here" and says so.
///
/// The surface used, checked against the framework on this machine:
/// - `+[DNDModeAssertionService serviceForClientIdentifier:]`
/// - `+[DNDModeAssertionDetails userRequestedAssertionDetailsWithIdentifier:modeIdentifier:lifetime:]`
/// - `+[DNDModeAssertionLifetime lifetimeForUserRequest]`
/// - `-[DNDModeAssertionService takeModeAssertionWithDetails:error:]`
/// - `-[DNDModeAssertionService invalidateActiveModeAssertionWithError:]`
///
/// Nothing here is AppKit and nothing reads the Focus database: the daemon owns
/// both, and the caller re-reads the state it already watches for.
enum FocusAssertion {
    /// Do Not Disturb — the one mode every Mac has.
    static let doNotDisturb = "com.apple.donotdisturb.mode.default"

    enum Failure: Equatable {
        /// The framework, a class or a selector was not there to call.
        case unavailable
        /// The call was made and the service would not take it.
        case refused

        var message: String {
            switch self {
            case .unavailable: "Focus can't be changed from Notch on this version of macOS."
            case .refused: "macOS didn't accept the Focus change."
            }
        }
    }

    /// Takes a Focus mode, or clears whatever assertion is active when
    /// `modeIdentifier` is nil.
    ///
    /// Synchronous — it is a single XPC round trip — so callers run it off the
    /// main thread.
    @discardableResult
    static func setActive(modeIdentifier: String?) -> Failure? {
        guard frameworkIsLoaded, let service = service() else { return .unavailable }

        guard let modeIdentifier else {
            // Answers BOOL rather than an object, so it is read as such — an
            // object-typed call to a BOOL-returning selector would hand ARC a
            // pointer that is not one. False means there was no assertion of
            // ours to drop: a Focus turned on in Control Center, or by a
            // schedule, is not this app's to end. Saying so is better than a
            // click that appears to do nothing.
            return sendBool(service, "invalidateActiveModeAssertionWithError:", nil)
                ? nil
                : .refused
        }

        guard let lifetimeClass = classObject("DNDModeAssertionLifetime"),
              let lifetime = send(lifetimeClass, "lifetimeForUserRequest"),
              let detailsClass = classObject("DNDModeAssertionDetails"),
              let details = send(
                  detailsClass,
                  "userRequestedAssertionDetailsWithIdentifier:modeIdentifier:lifetime:",
                  UUID().uuidString as AnyObject,
                  modeIdentifier as AnyObject,
                  lifetime
              )
        else { return .unavailable }

        // The assertion is the answer: a nil one means the daemon refused, and
        // the error out-parameter is optional by design.
        guard send(service, "takeModeAssertionWithDetails:error:", details, nil) != nil else {
            return .refused
        }
        return nil
    }

    // MARK: - The framework, by name

    private static let frameworkIsLoaded: Bool = {
        dlopen(
            "/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb",
            RTLD_LAZY
        ) != nil
    }()

    private static func classObject(_ name: String) -> AnyObject? {
        NSClassFromString(name) as AnyObject?
    }

    private static func service() -> AnyObject? {
        guard let serviceClass = classObject("DNDModeAssertionService") else { return nil }
        let identifier = Bundle.main.bundleIdentifier ?? "com.notchapp.Notch"
        return send(serviceClass, "serviceForClientIdentifier:", identifier as AnyObject)
    }

    /// One Objective-C message, typed generically.
    ///
    /// The extra argument slots are always present and default to nil: every
    /// selector used here takes at most three objects, and a nil is exactly
    /// what an absent argument would be. Optionals rather than three separate
    /// overloads, because the call sites differ only in how many they pass.
    private static func send(
        _ receiver: AnyObject,
        _ name: String,
        _ first: AnyObject? = nil,
        _ second: AnyObject? = nil,
        _ third: AnyObject? = nil
    ) -> AnyObject? {
        typealias Signature = @convention(c) (
            AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?
        ) -> AnyObject?
        let selector = NSSelectorFromString(name)
        guard let method = method(for: receiver, selector) else { return nil }
        let implementation = unsafeBitCast(method_getImplementation(method), to: Signature.self)
        return implementation(receiver, selector, first, second, third)
    }

    private static func sendBool(
        _ receiver: AnyObject, _ name: String, _ argument: AnyObject?
    ) -> Bool {
        typealias Signature = @convention(c) (AnyObject, Selector, AnyObject?) -> Bool
        let selector = NSSelectorFromString(name)
        guard let method = method(for: receiver, selector) else { return false }
        let implementation = unsafeBitCast(method_getImplementation(method), to: Signature.self)
        return implementation(receiver, selector, argument)
    }

    /// The method to call, whether the receiver is a class (a `+` selector) or
    /// an instance (a `-` one).
    private static func method(for receiver: AnyObject, _ selector: Selector) -> Method? {
        if class_isMetaClass(object_getClass(receiver)),
           let cls = receiver as? AnyClass {
            return class_getClassMethod(cls, selector)
        }
        return class_getInstanceMethod(type(of: receiver), selector)
    }
}
