import Foundation
import Observation

/// License state for the paid tier. Keys are validated offline against the
/// `NOTCH-XXXX-XXXX-XXXX` format and stored in defaults; wiring a real
/// licensing backend (Paddle / Lemon Squeezy / custom) means replacing
/// `validate(_:)` with a server check and keeping everything else.
@Observable
final class LicenseManager {
    static let shared = LicenseManager()

    private(set) var isPro: Bool
    private(set) var maskedKey: String?

    private static let defaultsKey = "licenseKey"
    static let purchaseURL = URL(string: "https://github.com/Wub796/Notch")!

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        if let stored, Self.validate(stored) {
            isPro = true
            maskedKey = Self.mask(stored)
        } else {
            isPro = false
            maskedKey = nil
        }
    }

    enum ActivationResult {
        case activated
        case invalidFormat
    }

    func activate(_ rawKey: String) -> ActivationResult {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.validate(key) else { return .invalidFormat }
        UserDefaults.standard.set(key, forKey: Self.defaultsKey)
        isPro = true
        maskedKey = Self.mask(key)
        return .activated
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        isPro = false
        maskedKey = nil
    }

    /// Offline shape check: NOTCH- followed by three groups of four
    /// uppercase alphanumerics.
    static func validate(_ key: String) -> Bool {
        key.range(of: "^NOTCH(-[A-Z0-9]{4}){3}$", options: .regularExpression) != nil
    }

    private static func mask(_ key: String) -> String {
        guard let last = key.split(separator: "-").last else { return key }
        return "NOTCH-••••-••••-\(last)"
    }
}
