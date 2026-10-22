import Foundation
import Observation

/// Reads the active macOS Focus mode from the Do Not Disturb database and
/// watches the directory for changes (no polling). The format matches what
/// Sapphire reads: an assertions file naming the active mode identifier, and
/// a configurations file describing each mode's name and symbol.
@Observable
final class FocusModeMonitor {
    struct Mode: Equatable {
        let name: String
        let symbolName: String
        let identifier: String
    }

    private(set) var activeMode: Mode?

    /// True while a Focus change is in flight, so a second click on the notch's
    /// focus button cannot queue another assertion behind the first.
    private(set) var isChanging = false

    /// Fired when a change is refused, so the click is answered with the
    /// reason instead of silence.
    var onError: ((String) -> Void)?

    /// Fired whenever the active focus changes, for the live activity.
    var onChange: ((Mode?) -> Void)?

    private let databaseURL: URL
    private let assertionsURL: URL
    private let configurationsURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        databaseURL = home.appending(path: "Library/DoNotDisturb/DB")
        assertionsURL = databaseURL.appending(path: "Assertions.json")
        configurationsURL = databaseURL.appending(path: "ModeConfigurations.json")
    }

    func start() {
        // Starting twice would open a second descriptor and drop the first
        // source without cancelling it, leaking both.
        guard source == nil else { return }
        reload(notify: false)

        descriptor = open(databaseURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .attrib, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reload(notify: true)
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }

    // MARK: - Changing it

    /// Turns the Focus that is on off, or Do Not Disturb on when none is.
    ///
    /// This is what the notch's focus indicator does: it used to open the Tools
    /// screen, which left the mode itself untouched — an indicator that looked
    /// like a control and was a signpost. The change goes through the system's
    /// own assertion service (`FocusAssertion`), and the state shown is then
    /// read back from the database this monitor already watches, so the glyph
    /// reflects what macOS did rather than what was asked for.
    func toggleFocus() {
        guard !isChanging else { return }
        isChanging = true
        let turningOff = activeMode != nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let failure = turningOff
                ? FocusAssertion.setActive(modeIdentifier: nil)
                : FocusAssertion.setActive(modeIdentifier: FocusAssertion.doNotDisturb)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isChanging = false
                if let message = failure?.message { self.onError?(message) }
                // The daemon writes the assertion a moment after it accepts
                // it, so the file is read once now and once after it has had
                // time to land — the second read is what moves the glyph when
                // the first was too early.
                self.reload(notify: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    self?.reload(notify: true)
                }
            }
        }
    }

    private func reload(notify: Bool) {
        let assertionsURL = self.assertionsURL
        let configurationsURL = self.configurationsURL
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let resolved = Self.readActiveMode(
                assertionsURL: assertionsURL,
                configurationsURL: configurationsURL
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, resolved != self.activeMode else { return }
                self.activeMode = resolved
                if notify {
                    self.onChange?(resolved)
                }
            }
        }
    }

    // MARK: - Parsing

    private struct Assertions: Decodable {
        struct Data: Decodable {
            let storeAssertionRecords: [Record]?
        }

        struct Record: Decodable {
            struct Details: Decodable {
                let assertionDetailsModeIdentifier: String?
            }

            let assertionDetails: Details?
            let assertionStartDateTimestamp: Double?
        }

        let data: [Data]
    }

    private struct Configurations: Decodable {
        struct Data: Decodable {
            let modeConfigurations: [String: Configuration]?
        }

        struct Configuration: Decodable {
            struct Mode: Decodable {
                let name: String?
                let modeIdentifier: String?
                let symbolImageName: String?
            }

            let mode: Mode
        }

        let data: [Data]
    }

    static func readActiveMode(assertionsURL: URL, configurationsURL: URL) -> Mode? {
        guard let assertionsData = try? Data(contentsOf: assertionsURL),
              let assertions = try? JSONDecoder().decode(Assertions.self, from: assertionsData),
              let record = assertions.data
                  .compactMap(\.storeAssertionRecords)
                  .flatMap({ $0 })
                  .max(by: {
                      ($0.assertionStartDateTimestamp ?? 0) < ($1.assertionStartDateTimestamp ?? 0)
                  }),
              let identifier = record.assertionDetails?.assertionDetailsModeIdentifier
        else { return nil }

        // Resolve the identifier to a display name and SF Symbol.
        if let configurationsData = try? Data(contentsOf: configurationsURL),
           let configurations = try? JSONDecoder()
               .decode(Configurations.self, from: configurationsData),
           let mode = configurations.data
               .compactMap(\.modeConfigurations)
               .flatMap({ $0.values })
               .map(\.mode)
               .first(where: { $0.modeIdentifier == identifier }) {
            return Mode(
                name: mode.name ?? "Focus",
                symbolName: mode.symbolImageName ?? "moon.fill",
                identifier: identifier
            )
        }

        return Mode(name: "Focus", symbolName: "moon.fill", identifier: identifier)
    }
}
