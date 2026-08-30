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
