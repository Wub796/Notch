import Foundation
import Observation

/// One filter line from an AutoEQ correction profile.
///
/// AutoEQ publishes measured headphone corrections as text: a parametric form
/// that names each filter's type, centre, gain and width, and a graphic form
/// that gives gain per frequency. Both describe the same idea — the difference
/// between a headphone's measured response and a target curve — and both are
/// supported here, because which one a given model ships varies.
struct AutoEQFilter: Codable, Equatable {
    enum Kind: String, Codable {
        case peaking
        case lowShelf
        case highShelf
    }

    var kind: Kind
    var frequency: Double
    var gain: Float
    var q: Double

    func biquad(sampleRate: Double) -> Biquad {
        switch kind {
        case .peaking:
            return Biquad.peaking(frequency: frequency, gainDB: Double(gain), q: q, sampleRate: sampleRate)
        case .lowShelf:
            return Biquad.lowShelf(frequency: frequency, gainDB: Double(gain), slope: max(q, 0.1), sampleRate: sampleRate)
        case .highShelf:
            return Biquad.highShelf(frequency: frequency, gainDB: Double(gain), slope: max(q, 0.1), sampleRate: sampleRate)
        }
    }
}

/// An imported correction: which headphones it is for, what it does, and where
/// it came from.
struct AutoEQProfile: Codable, Identifiable, Equatable {
    let id: UUID
    /// The model name, taken from the file or given by the user — this is what
    /// the device suggestion matches against.
    var name: String
    /// Where it was imported from, kept so a correction can be traced back to
    /// its source rather than being an anonymous set of numbers.
    var source: String
    /// The profile's own preamp, in dB, which exists to stop the correction's
    /// own boosts from clipping. Applied as a flat gain before the filters.
    var preampDB: Double
    var filters: [AutoEQFilter]
    /// Set when the profile arrived in graphic form, so it can be drawn on the
    /// ten band sliders as well as applied as filters.
    var graphicBands: [EQBand]?

    func biquads(sampleRate: Double) -> [Biquad] {
        filters.map { $0.biquad(sampleRate: sampleRate) }
    }

    /// Preamp folded into the strip's own gain, so no extra node is needed.
    var preampFactor: Float {
        Float(pow(10, preampDB / 20))
    }
}

/// Reads AutoEQ's two published text formats.
enum AutoEQParser {
    /// `Preamp: -6.2 dB` plus `Filter 1: ON PK Fc 20 Hz Gain 6.0 dB Q 1.41`
    /// lines. LSC/HSC are the shelving filters the same profiles use at the
    /// ends of the range.
    static func parseParametric(_ text: String, name: String, source: String) -> AutoEQProfile? {
        var filters: [AutoEQFilter] = []
        var preamp = 0.0

        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("preamp") {
                preamp = firstNumber(in: trimmed) ?? 0
                continue
            }
            guard trimmed.lowercased().contains("filter"),
                  let kind = filterKind(in: trimmed),
                  let frequency = value(after: "fc", in: trimmed),
                  let gain = value(after: "gain", in: trimmed)
            else { continue }
            let q = value(after: "q", in: trimmed) ?? 0.7
            filters.append(AutoEQFilter(kind: kind, frequency: frequency, gain: Float(gain), q: q))
        }

        guard !filters.isEmpty else { return nil }
        return AutoEQProfile(id: UUID(), name: name, source: source, preampDB: preamp, filters: filters, graphicBands: nil)
    }

    /// `GraphicEQ: 20 -3.4; 21 -3.3; …` — one gain per frequency. Kept as both
    /// a filter set (so it can be applied) and a curve on the standard ten
    /// bands (so it can be seen and adjusted).
    static func parseGraphic(_ text: String, name: String, source: String) -> AutoEQProfile? {
        guard let start = text.range(of: "GraphicEQ:") else { return nil }
        let body = text[start.upperBound...]

        var points: [(frequency: Double, gain: Float)] = []
        for pair in body.split(separator: ";") {
            let parts = pair.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
            guard parts.count >= 2,
                  let frequency = Double(parts[0]),
                  let gain = Double(parts[1])
            else { continue }
            points.append((frequency, Float(gain)))
        }
        guard !points.isEmpty else { return nil }

        // Applied as one peaking filter per standard band, each set to the
        // published gain nearest its centre: the graphic form is already a
        // smooth curve, so a second layer of smoothing would only blur it.
        let bands = EqualizerPreset.graphicFrequencies.map { centre -> EQBand in
            let nearest = points.min { abs(log2($0.frequency / centre)) < abs(log2($1.frequency / centre)) }
            return EQBand(frequency: centre, gain: nearest?.gain ?? 0, q: EqualizerPreset.graphicQ)
        }

        return AutoEQProfile(
            id: UUID(),
            name: name,
            source: source,
            preampDB: 0,
            filters: bands.map { AutoEQFilter(kind: .peaking, frequency: $0.frequency, gain: $0.gain, q: $0.q) },
            graphicBands: bands
        )
    }

    /// Reads whichever format the text turns out to be.
    static func parse(_ text: String, name: String, source: String) -> AutoEQProfile? {
        if text.contains("GraphicEQ:") {
            return parseGraphic(text, name: name, source: source)
        }
        return parseParametric(text, name: name, source: source)
    }

    // MARK: - Line scanning

    private static func filterKind(in line: String) -> AutoEQFilter.Kind? {
        let upper = line.uppercased()
        if upper.contains(" LSC ") || upper.contains(" LS ") { return .lowShelf }
        if upper.contains(" HSC ") || upper.contains(" HS ") { return .highShelf }
        if upper.contains(" PK ") { return .peaking }
        return nil
    }

    /// The first `-?digits` that follows a keyword — with or without a colon
    /// between them, since AutoEQ writes `Preamp:` but `Fc`, `Gain` and `Q`.
    private static func value(after keyword: String, in line: String) -> Double? {
        let pattern = "(?i)" + keyword + ":?\\s+(-?[0-9.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: line)
        else { return nil }
        return Double(line[captured])
    }

    private static func firstNumber(in line: String) -> Double? {
        value(after: "preamp", in: line)
    }
}

/// The imported corrections this app knows about.
///
/// Kept as files rather than defaults: a profile is a few dozen numbers and a
/// name, and users accumulate them, which is what a folder is for. The index is
/// loaded once at launch — nothing here is on the audio path.
@Observable
final class AutoEQLibrary {
    enum LibraryError: LocalizedError {
        case storeUnreadable
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .storeUnreadable:
                "The profile library couldn't be read, so saving is blocked to avoid overwriting it."
            case .saveFailed(let error):
                "Couldn't save the profile library: \(error.localizedDescription)"
            }
        }
    }
    static let shared = AutoEQLibrary()

    private(set) var profiles: [AutoEQProfile] = []
    /// Set when an import was refused, so the UI can say why rather than
    /// appearing to ignore the file.
    private(set) var lastImportFailure: String?

    private let directory: URL
    private let indexURL: URL
    /// Distinguishes a valid empty library from a file that exists but could
    /// not be decoded; writes must not replace the latter with an empty list.
    private var hasLoadedSuccessfully = false

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("Notch/AutoEQ", isDirectory: true)
        indexURL = directory.appendingPathComponent("profiles.json")
        load()
    }

    func profile(id: UUID) -> AutoEQProfile? {
        profiles.first { $0.id == id }
    }

    /// Where the imported corrections live, so Settings can show the folder
    /// rather than describing it.
    var directoryURL: URL { directory }
    var isStoreReadable: Bool { hasLoadedSuccessfully }

    /// The profile whose name best matches an output device, used to
    /// pre-select a correction when a pair of headphones is first seen.
    func suggestedProfile(forDeviceName name: String) -> AutoEQProfile? {
        let needle = name.lowercased()
        return profiles.first { profile in
            let candidate = profile.name.lowercased()
            return candidate == needle || needle.contains(candidate) || candidate.contains(needle)
        }
    }

    /// Imports a downloaded AutoEQ text file. The display name is the file's
    /// own name with the usual suffixes trimmed, since that is the model name
    /// in every published profile.
    @discardableResult
    func importProfile(from url: URL) -> AutoEQProfile? {
        do {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            let name = displayName(for: url)
            guard let profile = AutoEQParser.parse(text, name: name, source: url.lastPathComponent) else {
                lastImportFailure = "\(url.lastPathComponent) isn't an AutoEQ parametric or graphic profile."
                return nil
            }
            return try add(profile)
        } catch {
            lastImportFailure = error.localizedDescription
            return nil
        }
    }

    /// Imports from a URL — the way AutoEQ profiles are normally obtained,
    /// since the project publishes them per model rather than in one bundle.
    @discardableResult
    func importProfile(fromRemote url: URL) async -> AutoEQProfile? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else {
                lastImportFailure = "That URL didn't return text."
                return nil
            }
            let name = url.deletingPathExtension().lastPathComponent
            guard let profile = AutoEQParser.parse(text, name: name, source: url.absoluteString) else {
                lastImportFailure = "That file isn't an AutoEQ parametric or graphic profile."
                return nil
            }
            return try add(profile)
        } catch {
            lastImportFailure = error.localizedDescription
            return nil
        }
    }

    func remove(_ id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { return }
        var updated = profiles
        updated.removeAll { $0.id == id }
        try persist(updated)
        profiles = updated
        lastImportFailure = nil
        MixerBridge.shared.mixer?.reconcileAutoEQProfileReferences(
            replacements: [:],
            validProfileIDs: Set(updated.map(\.id))
        )
    }

    @discardableResult
    private func add(_ profile: AutoEQProfile) throws -> AutoEQProfile {
        let matchingProfiles = profiles.filter {
            $0.name.compare(profile.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        let committed = AutoEQProfile(
            id: matchingProfiles.first?.id ?? profile.id,
            name: profile.name,
            source: profile.source,
            preampDB: profile.preampDB,
            filters: profile.filters,
            graphicBands: profile.graphicBands
        )
        var updated = profiles.filter {
            $0.name.compare(profile.name, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
        updated.append(committed)
        updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try persist(updated)
        profiles = updated
        lastImportFailure = nil

        let replacements = Dictionary(
            uniqueKeysWithValues: matchingProfiles
                .filter { $0.id != committed.id }
                .map { ($0.id, committed.id) }
        )
        MixerBridge.shared.mixer?.reconcileAutoEQProfileReferences(
            replacements: replacements,
            validProfileIDs: Set(updated.map(\.id))
        )
        return committed
    }

    private func displayName(for url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        for suffix in [" ParametricEQ", " GraphicEQ", " Parametric", " Graphic", "_ParametricEQ", "_GraphicEQ"] {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
            }
        }
        return name.replacingOccurrences(of: "_", with: " ")
    }

    private func load() {
        do {
            let data = try Data(contentsOf: indexURL)
            profiles = try JSONDecoder().decode([AutoEQProfile].self, from: data)
            hasLoadedSuccessfully = true
        } catch CocoaError.fileReadNoSuchFile {
            // A missing index is the normal empty-library state.
            hasLoadedSuccessfully = true
        } catch {
            hasLoadedSuccessfully = false
            lastImportFailure = "Couldn't read the profile library: \(error.localizedDescription)"
        }
    }

    private func persist(_ updated: [AutoEQProfile]) throws {
        guard hasLoadedSuccessfully else {
            throw LibraryError.storeUnreadable
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(updated)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            let failure = LibraryError.saveFailed(error)
            lastImportFailure = failure.localizedDescription
            throw failure
        }
    }
}
