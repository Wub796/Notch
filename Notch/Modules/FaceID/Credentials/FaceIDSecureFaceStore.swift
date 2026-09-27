import Foundation

/// Encrypted persistence for enrolled face identities, using the same session
/// key `FaceIDCredentials` uses for the stored password rather than a second
/// one. `FaceEnrollmentStore` delegates its load and save here; there is no
/// plaintext fallback.
///
/// Ported from Glance (`SecureFaceStore.swift`, MIT © Jonathan Zhou).
enum FaceIDSecureFaceStore {
    /// Distinct filename and extension so plaintext can never be mistaken for
    /// ciphertext — and so a stray `.json` with the same stem is never read.
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Notch", isDirectory: true)
            .appendingPathComponent("face-identities.enc")
    }

    /// True if a store exists on disk, regardless of whether the session is
    /// currently unlocked enough to read it.
    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Throws `.sessionLocked` rather than returning an empty array, so callers
    /// can tell "nothing enrolled" from "enrolled, but locked".
    static func load() throws -> [FaceIdentity] {
        guard FaceIDCredentials.isSessionUnlocked else {
            throw FaceIDSecureFaceStoreError.sessionLocked
        }
        // Only a genuinely missing file means "no faces yet". Treat I/O errors
        // and malformed ciphertext as load failures so a later save cannot
        // overwrite an enrollment store that this build failed to read. Avoid
        // `fileExists` here: it also returns false when the path is inaccessible.
        do {
            let ciphertext = try Data(contentsOf: fileURL)
            let plaintext = try FaceIDCredentials.decrypt(ciphertext)
            return try JSONDecoder().decode([FaceIdentity].self, from: plaintext)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    static func save(_ identities: [FaceIdentity]) throws {
        guard FaceIDCredentials.isSessionUnlocked else {
            throw FaceIDSecureFaceStoreError.sessionLocked
        }
        let plaintext = try JSONEncoder().encode(identities)
        let ciphertext = try FaceIDCredentials.encrypt(plaintext)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ciphertext.write(to: fileURL, options: .atomic)
    }

    static func deleteAll() throws {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
            // Already absent is the desired final state.
        }
    }
}

enum FaceIDSecureFaceStoreError: LocalizedError {
    case sessionLocked

    var errorDescription: String? {
        switch self {
        case .sessionLocked:
            "The session is locked. Authenticate with Touch ID to access enrolled faces."
        }
    }
}
