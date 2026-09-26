import Foundation
import LocalAuthentication
import Security

/// Keychain items in Keychain Services, by account, plus the access-control
/// helper that gates one of them behind Touch ID.
///
/// Ported from Glance (`KeychainManager.swift`, MIT © Jonathan Zhou), with the
/// service name moved to this app's own bundle identifier so the two apps can
/// never read each other's items.
enum FaceIDKeychain {
    /// A separate service from `KeychainStore`'s: the session key is
    /// access-controlled and must be readable only by the Face ID flow, and
    /// keeping it in its own namespace makes that visible at a glance rather
    /// than by reading every call site.
    static let service = "com.notchapp.Notch.faceID"

    enum KeychainError: LocalizedError {
        case itemNotFound
        case unexpectedData
        case accessControlFailed(String)
        case authenticationFailed
        case authenticationUnavailable(String)
        case osStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                "Keychain item not found."
            case .unexpectedData:
                "Keychain item had an unexpected format."
            case .accessControlFailed(let message):
                "Couldn't create the Keychain access control: \(message)"
            case .authenticationFailed:
                "Authentication was cancelled or failed."
            case .authenticationUnavailable(let message):
                "Touch ID can't be used here: \(message)"
            case .osStatus(let status):
                "Keychain error: \(SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)")"
            }
        }

        /// `errSecMissingEntitlement` specifically, not "the write failed":
        /// it is the one status that says this *build* cannot reach the
        /// data-protection Keychain at all, so it is the one a caller can do
        /// something about (see `FaceIDCredentials.unlockSession(reason:)`).
        var isMissingEntitlement: Bool {
            if case .osStatus(let status) = self { return status == errSecMissingEntitlement }
            return false
        }
    }

    /// Existence check on attributes only — never prompts, even for an
    /// access-controlled item. Load-bearing: whether the *read* succeeded is
    /// indistinguishable from "no item" after a cancelled Touch ID prompt, so
    /// callers decide with this instead.
    static func exists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status != errSecItemNotFound
    }

    /// Pass an `LAContext` to authorize a read of an access-controlled item —
    /// the OS presents its prompt during this call.
    static func read(account: String, context: LAContext? = nil) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.unexpectedData }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecUserCanceled, errSecAuthFailed:
            throw KeychainError.authenticationFailed
        default:
            throw KeychainError.osStatus(status)
        }
    }

    /// Replaces any existing item. Pass `accessControl` to gate future reads
    /// behind Touch ID, or nothing for a device-local, unlock-only item.
    static func save(account: String, data: Data, accessControl: SecAccessControl? = nil) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        if let accessControl {
            addQuery[kSecAttrAccessControl as String] = accessControl
        } else {
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        var status = SecItemAdd(addQuery as CFDictionary, nil)
        // An item with no access control lands in the file-based Keychain,
        // which doesn't accept every accessibility class. Protection there
        // comes from the Keychain's own lock state anyway — the login Keychain
        // is what unlocks at login — so dropping the attribute costs nothing
        // real, and beats failing a write over an attribute nothing enforces.
        if status == errSecParam, addQuery[kSecAttrAccessible as String] != nil {
            addQuery[kSecAttrAccessible as String] = nil
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }

    /// Asks for Touch ID — or the device password, when there's no usable
    /// biometry — before a read of a *plain* item, for the builds where the
    /// access control below can't be used.
    ///
    /// Asynchronous on purpose. `evaluatePolicy`'s answer arrives on its own
    /// queue, so getting it back into a synchronous function means parking a
    /// thread for the whole duration of a prompt the user may leave open, and
    /// this is called from a task that the caller is already awaiting.
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            let message = evaluationError?.localizedDescription
                ?? "neither Touch ID nor a login password is set up"
            throw KeychainError.authenticationUnavailable(message)
        }
        guard (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true else {
            throw KeychainError.authenticationFailed
        }
    }

    /// `.userPresence` requires Touch ID or the device password, with no
    /// separate no-hardware handling needed.
    ///
    /// Items carrying one of these live in the data-protection Keychain, which
    /// a macOS app can only reach when it is signed with the
    /// `keychain-access-groups` entitlement. Where that isn't the case,
    /// `SecItemAdd` fails with `errSecMissingEntitlement` and the caller has to
    /// ask for authentication itself — `.userPresence` is the same policy
    /// `authenticate(reason:)` evaluates, so both shapes keep the same promise.
    static func makeUserPresenceAccessControl() throws -> SecAccessControl {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &accessError
        ) else {
            let message = (accessError?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw KeychainError.accessControlFailed(message)
        }
        return access
    }
}
