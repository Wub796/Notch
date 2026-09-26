import Foundation
import Observation

/// One captured face, as it is persisted.
struct FaceSample: Codable, Equatable {
    /// 512 numbers from ArcFace — a mathematical fingerprint. The frame it came
    /// from is discarded; see `FaceIDEnrollmentSession`.
    let embedding: [Float]
    /// Which guided pose this came from, or nil for an untagged capture.
    let pose: String?
    let capturedAt: Date
    /// Vision's capture-quality score (0...1), or nil if unavailable.
    let quality: Float?
}

extension FaceSample {
    /// Lives here rather than in a view so the settings tick strip and the test
    /// readout can't drift apart.
    enum QualityTier {
        /// No score recorded. Never counted as poor.
        case unrated
        case poor
        case fair
        case good

        var title: String {
            switch self {
            case .unrated: "Unrated"
            case .poor: "Poor"
            case .fair: "Fair"
            case .good: "Good"
            }
        }
    }

    var qualityTier: QualityTier {
        guard let quality else { return .unrated }
        if quality < 0.4 { return .poor }
        if quality < 0.5 { return .fair }
        return .good
    }
}

/// Everyone the user has enrolled, as one named identity with the samples that
/// make it up.
struct FaceIdentity: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var samples: [FaceSample]
    /// Which `FaceEmbedder.modelIdentifier` produced these samples. Embeddings
    /// from different models live in unrelated vector spaces — comparing across
    /// them wouldn't error, it would produce confident nonsense. See
    /// `isStale(comparedTo:)`.
    var modelIdentifier: String
    var embeddingDimension: Int
    var createdAt: Date
    /// Turning this off keeps the enrollment intact but excludes it from
    /// `activeIdentities`, which recognition scores against.
    var isEnabled: Bool

    init(
        id: UUID,
        name: String,
        samples: [FaceSample],
        modelIdentifier: String,
        embeddingDimension: Int,
        createdAt: Date,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.samples = samples
        self.modelIdentifier = modelIdentifier
        self.embeddingDimension = embeddingDimension
        self.createdAt = createdAt
        self.isEnabled = isEnabled
    }

    /// Hand-written so `isEnabled` defaults to `true` when the key is absent:
    /// a synthesized decoder would throw on a missing key and, because the
    /// whole store decodes as one array, lose every identity in it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        samples = try container.decode([FaceSample].self, forKey: .samples)
        modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
        embeddingDimension = try container.decode(Int.self, forKey: .embeddingDimension)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    /// The single vector actually compared against at recognition time.
    var template: [Float]? {
        FaceEmbedding.average(samples.map(\.embedding))
    }

    /// True if these samples came from a different embedder than the one
    /// currently active, in which case they can never match and the UI should
    /// ask for a re-enrollment rather than fail silently forever.
    func isStale(comparedTo embedder: FaceEmbedder) -> Bool {
        modelIdentifier != embedder.modelIdentifier
    }
}

enum FaceEnrollmentStoreError: LocalizedError {
    case storeUnreadable

    var errorDescription: String? {
        switch self {
        case .storeUnreadable:
            "Your enrolled faces couldn't be read, so nothing was saved — writing now would "
                + "overwrite them."
        }
    }
}

/// The enrolled faces, loaded from and written to encrypted storage.
///
/// Ported from Glance (`FaceEnrollmentStore.swift`, MIT © Jonathan Zhou). The
/// two flags that look redundant are not: `isLocked` means "authenticate and
/// this will load", while `loadFailure` means "this will not load no matter how
/// many times you authenticate" — and the write path refuses in the second
/// case rather than overwriting a store it couldn't read.
@Observable
final class FaceEnrollmentStore {
    /// Shared so the panel screen and the settings pane observe the same
    /// identities rather than diverging copies.
    static let shared = FaceEnrollmentStore()

    private(set) var identities: [FaceIdentity] = []

    /// True until a successful load, which is what distinguishes "nothing
    /// enrolled yet" from "locked, needs Touch ID".
    private(set) var isLocked = true

    /// Non-nil when the session is unlocked but the store still couldn't be
    /// read. Unlike `isLocked`, unlocking again won't fix this.
    private(set) var loadFailure: String?

    /// False until a load succeeds. Guards `persist()`, so an unreadable store
    /// is never silently replaced by an empty array.
    private var hasLoadedSuccessfully = false

    /// Everyone the user hasn't switched off — what recognition actually
    /// scores against. `identities` stays the full list.
    var activeIdentities: [FaceIdentity] {
        identities.filter(\.isEnabled)
    }

    private init() {
        reloadIfUnlocked()
        // Reload whenever the session key changes, from wherever it changed,
        // so this store can't go stale relative to the credential UI.
        NotificationCenter.default.addObserver(
            forName: .faceIDSessionDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.reloadIfUnlocked()
            }
        }
    }

    /// Re-attempts loading from encrypted storage. A no-op, leaving
    /// `isLocked = true`, if the session isn't unlocked yet.
    func reloadIfUnlocked() {
        guard FaceIDCredentials.isSessionUnlocked else {
            isLocked = true
            return
        }
        do {
            identities = try FaceIDSecureFaceStore.load()
            hasLoadedSuccessfully = true
            loadFailure = nil
        } catch {
            // Deliberately not `(try? load()) ?? []` — a store that couldn't be
            // read is not an empty store, and the next write must not persist
            // an empty array over a file that still holds every sample.
            identities = []
            loadFailure = error.localizedDescription
        }
        isLocked = false
    }

    /// Commits a whole guided enrollment in one write. When `existingID` names
    /// a known identity its samples are replaced wholesale — a recapture is a
    /// redo, not an append — and it can be renamed, since matching is by id.
    @discardableResult
    func commitEnrollment(
        replacing existingID: UUID?,
        name: String,
        samples: [FaceSample],
        embedder: FaceEmbedder
    ) throws -> FaceIdentity? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !samples.isEmpty else { return nil }

        // A local copy, assigned only once the write succeeds — otherwise a
        // locked session would show a save that never reached disk.
        var updated = identities
        let committed: FaceIdentity
        if let existingID, let index = updated.firstIndex(where: { $0.id == existingID }) {
            updated[index].name = trimmed
            updated[index].samples = samples
            updated[index].modelIdentifier = embedder.modelIdentifier
            updated[index].embeddingDimension = embedder.embeddingDimension
            committed = updated[index]
        } else {
            // Also the fallback when `existingID` no longer resolves (deleted
            // mid-flow): saving as new beats discarding the captures.
            committed = FaceIdentity(
                id: UUID(),
                name: trimmed,
                samples: samples,
                modelIdentifier: embedder.modelIdentifier,
                embeddingDimension: embedder.embeddingDimension,
                createdAt: Date()
            )
            updated.append(committed)
        }
        try FaceIDSecureFaceStore.save(updated)
        identities = updated
        return committed
    }

    /// Case- and diacritic-insensitive, unlike an exact match: "alex", "Alex"
    /// and "Álex" are one person to the user even though storage would treat
    /// them as three. `excluding` lets a recapture keep its own name.
    func nameIsTaken(_ name: String, excluding id: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return identities.contains {
            $0.id != id
                && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Reverts the in-memory flag if the encrypted write fails, rather than
    /// showing a toggle state that isn't on disk.
    func setEnabled(_ isEnabled: Bool, for identityID: UUID) throws {
        guard let index = identities.firstIndex(where: { $0.id == identityID }) else { return }
        let previous = identities[index].isEnabled
        guard previous != isEnabled else { return }
        identities[index].isEnabled = isEnabled
        do {
            try persist()
        } catch {
            identities[index].isEnabled = previous
            throw error
        }
    }

    func rename(_ identityID: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = identities.firstIndex(where: { $0.id == identityID }) else { return }
        let previous = identities[index].name
        identities[index].name = trimmed
        do {
            try persist()
        } catch {
            identities[index].name = previous
            throw error
        }
    }

    func delete(_ identity: FaceIdentity) throws {
        identities.removeAll { $0.id == identity.id }
        try persist()
    }

    /// Removes the file outright rather than writing an empty array — the
    /// teardown path when the session key itself is going away, so no orphaned
    /// encrypted file is left behind for the next setup to trip over.
    func deleteAll() {
        identities.removeAll()
        FaceIDSecureFaceStore.deleteAll()
        loadFailure = nil
        hasLoadedSuccessfully = true
    }

    private func persist() throws {
        // Refuses to write when the last load failed, so an unreadable store
        // can't be silently replaced by an empty array.
        guard hasLoadedSuccessfully else {
            throw FaceEnrollmentStoreError.storeUnreadable
        }
        try FaceIDSecureFaceStore.save(identities)
    }
}
