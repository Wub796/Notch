import AppKit
import CoreLocation
import SwiftUI
import EventKit
import Foundation
import Observation

/// Live authorization state for the integrations the notch depends on.
///
/// Statuses are cached and refreshed explicitly rather than recomputed on
/// every view render: creating a `CLLocationManager` per read reports
/// `.notDetermined` regardless of the real authorization on macOS, which is
/// why the settings pane used to show wrong values. A single long-lived
/// manager is the only reliable way to read location authorization.
@Observable
final class IntegrationPermissions: NSObject, CLLocationManagerDelegate {
    static let shared = IntegrationPermissions()

    enum Status: String {
        case granted
        case denied
        case notDetermined
        /// Authorization can't be determined right now — for Apple Events,
        /// the target app has to be running before macOS will answer.
        case unknown

        var title: String {
            switch self {
            case .granted: "Granted"
            case .denied: "Denied"
            case .notDetermined: "Not requested"
            case .unknown: "Unavailable"
            }
        }

        var tint: Color {
            switch self {
            case .granted: .green
            case .denied: .red
            case .notDetermined: .orange
            case .unknown: .secondary
            }
        }
    }

    enum Integration: String, CaseIterable, Identifiable {
        case music
        case calendar
        case location

        var id: String { rawValue }

        var title: String {
            switch self {
            case .music: "Music control"
            case .calendar: "Calendar"
            case .location: "Location"
            }
        }

        var systemImage: String {
            switch self {
            case .music: "music.note"
            case .calendar: "calendar"
            case .location: "location.fill"
            }
        }

        var detail: String {
            switch self {
            case .music:
                "Lets the notch play, pause, and skip in Music or Spotify."
            case .calendar:
                "Shows your schedule and upcoming meetings."
            case .location:
                "Pins weather to your exact city."
            }
        }

        /// What the app still does when this is not granted — so the pane can
        /// tell the truth about consequences instead of implying breakage.
        var fallbackNote: String {
            switch self {
            case .music:
                "Without it, playback still follows whatever is playing — only direct control needs permission."
            case .calendar:
                "Without it, the schedule stays empty."
            case .location:
                "Without it, weather falls back to an approximate location from your network."
            }
        }

        var settingsURL: URL? {
            let base = "x-apple.systempreferences:com.apple.preference.security"
            switch self {
            case .music: return URL(string: base + "?Privacy_Automation")
            case .calendar: return URL(string: base + "?Privacy_Calendars")
            case .location: return URL(string: base + "?Privacy_LocationServices")
            }
        }
    }

    /// Current status per integration, refreshed by `refresh()`.
    private(set) var statuses: [Integration: Status] = [:]

    /// Extra context shown under a row, e.g. why music can't be verified.
    private(set) var notes: [Integration: String] = [:]

    /// Integrations with a request in flight, so the row can show progress
    /// instead of looking like the button did nothing.
    private(set) var pending: Set<Integration> = []

    private let locationManager = CLLocationManager()
    private var calendarStore: EKEventStore?

    private override init() {
        super.init()
        locationManager.delegate = self
        refresh()
    }

    func status(for integration: Integration) -> Status {
        statuses[integration] ?? .unknown
    }

    // MARK: - Refresh

    func refresh() {
        // Notes describe the most recent attempt, so a fresh read clears them
        // before anything re-states its own.
        notes.removeAll()

        statuses[.calendar] = calendarStatus()
        statuses[.location] = locationStatus()

        let music = musicStatus()
        statuses[.music] = music.status
        notes[.music] = music.note
    }

    private func calendarStatus() -> Status {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: .granted
        case .writeOnly: .denied
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    /// Read from the one long-lived manager, which is the only source that
    /// reports macOS location authorization correctly.
    private func locationStatus() -> Status {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    /// Apple Events authorization is only answerable while the target app is
    /// running. When it isn't, say so rather than guessing from a cached flag
    /// — the old code reported "Granted" having verified nothing.
    private func musicStatus() -> (status: Status, note: String?) {
        let provider = NotchSettings.shared.musicProvider
        let bundleID = provider == .spotify ? "com.spotify.client" : "com.apple.Music"
        let appName = provider == .spotify ? "Spotify" : "Music"

        guard !NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID).isEmpty
        else {
            return (.unknown, "\(appName) isn't running — open it to check access.")
        }

        guard let data = bundleID.data(using: .utf8) else {
            return (.unknown, nil)
        }

        var target = AEAddressDesc()
        // AECreateDesc is one of the older Apple Event calls and still returns
        // OSErr (Int16); AEDeterminePermissionToAutomateTarget below returns
        // OSStatus (Int32). Widening here keeps both comparable to noErr.
        let created = data.withUnsafeBytes { raw -> OSStatus in
            // -50 is paramErr: the bundle ID produced no bytes.
            guard let base = raw.baseAddress else { return OSStatus(-50) }
            return OSStatus(
                AECreateDesc(DescType(typeApplicationBundleID), base, data.count, &target)
            )
        }
        guard created == noErr else { return (.unknown, nil) }
        defer { AEDisposeDesc(&target) }

        // askUserIfNeeded: false — this is a status probe, not a request.
        let result = AEDeterminePermissionToAutomateTarget(
            &target, DescType(typeWildCard), DescType(typeWildCard), false
        )

        switch result {
        case noErr:
            return (.granted, nil)
        case OSStatus(-1743): // errAEEventNotPermitted
            return (.denied, "Enable Notch under Privacy & Security → Automation.")
        case OSStatus(-600): // procNotFound
            return (.unknown, "\(appName) isn't running — open it to check access.")
        default:
            return (.notDetermined, nil)
        }
    }

    // MARK: - Requests

    /// Asks macOS for access. Every path ends by re-reading the real status
    /// and, when nothing moved, saying why — a system prompt that cannot be
    /// shown (already answered once, or the service switched off globally) is
    /// silent, and silence is what made these buttons look broken.
    func request(_ integration: Integration, completion: @escaping () -> Void = {}) {
        guard !pending.contains(integration) else { return }
        pending.insert(integration)
        let before = status(for: integration)

        let finish = { [weak self] in
            guard let self else { return }
            self.pending.remove(integration)
            self.refresh()
            if self.status(for: integration) == before {
                self.notes[integration] = Self.unchangedNote(for: integration, status: before)
            }
            completion()
        }

        switch integration {
        case .calendar:
            let store = EKEventStore()
            calendarStore = store
            store.requestFullAccessToEvents { _, _ in
                DispatchQueue.main.async(execute: finish)
            }

        case .location:
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestWhenInUseAuthorization()
            // Authorization arrives via the delegate, which refreshes on its
            // own; this settles the row if the prompt never appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: finish)

        case .music:
            grantMusicAccess(finish: finish)
        }
    }

    /// Whether a player is installed at all, so the UI can offer to install it
    /// rather than asking for permission to automate something absent.
    static func isInstalled(_ provider: MusicProvider) -> Bool {
        guard !provider.bundleID.isEmpty else { return true }
        return NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: provider.bundleID) != nil
    }

    /// Where to get a player that isn't installed.
    static func downloadURL(for provider: MusicProvider) -> URL? {
        switch provider {
        case .spotify: URL(string: "https://www.spotify.com/download/mac/")
        case .appleMusic, .automatic: nil
        }
    }

    /// Launches the chosen player, waits for it to be ready, then addresses it
    /// over Apple Events — which is the only thing that makes macOS show the
    /// Automation prompt.
    ///
    /// The old version fired the Apple Event immediately. If the app was not
    /// already running that call had to launch it and talk to it in one step,
    /// and the event usually timed out against a still-starting app: no
    /// prompt, no error the user could see, and a button that looked dead.
    private func grantMusicAccess(finish: @escaping () -> Void) {
        let provider = NotchSettings.shared.musicProvider
        let target: MusicProvider = provider == .automatic ? .appleMusic : provider

        guard Self.isInstalled(target),
              let url = NSWorkspace.shared
                  .urlForApplication(withBundleIdentifier: target.bundleID)
        else {
            notes[.music] = "\(target.title) isn't installed."
            pending.remove(.music)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            // Give the app a moment to register with Apple Events; asking a
            // process that is still launching is what produced the silence.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.global(qos: .userInitiated).async {
                    let script = NSAppleScript(
                        source: "tell application id \"\(target.bundleID)\" to return name"
                    )
                    var error: NSDictionary?
                    script?.executeAndReturnError(&error)
                    DispatchQueue.main.async(execute: finish)
                }
            }
        }
    }

    /// What to tell the user when a request produced no change at all.
    private static func unchangedNote(for integration: Integration, status: Status) -> String {
        switch integration {
        case .location:
            return status == .notDetermined
                ? "macOS showed no prompt. It only ever offers one per app, and "
                    + "only for a signed build with Location Services switched "
                    + "on — add Notch by hand under Privacy & Security → "
                    + "Location Services."
                : "No change — grant access in Privacy & Security → Location Services."
        case .calendar:
            return "No change — grant access in Privacy & Security → Calendars."
        case .music:
            return "No change yet. If macOS showed no prompt, allow Notch for "
                + "your player under Privacy & Security → Automation."
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
    }
}
