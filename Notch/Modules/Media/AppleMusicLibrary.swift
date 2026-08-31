import AppKit
import Foundation
import Observation

/// Represents a playlist from Apple Music.
struct AppleMusicPlaylist: Identifiable, Hashable {
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

    private(set) var playlists: [AppleMusicPlaylist] = []
    private(set) var isLoading = false
    private(set) var lastLoad = Date.distantPast

    var isAuthorized: Bool {
        IntegrationPermissions.shared.musicStatus(for: .appleMusic) == .granted
    }

    /// Fetches all playlists from the macOS Music app asynchronously.
    func refresh(force: Bool = false) {
        guard IntegrationPermissions.isInstalled(.appleMusic) else { return }
        guard force || Date().timeIntervalSince(lastLoad) > 15 else { return }

        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scriptSource = """
            tell application "Music"
                if not (exists user playlists) then return ""
                set pIDs to persistent ID of user playlists
                set pNames to name of user playlists
                set pCounts to count of tracks of user playlists
                set pSmart to smart of user playlists
                set outText to ""
                repeat with i from 1 to count of pIDs
                    set curID to item i of pIDs
                    set curName to item i of pNames
                    set curCount to item i of pCounts
                    set curSmart to item i of pSmart as string
                    set outText to outText & curID & "<;>" & curName & "<;>" & (curCount as string) & "<;>" & curSmart & "\n"
                end repeat
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
                }
                self.isLoading = false
                self.lastLoad = Date()
            }
        }
    }

    /// Plays a playlist by name in Apple Music.
    func play(playlistName: String) {
        let escaped = playlistName.replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Music"
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
