import Foundation
import Observation

/// The credential half of Face ID: session state, the stored password, and the
/// Accessibility grant that typing it needs.
///
/// Ported from Glance (`POCController.swift`, MIT © Jonathan Zhou). It exists so
/// the UI can be dumb about this — the panel screen and the settings pane read
/// `isSessionUnlocked` and call `unlockSession()`, and neither of them touches
/// `LAContext`, `SecItemAdd`, or `CGEvent` directly.
@Observable
final class FaceIDCredentialController {
    /// One instance for the app, the way the other cross-surface objects here work.
    /// Two of these would each hold their own idea of whether the session is
    /// unlocked, and unlocking from one would leave the other's UI claiming the
    /// opposite — a bug that reads as a broken button rather than as a stale flag.
    static let shared = FaceIDCredentialController()

    var accessibilityGranted: Bool = FaceIDKeystrokeInjector.isAccessibilityTrusted()

    var hasStoredPassword: Bool = FaceIDCredentials.hasStoredPassword()
    var isSessionUnlocked: Bool = FaceIDCredentials.isSessionUnlocked
    var sessionError: String?

    /// True while a Touch ID prompt is outstanding. The screen shows this
    /// because every failure mode here is otherwise invisible: a refused
    /// Keychain read, a dismissed prompt, and a prompt sitting behind another
    /// window all look identical from the outside — like a dead button.
    private(set) var isAuthenticating = false

    /// True when the session key that decrypts the stored password is gone while
    /// the encrypted data remains. Unlocking can never succeed in that state and
    /// nothing here can repair it, so the screen offers the only way out —
    /// `deleteEverything()` — next to the error rather than describing it.
    private(set) var needsResetBeforeUse = false

    /// Bound to the setup `SecureField`. Cleared immediately after a
    /// successful save, so the plaintext doesn't outlive the write.
    var passwordInput: String = ""

    var statusMessage: String = "Idle"

    func refreshAccessibilityStatus() {
        accessibilityGranted = FaceIDKeystrokeInjector.isAccessibilityTrusted()
    }

    func requestAccessibility() {
        FaceIDKeystrokeInjector.promptForAccessibility()
    }

    func refreshCredentialStatus() {
        hasStoredPassword = FaceIDCredentials.hasStoredPassword()
        isSessionUnlocked = FaceIDCredentials.isSessionUnlocked
    }

    // MARK: - Session (the Touch ID gate)

    /// Must succeed before `savePassword()` or `injectStoredPassword()` will do
    /// anything. The Touch ID prompt and the Keychain reads both run on a
    /// detached task, so the main actor is never waiting on either; every state
    /// assignment happens back on the main actor, so the screen is guaranteed to
    /// observe the result rather than racing a background write.
    @MainActor
    func unlockSession() async {
        guard !isAuthenticating else { return }
        sessionError = nil
        isAuthenticating = true

        #if DEBUG
        // Names the branch, not just the failure: `FaceIDCredentials` refuses to
        // mint a session key when encrypted data already exists, and that refusal
        // is the difference between "Touch ID said no" and "there is nothing left
        // to unlock".
        print("[FaceID] unlock: begin — sessionKey=\(FaceIDCredentials.hasSessionKey) "
            + "encryptedData=\(FaceIDCredentials.hasSessionEncryptedData) "
            + "cached=\(FaceIDCredentials.isSessionUnlocked)")
        #endif

        let authentication = Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                try await FaceIDCredentials.unlockSession(
                    reason: "Authenticate to set up or use Face ID"
                )
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        // A prompt that wants the user can wait indefinitely — one hidden behind
        // another window never gets answered, and nothing would ever clear the
        // flag above, which is what would leave one hung attempt as the only
        // attempt possible. The orphaned task is left alone: it may still
        // finish, and if it does, its result is the one that gets applied.
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.isAuthenticating else { return }
            self.isAuthenticating = false
            self.sessionError = "Touch ID didn't answer within 45 seconds. If a system prompt is waiting "
                + "for you — possibly behind another window — dismiss it and try again."
        }

        let outcome = await authentication.value
        watchdog.cancel()
        isAuthenticating = false

        switch outcome {
        case .success:
            #if DEBUG
            print("[FaceID] unlock: succeeded")
            #endif
            isSessionUnlocked = true
            needsResetBeforeUse = false
            // A watchdog message can have landed while the real prompt was still
            // open; the answer that arrived is the one that counts.
            sessionError = nil
        case .failure(let error):
            #if DEBUG
            print("[FaceID] unlock: failed — \(error.localizedDescription)")
            #endif
            isSessionUnlocked = false
            sessionError = error.localizedDescription
            needsResetBeforeUse = (error as? SecureCredentialError) == .sessionKeyUnavailable
        }
    }

    func lockSession() {
        FaceIDCredentials.lockSession()
        isSessionUnlocked = false
    }

    // MARK: - Setup

    /// Encrypts and stores `passwordInput`. Requires an already-unlocked
    /// session — Touch ID happens in `unlockSession()`, not here, because this
    /// path is also reached from the lock screen's retry flow.
    func savePassword() async {
        guard !passwordInput.isEmpty else {
            statusMessage = "Enter your Mac's login password first."
            return
        }
        let plaintext = passwordInput
        passwordInput = ""

        do {
            try await Task.detached(priority: .userInitiated) {
                guard var bytes = plaintext.data(using: .utf8) else {
                    throw SecureCredentialError.emptyPassword
                }
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                try FaceIDCredentials.savePassword(bytes)
            }.value
            statusMessage = "Password saved and encrypted."
            hasStoredPassword = true
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Forgets the password *and* the session key. The enrolled faces go with
    /// them, because they are sealed under that same key — leaving them would
    /// leave an encrypted file nothing can ever read again.
    func deleteEverything() {
        do {
            try FaceIDCredentials.deletePassword()
        } catch {
            statusMessage = "Couldn't clear the stored password: \(error.localizedDescription)"
            return
        }
        FaceEnrollmentStore.shared.deleteAll()
        hasStoredPassword = false
        isSessionUnlocked = false
        sessionError = nil
        needsResetBeforeUse = false
        statusMessage = "Stored password and enrolled faces removed."
    }

    // MARK: - Injection

    /// Reads, decrypts, and types the stored password, zeroing the plaintext
    /// buffer before returning. When `requireAuthoritativeLock` is true — the
    /// automatic path, driven by a lock or wake event — refuses unless
    /// CGSession confirms the screen is actually locked.
    ///
    /// Returns whether anything was typed, so the caller can tell a real
    /// unlock from a refusal.
    @discardableResult
    func injectStoredPassword(requireAuthoritativeLock: Bool = false) async -> Bool {
        guard FaceIDKeystrokeInjector.isAccessibilityTrusted() else {
            statusMessage = "Accessibility isn't granted — open System Settings and enable Notch."
            return false
        }
        guard FaceIDCredentials.isSessionUnlocked else {
            statusMessage = "The session is locked — authenticate with Touch ID first."
            return false
        }

        if requireAuthoritativeLock {
            guard LockMonitor.isScreenActuallyLocked() else {
                statusMessage = "Skipped: CGSession reports the screen is not actually locked."
                return false
            }
        }

        statusMessage = "Typing the password…"
        do {
            try await Task.detached(priority: .userInitiated) {
                var bytes = try FaceIDCredentials.readPassword()
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                try FaceIDKeystrokeInjector.typeAndReturn(bytes)
            }.value
            statusMessage = "Password typed at \(Date().formatted(date: .omitted, time: .standard))"
            return true
        } catch {
            statusMessage = "Couldn't type the password: \(error.localizedDescription)"
            return false
        }
    }
}
