import CryptoKit
import Foundation
import LocalAuthentication

/// Two-tier storage on top of `FaceIDKeychain`: a Touch-ID-gated session key,
/// unwrapped once per launch, wrapping an ungated encrypted password blob that
/// is therefore safe to read at any time — including the lock screen, where no
/// app UI exists to host a Touch ID prompt.
///
/// Ported from Glance (`SecureCredentialManager.swift`, MIT © Jonathan Zhou).
/// The shape is the whole design: Touch ID authorizes the *session*, not each
/// unlock, because an unattended prompt at the lock screen can't be answered.
/// That is why the batch below is called a session and why
/// `FaceIDSessionAutoLocker` exists rather than a per-use prompt.
///
/// The session key is stored in one of two shapes, and they are separate
/// accounts rather than one account with two possible attribute sets, because
/// nothing about the stored item can be asked whether it is access-controlled:
/// a read of a plain item succeeds without a prompt, so a single account would
/// silently stop asking for Touch ID the moment the fallback was used.
///
/// - `sessionKey`: carrying a `.userPresence` access control, so the Keychain
///   itself refuses the bytes until Touch ID has been answered. Needs the
///   data-protection Keychain, and therefore the `keychain-access-groups`
///   entitlement — see `unlockSession(reason:)` for what happens without it.
/// - `sessionKeyAppGated`: the same key bytes, ungated, behind an explicit
///   `LAContext` prompt evaluated by this code before the read.
enum FaceIDCredentials {
    private static let keychainGatedSessionKeyAccount = "sessionKey"
    private static let appGatedSessionKeyAccount = "sessionKeyAppGated"
    private static let passwordBlobAccount = "encryptedPassword"

    // MARK: - Session state (thread-safe via NSLock)

    private static let sessionLock = NSLock()
    private nonisolated(unsafe) static var _cachedKey: SymmetricKey?
    /// Last unlock or successful `readPassword` — what `FaceIDSessionAutoLocker`
    /// compares against the idle limit. Guarded by `sessionLock` alongside the
    /// key so the two can never be observed out of step.
    private nonisolated(unsafe) static var _lastActivityAt: Date?

    static var isSessionUnlocked: Bool {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _cachedKey != nil
    }

    /// `nil` whenever the session is locked — there is no activity to age.
    static var lastActivityAt: Date? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _lastActivityAt
    }

    private static func cachedKey() -> SymmetricKey? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _cachedKey
    }

    private static func setCachedKey(_ key: SymmetricKey?) {
        sessionLock.lock()
        let changed = (key != nil) != (_cachedKey != nil)
        _cachedKey = key
        _lastActivityAt = key == nil ? nil : Date()
        sessionLock.unlock()
        // Posted after releasing the lock: an observer may call back into
        // `isSessionUnlocked`, which re-acquires it, so posting while still
        // holding it is a real self-deadlock rather than a theoretical one.
        guard changed else { return }
        NotificationCenter.default.post(name: .faceIDSessionDidChange, object: nil)
    }

    /// Resets the idle countdown on each successful use, so an actively-used
    /// session never auto-locks.
    private static func recordActivity() {
        sessionLock.lock()
        if _cachedKey != nil { _lastActivityAt = Date() }
        sessionLock.unlock()
    }

    // MARK: - Generic session-key crypto
    //
    // Shared by the password here and the face templates in
    // `FaceIDSecureFaceStore` — one key, one encryption path, rather than a
    // second key to keep in step with this one.

    static func encrypt(_ plaintext: Data) throws -> Data {
        guard let key = cachedKey() else { throw SecureCredentialError.sessionLocked }
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else { throw SecureCredentialError.encryptionFailed }
            return combined
        } catch {
            throw SecureCredentialError.encryptionFailed
        }
    }

    static func decrypt(_ ciphertext: Data) throws -> Data {
        guard let key = cachedKey() else { throw SecureCredentialError.sessionLocked }
        do {
            let sealed = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealed, using: key)
        } catch {
            throw SecureCredentialError.decryptionFailed
        }
    }

    // MARK: - Public API

    static func hasStoredPassword() -> Bool {
        FaceIDKeychain.exists(account: passwordBlobAccount)
    }

    /// Prompts Touch ID and unwraps the session key, creating it behind Touch
    /// ID on first use. The Keychain calls are synchronous but brief; only
    /// `FaceIDKeychain.authenticate(reason:)` waits on the user, and it is
    /// awaited rather than slept on.
    ///
    /// The cached key is only set after a real read-back succeeds: `SecItemAdd`
    /// returns success even when the user hit Cancel on the auth UI, so the
    /// write alone proves nothing.
    static func unlockSession(reason: String) async throws {
        if cachedKey() != nil {
            #if DEBUG
            print("[FaceID] credentials: session key already cached")
            #endif
            return
        }

        // The existence check, not the read, decides whether a key gets
        // created, and that is load-bearing: a cancelled Touch ID prompt on a
        // user-presence item reports `errSecItemNotFound`, indistinguishable
        // from "no key" — deciding on the read's error would mint a fresh key
        // (destroying the one that decrypts existing data) on every mis-tap.
        if FaceIDKeychain.exists(account: keychainGatedSessionKeyAccount) {
            #if DEBUG
            print("[FaceID] credentials: reading the Keychain-gated session key")
            #endif
            do {
                setCachedKey(try readKeychainGatedSessionKey(reason: reason))
            } catch let error as FaceIDKeychain.KeychainError where error.isMissingEntitlement {
                // The key is here, in a form this build isn't signed to open —
                // a build that had `keychain-access-groups` and no longer
                // does. Retrying can't clear it and nothing can be minted
                // over it, so this is the same dead end as a lost key, down
                // to the way out: delete both and set up again.
                #if DEBUG
                print("[FaceID] credentials: the stored key is access-controlled and this build can't open it")
                #endif
                throw SecureCredentialError.sessionKeyUnavailable
            }
            return
        }

        if FaceIDKeychain.exists(account: appGatedSessionKeyAccount) {
            #if DEBUG
            print("[FaceID] credentials: asking Touch ID for the app-gated session key")
            #endif
            try await FaceIDKeychain.authenticate(reason: reason)
            setCachedKey(SymmetricKey(data: try FaceIDKeychain.read(account: appGatedSessionKeyAccount)))
            return
        }

        // No key at all — but minting one is still destructive if data is
        // already encrypted under a previous key (a re-signed build, say), so
        // refuse rather than silently render it unreadable forever.
        guard !hasSessionEncryptedData else {
            #if DEBUG
            print("[FaceID] credentials: no session key, and encrypted data exists — refusing to mint one")
            #endif
            throw SecureCredentialError.sessionKeyUnavailable
        }

        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }

        #if DEBUG
        print("[FaceID] credentials: minting a new session key")
        #endif

        // Try the shape with the Keychain enforcing Touch ID itself. An
        // access-controlled item lives in the data-protection Keychain, which
        // a macOS app can only reach with the `keychain-access-groups`
        // entitlement; without it the write is refused outright rather than
        // stored unprotected, so a failure here is safe to recover from.
        var keychainGated = true
        do {
            let access = try FaceIDKeychain.makeUserPresenceAccessControl()
            try FaceIDKeychain.save(
                account: keychainGatedSessionKeyAccount,
                data: raw,
                accessControl: access
            )
        } catch let error as FaceIDKeychain.KeychainError where error.isMissingEntitlement {
            keychainGated = false
        }

        if keychainGated {
            #if DEBUG
            print("[FaceID] credentials: stored it Keychain-gated; reading it back through Touch ID")
            #endif
            // Through the gated path rather than trusting the write: only a
            // read proves the user actually answered a prompt.
            setCachedKey(try readKeychainGatedSessionKey(reason: reason))
            return
        }

        #if DEBUG
        print("[FaceID] credentials: no keychain-access-groups entitlement — "
            + "asking Touch ID directly and storing the key app-gated")
        #endif
        // Ask *before* writing, so a cancelled prompt leaves nothing behind to
        // be found on the next attempt as if it had been authenticated.
        try await FaceIDKeychain.authenticate(reason: reason)
        try FaceIDKeychain.save(account: appGatedSessionKeyAccount, data: raw)
        setCachedKey(key)
    }

    /// A context whose prompt carries this app's own reason, rather than the
    /// Keychain's stock "… wants to use your confidential information…".
    private static func promptContext(reason: String) -> LAContext {
        let context = LAContext()
        context.localizedReason = reason
        return context
    }

    /// Reads the access-controlled item, translating the one status a
    /// cancelled prompt produces into a cancellation. Both call sites have
    /// just proved the item exists, so "not found" cannot mean anything else.
    private static func readKeychainGatedSessionKey(reason: String) throws -> SymmetricKey {
        do {
            let data = try FaceIDKeychain.read(
                account: keychainGatedSessionKeyAccount,
                context: promptContext(reason: reason)
            )
            return SymmetricKey(data: data)
        } catch FaceIDKeychain.KeychainError.itemNotFound {
            throw FaceIDKeychain.KeychainError.authenticationFailed
        }
    }

    /// Checked without needing the key itself, so this stays answerable
    /// precisely when the key can't be read.
    static var hasSessionEncryptedData: Bool {
        FaceIDKeychain.exists(account: passwordBlobAccount) || FaceIDSecureFaceStore.exists
    }

    /// Whether a Touch ID-gated session key exists at all. Separate from reading
    /// it — and from `isSessionUnlocked`, which is only true once this launch has
    /// actually unwrapped it — because "the key is missing" and "the key is here
    /// but nobody has authenticated yet" need different answers from the UI.
    static var hasSessionKey: Bool {
        FaceIDKeychain.exists(account: keychainGatedSessionKeyAccount)
            || FaceIDKeychain.exists(account: appGatedSessionKeyAccount)
    }

    /// Clears the cached session key. The next save or read needs Touch ID again.
    static func lockSession() {
        setCachedKey(nil)
    }

    /// Encrypts and stores `passwordBytes`. Requires an unlocked session.
    /// Blocking; call from a background task.
    static func savePassword(_ passwordBytes: Data) throws {
        guard !passwordBytes.isEmpty else { throw SecureCredentialError.emptyPassword }
        let combined = try encrypt(passwordBytes)
        try FaceIDKeychain.save(account: passwordBlobAccount, data: combined)
    }

    /// No separate Touch ID prompt — only the session key was gated, at unlock
    /// time. The caller MUST zero the returned bytes with `.resetBytes(in:)`
    /// after use. Blocking; call from a background task.
    static func readPassword() throws -> Data {
        guard cachedKey() != nil else { throw SecureCredentialError.sessionLocked }
        let ciphertext = try FaceIDKeychain.read(account: passwordBlobAccount)
        let plaintext = try decrypt(ciphertext)
        // Only on success: a failed read should not extend the idle window.
        recordActivity()
        return plaintext
    }

    /// Deletes both Keychain items and clears the cached session key.
    static func deletePassword() throws {
        try FaceIDKeychain.delete(account: passwordBlobAccount)
        try FaceIDKeychain.delete(account: keychainGatedSessionKeyAccount)
        try FaceIDKeychain.delete(account: appGatedSessionKeyAccount)
        setCachedKey(nil)
    }
}

/// `Equatable` so callers can single out `sessionKeyUnavailable`, the one
/// failure that no amount of retrying can clear.
enum SecureCredentialError: LocalizedError, Equatable {
    case emptyPassword
    case sessionLocked
    case encryptionFailed
    case decryptionFailed
    case sessionKeyUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            "The password can't be empty."
        case .sessionLocked:
            "The session is locked. Authenticate with Touch ID before storing or using the password."
        case .encryptionFailed:
            "Encryption failed."
        case .decryptionFailed:
            "Decryption failed — the stored credential may be corrupted."
        case .sessionKeyUnavailable:
            "The session key that decrypts your stored password is either gone or stored in a form "
                + "this build can't open, and the encrypted data is still here — a build signed by a "
                + "different developer, a removed Keychain item, or a build that can no longer reach "
                + "the Keychain item it wrote does this. Nothing has been deleted. Use Reset Face ID "
                + "data to clear the stored password and any enrolled faces together, then set them "
                + "up again."
        }
    }
}

extension Notification.Name {
    /// Fires whenever the cached session key changes, so anything encrypted
    /// under it (the enrolled faces) can reload itself instead of relying on
    /// each call site to remember to.
    static let faceIDSessionDidChange = Notification.Name("FaceIDCredentials.sessionDidChange")
}
