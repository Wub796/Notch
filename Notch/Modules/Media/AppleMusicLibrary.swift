import AppKit
import Foundation
import Observation

/// Represents a playlist from Apple Music.
struct AppleMusicPlaylist: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let trackCount: Int
    let kind: String
    let isSmart: Bool
}

/// Manages loading and playing user playlists from Apple Music on macOS.
@Observable
final class AppleMusicLibrary {
    static let shared = AppleMusicLibrary()
    private static let cacheKey = "notch.applemusic.playlists.cache"

    private(set) var playlists: [AppleMusicPlaylist] = []
    private(set) var isLoading = false
    private(set) var lastLoad = Date.distantPast

    var isAuthorized: Bool {
        IntegrationPermissions.shared.musicStatus(for: .appleMusic) == .granted
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode([AppleMusicPlaylist].self, from: data) {
            playlists = cached
        }
    }

    var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    /// Fetches all playlists from the macOS Music app asynchronously.
    func refresh(force: Bool = false) {
        guard IntegrationPermissions.isInstalled(.appleMusic) else { return }
        guard force || Date().timeIntervalSince(lastLoad) > 15 else { return }

        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scriptSource = """
            tell application "Music"
                set outText to ""
                try
                    repeat with p in user playlists
                        try
                            set pID to persistent ID of p
                            set pName to name of p
                            set pCount to count of tracks of p
                            set pSmart to smart of p
                            if pName is not "Library" and pName is not "Music" and pName is not "Downloaded" and pName is not "Genius" then
                                set outText to outText & pID & "<;>" & pName & "<;>" & (pCount as string) & "<;>" & (pSmart as string) & "\n"
                            end if
                        end try
                    end repeat
                on error
                    try
                        repeat with p in playlists
                            try
                                set pID to persistent ID of p
                                set pName to name of p
                                set pCount to count of tracks of p
                                if pName is not "Library" and pName is not "Music" and pName is not "Downloaded" and pName is not "Genius" and pName is not "Internet Radio" then
                                    set outText to outText & pID & "<;>" & pName & "<;>" & (pCount as string) & "<;>false\n"
                                end if
                            end try
                        end repeat
                    end try
                end try
                return outText
            end tell
            """

            var error: NSDictionary?
            var parsed: [AppleMusicPlaylist] = []
            if let script = NSAppleScript(source: scriptSource) {
                let result = script.executeAndReturnError(&error)
                if error == nil, let text = result.stringValue {
                    let lines = text.components(separatedBy: "\n")
                    for line in lines where !line.isEmpty {
                        let parts = line.components(separatedBy: "<;>")
                        if parts.count >= 4 {
                            let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                            let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                            let count = Int(parts[2].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                            let isSmart = parts[3].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
                            if !name.isEmpty {
                                parsed.append(AppleMusicPlaylist(
                                    id: id,
                                    name: name,
                                    trackCount: count,
                                    kind: isSmart ? "Smart Playlist" : "Playlist",
                                    isSmart: isSmart
                                ))
                            }
                        }
                    }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !parsed.isEmpty {
                    self.playlists = parsed
                    if let encoded = try? JSONEncoder().encode(parsed) {
                        UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
                    }
                }
                self.isLoading = false
                self.lastLoad = Date()
            }
        }
    }

    /// Launches Apple Music and loads playlists.
    func openMusicApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self?.refresh(force: true)
                }
            }
        }
    }

    /// Plays a playlist by name in Apple Music, launching the Music app if needed.
    func play(playlistName: String) {
        let escaped = playlistName.replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Music"
            activate
            try
                play (first user playlist whose name is "\(escaped)")
            on error
                play playlist "\(escaped)"
            end try
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}
