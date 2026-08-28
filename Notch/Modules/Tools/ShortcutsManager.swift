import Foundation
import Observation

/// Runs Shortcuts from the notch (Sapphire's shortcuts module), using the
/// system `shortcuts` CLI — no private APIs, no extra entitlements.
@Observable
final class ShortcutsManager {
    private(set) var shortcuts: [String] = []
    private(set) var isLoading = false
    private(set) var runningName: String?

    private static let executable = "/usr/bin/shortcuts"
    private static let favoritesKey = "favoriteShortcuts"

    /// Names the user pinned to the Tools tab.
    private(set) var favorites: [String] = UserDefaults.standard
        .stringArray(forKey: ShortcutsManager.favoritesKey) ?? []

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: Self.executable)
    }

    func refresh() {
        guard isAvailable, !isLoading else { return }
        isLoading = true

        Task.detached { [weak self] in
            let names = Self.run(arguments: ["list"])?
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                ?? []
            await MainActor.run { [weak self] in
                self?.shortcuts = names
                self?.isLoading = false
            }
        }
    }

    func run(_ name: String) {
        guard isAvailable else { return }
        runningName = name
        NotchTheme.Haptics.generic()

        Task.detached { [weak self] in
            _ = Self.run(arguments: ["run", name])
            await MainActor.run { [weak self] in
                if self?.runningName == name {
                    self?.runningName = nil
                }
            }
        }
    }

    func toggleFavorite(_ name: String) {
        if let index = favorites.firstIndex(of: name) {
            favorites.remove(at: index)
        } else {
            favorites.append(name)
        }
        UserDefaults.standard.set(favorites, forKey: Self.favoritesKey)
    }

    private static func run(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
