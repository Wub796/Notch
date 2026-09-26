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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("face-identities.enc")
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
        guard let ciphertext = try? Data(contentsOf: fileURL) else { return [] }
        let plaintext = try FaceIDCredentials.decrypt(ciphertext)
        return try JSONDecoder().decode([FaceIdentity].self, from: plaintext)
    }

    static func save(_ identities: [FaceIdentity]) throws {
        guard FaceIDCredentials.isSessionUnlocked else {
            throw FaceIDSecureFaceStoreError.sessionLocked
        }
        let plaintext = try JSONEncoder().encode(identities)
        let ciphertext = try FaceIDCredentials.encrypt(plaintext)
        try ciphertext.write(to: fileURL, options: .atomic)
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
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
