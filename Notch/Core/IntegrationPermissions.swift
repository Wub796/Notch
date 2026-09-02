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
        case accessibility
        case music
        case calendar
        case location
        case screenCapture

        var id: String { rawValue }

        var title: String {
            switch self {
            case .accessibility: "Accessibility"
            case .music: "Music & Player Automation"
            case .calendar: "Calendar"
            case .location: "Location"
            case .screenCapture: "Screen & Audio Recording"
            }
        }

        var systemImage: String {
            switch self {
            case .accessibility: "accessibility"
            case .music: "music.note"
            case .calendar: "calendar"
            case .location: "location.fill"
            case .screenCapture: "waveform.badge.magnifyingglass"
            }
        }

        var detail: String {
            switch self {
            case .accessibility:
                "Enables hardware media key interception, volume/brightness HUDs, and hotkeys."
            case .music:
                "Lets the notch control playback and lyrics across Apple Music and Spotify."
            case .calendar:
                "Shows your schedule, upcoming events, and meeting links."
            case .location:
                "Pins weather forecasts to your current city."
            case .screenCapture:
                "Analyzes audio playback levels for the real-time sound visualizer."
            }
        }

        /// What the app still does when this is not granted — so the pane can
        /// tell the truth about consequences instead of implying breakage.
        var fallbackNote: String {
            switch self {
            case .accessibility:
                "Without it, system media keys and global hotkeys use default macOS routing."
            case .music:
                "Without it, playback still follows whatever is playing — only direct automation needs permission."
            case .calendar:
                "Without it, the schedule stays empty."
            case .location:
                "Without it, weather falls back to an approximate location from your network."
            case .screenCapture:
                "Without it, the notch audio visualizer falls back to animated waveforms."
            }
        }

        var settingsURL: URL? {
            let base = "x-apple.systempreferences:com.apple.preference.security"
            switch self {
            case .accessibility: return URL(string: base + "?Privacy_Accessibility")
            case .music: return URL(string: base + "?Privacy_Automation")
            case .calendar: return URL(string: base + "?Privacy_Calendars")
            case .location: return URL(string: base + "?Privacy_LocationServices")
            case .screenCapture: return URL(string: base + "?Privacy_ScreenCapture")
            }
        }
    }

    /// Current status per integration, refreshed by `refresh()`.
    private(set) var statuses: [Integration: Status] = [:]

    /// Automation status per player. Consent is granted per target app, so
    /// Spotify and Apple Music each get their own row in settings — the
    /// `.music` integration line reports whichever player is selected.
    private(set) var musicStatuses: [MusicProvider: Status] = [:]

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

        statuses[.accessibility] = accessibilityStatus()
        statuses[.calendar] = calendarStatus()
        statuses[.location] = locationStatus()
        statuses[.screenCapture] = screenCaptureStatus()
        refreshMusicStatus()
    }

    private func accessibilityStatus() -> Status {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    private func screenCaptureStatus() -> Status {
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    /// Apple Events authorization is read off the main thread.
    ///
    /// `AEDeterminePermissionToAutomateTarget` blocks, and against an app that
    /// is still launching it can block for many seconds. Calling it from
    /// `refresh()` — which runs on every activation and every time a settings
    /// pane appears — is what froze the app right after it opened Music.
    ///
    /// Automation consent is granted per target app, so each player gets its
    /// own status (surfaced by `musicStatus(for:)`); the `.music` integration
    /// line reports whichever player is currently selected.
    private func refreshMusicStatus() {
        let current = resolvedMusicProvider()

        for provider in [MusicProvider.appleMusic, .spotify] {
            guard Self.isInstalled(provider),
                  !NSRunningApplication
                      .runningApplications(withBundleIdentifier: provider.bundleID).isEmpty
            else {
                musicStatuses[provider] = .unknown
                if provider == current {
                    statuses[.music] = .unknown
                    notes[.music] = "\(provider.title) isn't running — open it to check access."
                }
                continue
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = Self.automationPermission(for: provider.bundleID, askUser: false)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.musicStatuses[provider] = Self.musicStatus(from: result)
                    if provider == current {
                        self.statuses[.music] = self.musicStatuses[provider] ?? .unknown
                        if self.statuses[.music] == .denied {
                            self.notes[.music] = "Enable Notch under Privacy & Security → Automation."
                        }
                    }
                }
            }
        }
    }

    /// Maps an `AEDeterminePermissionToAutomateTarget` result to a status.
    private static func musicStatus(from result: OSStatus) -> Status {
        switch result {
        case noErr: .granted
        case OSStatus(-1743): .denied // errAEEventNotPermitted
        case OSStatus(-600): .unknown // procNotFound
        default: .notDetermined
        }
    }

    /// The player the `.music` integration line reports on. Automatic
    /// resolves to Apple Music, since it is the one that ships with macOS.
    private func resolvedMusicProvider() -> MusicProvider {
        let provider = NotchSettings.shared.musicProvider
        return provider == .automatic ? .appleMusic : provider
    }

    /// Automation status for one specific player — the settings rows for
    /// Spotify and Apple Music each check their own, because consent is
    /// granted per target app, not per feature.
    func musicStatus(for provider: MusicProvider) -> Status {
        musicStatuses[provider] ?? .unknown
    }

    /// Asks macOS whether this app may automate `bundleID`.
    ///
    /// With `askUser` true this is also what *raises* the Automation prompt —
    /// it is the API designed for it. Sending a real Apple Event to provoke
    /// the prompt instead means waiting on the target app's own event loop,
    /// which is unreliable while it is launching.
    ///
    /// Blocks. Never call it on the main thread.
    /// Whether Apple Events to this app are already allowed, asked without
    /// raising the consent dialog. Used before any speculative script — a
    /// background probe at launch must never be what puts a prompt on screen.
    static func isAutomationAllowed(_ bundleID: String) -> Bool {
        automationPermission(for: bundleID, askUser: false) == noErr
    }

    private static func automationPermission(for bundleID: String, askUser: Bool) -> OSStatus {
        guard let data = bundleID.data(using: .utf8) else { return OSStatus(-50) }

        var target = AEAddressDesc()
        // AECreateDesc is one of the older Apple Event calls and still returns
        // OSErr (Int16), where the call below returns OSStatus (Int32).
        let created = data.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return OSStatus(-50) }
            return OSStatus(
                AECreateDesc(DescType(typeApplicationBundleID), base, data.count, &target)
            )
        }
        guard created == noErr else { return created }
        defer { AEDisposeDesc(&target) }

        return AEDeterminePermissionToAutomateTarget(
            &target, DescType(typeWildCard), DescType(typeWildCard), askUser
        )
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
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            if !trusted {
                if let url = integration.settingsURL {
                    // Bring Notch forward first: the accessibility consent
                    // dialog is tied to the requesting app, and macOS only
                    // shows it while that app is frontmost.
                    NSApp.activate(ignoringOtherApps: true)
                    NSWorkspace.shared.open(url)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: finish)

        case .screenCapture:
            NSApp.activate(ignoringOtherApps: true)
            let hasAccess = CGRequestScreenCaptureAccess()
            if !hasAccess {
                if let url = integration.settingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: finish)

        case .calendar:
            let store = EKEventStore()
            calendarStore = store
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { _, _ in
                    DispatchQueue.main.async(execute: finish)
                }
            } else {
                store.requestAccess(to: .event) { _, _ in
                    DispatchQueue.main.async(execute: finish)
                }
            }

        case .location:
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestWhenInUseAuthorization()
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

    /// Launches the currently selected player, waits for it to be ready, then
    /// addresses it over Apple Events — the only thing that makes macOS show
    /// the Automation prompt.
    private func grantMusicAccess(finish: @escaping () -> Void) {
        performMusicGrant(for: resolvedMusicProvider(), finish: finish)
    }

    /// The settings rows' per-player version of `request(.music)`: launches
    /// that exact player (Spotify or Apple Music) and raises its Automation
    /// prompt, then re-reads the status.
    func grantMusicAccess(for provider: MusicProvider) {
        guard !pending.contains(.music) else { return }
        pending.insert(.music)
        let before = musicStatus(for: provider)

        performMusicGrant(for: provider) { [weak self] in
            guard let self else { return }
            self.pending.remove(.music)
            self.refresh()
            if self.musicStatus(for: provider) == before {
                self.notes[.music] = "No change yet. Allow Notch for \(provider.title) "
                    + "under Privacy & Security → Automation."
            }
        }
    }

    /// Shared body for the music grant: open the player if it isn't running,
    /// wait for it to be ready, then call `AEDeterminePermissionToAutomateTarget`
    /// with `askUser` true — which is what puts the macOS Automation prompt
    /// on screen.
    private func performMusicGrant(for provider: MusicProvider, finish: @escaping () -> Void) {
        let target: MusicProvider = provider == .automatic ? .appleMusic : provider

        guard Self.isInstalled(target),
              let url = NSWorkspace.shared
                  .urlForApplication(withBundleIdentifier: target.bundleID)
        else {
            notes[.music] = "\(target.title) isn't installed."
            pending.remove(.music)
            return
        }

        let ask = {
            // The Automation consent dialog is tied to Notch, and macOS only
            // presents it reliably while Notch is the active app. The player
            // was just opened with `activates`, which made *it* frontmost —
            // bring Notch back forward before raising the prompt, or the
            // dialog can appear behind Spotify or fail to surface at all.
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.automationPermission(for: target.bundleID, askUser: true)
                DispatchQueue.main.async(execute: finish)
            }
        }

        // Already running: ask straight away.
        guard NSRunningApplication
            .runningApplications(withBundleIdentifier: target.bundleID).isEmpty
        else {
            ask()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: url, configuration: configuration
        ) { [weak self] _, error in
            DispatchQueue.main.async { [weak self] in
                guard error == nil else {
                    self?.notes[.music] = "Couldn't open \(target.title)."
                    self?.pending.remove(.music)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: ask)
            }
        }
    }

    /// What to tell the user when a request produced no change at all.
    private static func unchangedNote(for integration: Integration, status: Status) -> String {
        switch integration {
        case .accessibility:
            return "Enable Notch in Privacy & Security → Accessibility to unlock all hardware and global controls."
        case .screenCapture:
            return "Enable Notch in Privacy & Security → Screen Recording for real-time sound metering."
        case .location:
            return status == .notDetermined
                ? "macOS showed no prompt — add Notch under Privacy & Security → Location Services."
                : "No change — grant access in Privacy & Security → Location Services."
        case .calendar:
            return "No change — grant access in Privacy & Security → Calendars."
        case .music:
            return "No change yet. Allow Notch for your player under Privacy & Security → Automation."
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
    }
}
