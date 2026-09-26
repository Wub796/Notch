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
    static let shared = AutoEQLibrary()

    private(set) var profiles: [AutoEQProfile] = []
    /// Set when an import was refused, so the UI can say why rather than
    /// appearing to ignore the file.
    private(set) var lastImportFailure: String?

    private let directory: URL
    private let indexURL: URL

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
            let text = try String(contentsOf: url, encoding: .utf8)
            let name = displayName(for: url)
            guard let profile = AutoEQParser.parse(text, name: name, source: url.lastPathComponent) else {
                lastImportFailure = "\(url.lastPathComponent) isn't an AutoEQ parametric or graphic profile."
                return nil
            }
            add(profile)
            return profile
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
            add(profile)
            return profile
        } catch {
            lastImportFailure = error.localizedDescription
            return nil
        }
    }

    func remove(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    private func add(_ profile: AutoEQProfile) {
        profiles.removeAll { $0.name.lowercased() == profile.name.lowercased() }
        profiles.append(profile)
        profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lastImportFailure = nil
        persist()
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
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([AutoEQProfile].self, from: data)
        else { return }
        profiles = stored
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            lastImportFailure = "Couldn't save the profile: \(error.localizedDescription)"
        }
    }
}
