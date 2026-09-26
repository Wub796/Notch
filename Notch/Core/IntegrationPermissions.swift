import AppKit
import AVFoundation
import CoreBluetooth
import CoreLocation
import SwiftUI
import EventKit
import Foundation
import Observation
import UserNotifications

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

    /// Every permission Notch can need, in the order System Settings lists
    /// them — a permission the user has already met there is in the same
    /// relative place here, which is half of what makes a privacy page
    /// trustworthy.
    enum Integration: String, CaseIterable, Identifiable {
        case accessibility
        case screenCapture
        case filesAndFolders
        case music
        case location
        case calendar
        case camera
        case bluetooth
        case notifications

        var id: String { rawValue }

        var title: String {
            switch self {
            case .accessibility: "Accessibility"
            case .screenCapture: "Screen & Audio Recording"
            case .filesAndFolders: "Files & Folders"
            case .music: "Music & Player Automation"
            case .location: "Location"
            case .calendar: "Calendar"
            case .camera: "Camera"
            case .bluetooth: "Bluetooth"
            case .notifications: "Notifications"
            }
        }

        var systemImage: String {
            switch self {
            case .accessibility: "accessibility"
            case .screenCapture: "waveform.badge.magnifyingglass"
            case .filesAndFolders: "folder"
            case .music: "music.note"
            case .location: "location.fill"
            case .calendar: "calendar"
            case .camera: "video.fill"
            case .bluetooth: "antenna.radiowaves.left.and.right"
            case .notifications: "bell.badge.fill"
            }
        }

        var detail: String {
            switch self {
            case .accessibility:
                "Enables hardware media key interception, volume/brightness HUDs, hotkeys, and "
                    + "letting Face ID type your password at the lock screen."
            case .screenCapture:
                "Not used to capture your screen: Notch never records pixels, so "
                    + "this row mirrors the system's own record rather than a "
                    + "request it makes. The part that matters is audio access, "
                    + "which the real-time visualizer and per-app volume use to "
                    + "read the output mix through a CoreAudio tap."
            case .filesAndFolders:
                "Lets the notch catch finished downloads and new screenshots as they land."
            case .music:
                "Lets the notch control playback and lyrics across Apple Music and Spotify."
            case .location:
                "Pins weather forecasts to your current city."
            case .calendar:
                "Shows your schedule, upcoming events, and meeting links."
            case .camera:
                "Shows a live preview on the camera screen while it is open, and reads your face "
                    + "during a Face ID scan. Frames are processed in memory and never written to disk."
            case .bluetooth:
                "Lists your paired audio accessories, with battery levels."
            case .notifications:
                "Lets a finished timer reach you when the notch is closed."
            }
        }

        /// What the app still does when this is not granted — so the pane can
        /// tell the truth about consequences instead of implying breakage.
        var fallbackNote: String {
            switch self {
            case .accessibility:
                "Without it, system media keys and global hotkeys use default macOS routing."
            case .screenCapture:
                "Without it, the visualizer's bars follow the output volume instead "
                    + "of the music's own three frequency ranges, and per-app volume "
                    + "cannot take an app over."
            case .filesAndFolders:
                "Without it, files you drop on the notch still work; arrivals in those "
                    + "folders are not announced."
            case .music:
                "Without it, the notch still controls playback through the system's "
                    + "now-playing channel, and only follows what is playing — grant this "
                    + "to drive the player directly instead."
            case .location:
                "Without it, weather falls back to an approximate location from your network."
            case .calendar:
                "Without it, the schedule stays empty."
            case .camera:
                "Without it, the camera screen stays empty — the device is never opened "
                    + "speculatively."
            case .bluetooth:
                "Without it, paired accessories are still listed, without names or levels."
            case .notifications:
                "Without it, a finished timer is shown in the notch only."
            }
        }

        var settingsURL: URL? {
            let base = "x-apple.systempreferences:com.apple.preference.security"
            switch self {
            case .accessibility: return URL(string: base + "?Privacy_Accessibility")
            case .screenCapture: return URL(string: base + "?Privacy_ScreenCapture")
            case .filesAndFolders: return URL(string: base + "?Privacy_FilesAndFolders")
            case .music: return URL(string: base + "?Privacy_Automation")
            case .location: return URL(string: base + "?Privacy_LocationServices")
            case .calendar: return URL(string: base + "?Privacy_Calendars")
            case .camera: return URL(string: base + "?Privacy_Camera")
            case .bluetooth: return URL(string: base + "?Privacy_Bluetooth")
            // Notifications are their own extension rather than a Privacy pane
            // in System Settings, so they carry their own identifier.
            case .notifications:
                return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
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

    /// Held only for the moment the Bluetooth prompt is raised. Nothing scans,
    /// connects, or stays open: creating the manager is the prompt, and it is
    /// released as soon as the answer lands.
    private var bluetoothPrompt: CBCentralManager?

    private override init() {
        super.init()
        locationManager.delegate = self
        refresh()
    }

    func status(for integration: Integration) -> Status {
        statuses[integration] ?? .unknown
    }

    /// Whether macOS can still put its own prompt on screen for this one.
    ///
    /// Consent is asked for once per app and permission. While the answer is
    /// still open the prompt is ours to raise; once macOS has recorded a
    /// decision, asking again is silent — so the pane changes what its button
    /// does rather than firing a request that can no longer happen.
    func canPrompt(for integration: Integration) -> Bool {
        switch status(for: integration) {
        case .notDetermined, .unknown: true
        case .granted, .denied: false
        }
    }

    /// Takes the user to the exact pane that can change `integration`.
    func openSettings(for integration: Integration) {
        guard let url = integration.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Refresh

    /// - Parameter probeFolders: whether to check access to the folders the
    ///   file catcher watches. Reading one is the only way to learn whether
    ///   macOS is blocking it, and a read is also the one check here that can
    ///   raise a consent prompt — so it is reserved for the permissions pane,
    ///   never part of the routine refresh that runs at launch.
    func refresh(probeFolders: Bool = false) {
        // Notes describe the most recent attempt, so a fresh read clears them
        // before anything re-states its own.
        notes.removeAll()

        statuses[.accessibility] = accessibilityStatus()
        statuses[.calendar] = calendarStatus()
        statuses[.location] = locationStatus()
        statuses[.screenCapture] = screenCaptureStatus()
        statuses[.camera] = cameraStatus()
        statuses[.bluetooth] = bluetoothStatus()
        refreshNotificationStatus()
        if probeFolders {
            refreshFolderAccess()
        } else if statuses[.filesAndFolders] == nil {
            statuses[.filesAndFolders] = .unknown
        }
        refreshMusicStatus()
    }

    /// Whether we have ever put the system prompt for `integration` on screen.
    ///
    /// Neither `AXIsProcessTrusted` nor `CGPreflightScreenCaptureAccess` can
    /// tell "never asked" from "asked and refused" — both just answer false.
    /// Remembering the ask is the only way to stop the pane reporting a firm
    /// denial as "Not requested" forever.
    private static func hasRequested(_ integration: Integration) -> Bool {
        UserDefaults.standard.bool(forKey: "requested.\(integration.rawValue)")
    }

    private static func markRequested(_ integration: Integration) {
        UserDefaults.standard.set(true, forKey: "requested.\(integration.rawValue)")
    }

    private func accessibilityStatus() -> Status {
        if AXIsProcessTrusted() { return .granted }
        return Self.hasRequested(.accessibility) ? .denied : .notDetermined
    }

    private func screenCaptureStatus() -> Status {
        if CGPreflightScreenCaptureAccess() { return .granted }
        return Self.hasRequested(.screenCapture) ? .denied : .notDetermined
    }

    /// Read without opening the device, so the pane can report the camera's
    /// state — and the hardware light stays off while it does.
    private func cameraStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    /// `CBManager.authorization` answers without a manager, which matters:
    /// creating one while the answer is still open is itself the prompt.
    private func bluetoothStatus() -> Status {
        switch CBManager.authorization {
        case .allowedAlways: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    /// Notification consent is read asynchronously, so the row keeps whatever
    /// it had until the real answer lands rather than flickering to Unknown.
    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status: Status
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: status = .granted
            case .denied: status = .denied
            case .notDetermined: status = .notDetermined
            @unknown default: status = .unknown
            }
            DispatchQueue.main.async { self?.statuses[.notifications] = status }
        }
    }

    /// Whether Notch can read the folders it watches for arriving files.
    ///
    /// macOS has no preflight call for these, so the check is a real listing of
    /// the same two folders the file catcher uses. A folder that does not exist
    /// is skipped rather than counted as blocked: on a Mac with screenshots
    /// moved elsewhere, the default Desktop path is simply absent.
    private func refreshFolderAccess(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var folders: [URL] = []
            for folder in [FileCatcher.downloadsFolder, FileCatcher.screenshotFolder] {
                guard let folder else { continue }
                let standardized = folder.standardizedFileURL
                if !folders.contains(standardized) { folders.append(standardized) }
            }

            var blocked = false
            for folder in folders {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                      isDirectory.boolValue
                else { continue }
                if (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) == nil {
                    blocked = true
                }
            }

            let status: Status = blocked
                ? (Self.hasRequested(.filesAndFolders) ? .denied : .notDetermined)
                : .granted
            DispatchQueue.main.async {
                guard let self else { return }
                self.statuses[.filesAndFolders] = status
                if status == .denied {
                    self.notes[.filesAndFolders] = "macOS is blocking "
                        + "\(folders.map(\.lastPathComponent).joined(separator: " and ")) "
                        + "for Notch."
                }
                completion?()
            }
        }
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

    /// Whether Apple Events to this app are already allowed, asked without
    /// raising the consent dialog. Used before any speculative script — a
    /// background probe at launch must never be what puts a prompt on screen.
    ///
    /// **Never blocks, and the answer is the last one looked up.** The call
    /// behind it, `AEDeterminePermissionToAutomateTarget`, blocks until tccd
    /// answers — and while an Automation prompt for this app is pending, tccd
    /// does not answer at all. It used to be called straight from the main
    /// thread (every track change, via `refreshShuffleAndFavorite`), which
    /// froze the whole notch: no hover, no clicks, no timers, and no way back
    /// short of answering a prompt that a background agent may never surface.
    /// See `AutomationConsent`, which now owns the lookup.
    static func isAutomationAllowed(_ bundleID: String) -> Bool {
        AutomationConsent.shared.isAllowed(bundleID)
    }

    /// Asks macOS whether this app may automate `bundleID`.
    ///
    /// `fileprivate` rather than `private`: `AutomationConsent` below is the
    /// only caller left, and it must not live inside this type's cache.
    ///
    /// With `askUser` true this is also what *raises* the Automation prompt —
    /// it is the API designed for it. Sending a real Apple Event to provoke
    /// the prompt instead means waiting on the target app's own event loop,
    /// which is unreliable while it is launching.
    ///
    /// Blocks. Never call it on the main thread, and never on a queue that
    /// carries the user's scripting: a pending prompt holds it for as long as
    /// that prompt is on screen.
    fileprivate static func automationPermission(for bundleID: String, askUser: Bool) -> OSStatus {
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

        // A decision macOS has already recorded cannot be asked again — the
        // prompt is shown once per app and permission, and every call after
        // that is silent. Opening the pane that owns the switch is then the
        // only thing that can change the answer, and it is what this row's
        // button promises in that state.
        guard canPrompt(for: integration) else {
            openSettings(for: integration)
            completion()
            return
        }

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
            Self.markRequested(.accessibility)
            // The alert macOS raises here *is* the prompt: it explains the ask
            // and offers to open the pane that grants it. Nothing is opened by
            // us first — sending the user to System Settings on their click is
            // the detour this replaces. Bring Notch forward, because the dialog
            // is tied to the requesting app and only shows while it is
            // frontmost.
            NSApp.activate(ignoringOtherApps: true)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            // This one is granted out of band, in System Settings — there is no
            // callback. A fixed 1.2s wait finished long before anyone could
            // click anything, so the pane always concluded "nothing moved".
            awaitGrant(integration, finish: finish)

        case .screenCapture:
            Self.markRequested(.screenCapture)
            NSApp.activate(ignoringOtherApps: true)
            // Raises the system's own screen-recording prompt. It answers
            // false while the answer is still pending, so the grant is awaited
            // below rather than concluded from the return value.
            _ = CGRequestScreenCaptureAccess()
            awaitGrant(integration, finish: finish)

        case .filesAndFolders:
            Self.markRequested(.filesAndFolders)
            // No prompt API exists for these folders: macOS asks the first time
            // the app actually reads one, so the request *is* a read of the
            // folders the file catcher already watches.
            refreshFolderAccess { finish() }

        case .camera:
            Self.markRequested(.camera)
            NSApp.activate(ignoringOtherApps: true)
            // The system prompt, from the only API that raises it. The device
            // is never opened to find out: `authorizationStatus` answered that
            // already.
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async(execute: finish)
            }

        case .bluetooth:
            Self.markRequested(.bluetooth)
            NSApp.activate(ignoringOtherApps: true)
            // Bluetooth has no request call — the prompt is raised by creating
            // a central manager while the answer is still open. It is told not
            // to scan, connect, or raise a power alert, held just long enough
            // for the answer to register, then released.
            bluetoothPrompt = CBCentralManager(
                delegate: nil,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.bluetoothPrompt = nil
                finish()
            }

        case .notifications:
            Self.markRequested(.notifications)
            NSApp.activate(ignoringOtherApps: true)
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]
            ) { _, _ in
                DispatchQueue.main.async(execute: finish)
            }

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
            // The user pressed Grant, so pulling focus is what they asked for:
            // macOS attaches the prompt to the frontmost app.
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestWhenInUseAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: finish)

        case .music:
            grantMusicAccess(finish: finish)
        }
    }

    /// Waits for an out-of-band grant (System Settings) to land.
    ///
    /// Re-reads the real status roughly once a second and finishes the moment
    /// it changes, giving up after `timeout`. The row stays in its pending
    /// state meanwhile, which is the honest thing to show while the user is
    /// off in System Settings.
    private func awaitGrant(
        _ integration: Integration,
        timeout: TimeInterval = 45,
        finish: @escaping () -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let before = status(for: integration)

        func poll() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                let now: Status = integration == .accessibility
                    ? self.accessibilityStatus()
                    : self.screenCaptureStatus()
                if now != before || Date() >= deadline {
                    finish()
                } else {
                    poll()
                }
            }
        }
        poll()
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
            return "Enable Notch under Privacy & Security → Screen & System Audio Recording "
                + "(Screen Recording on older macOS) for real-time sound metering."
        case .filesAndFolders:
            return "Allow Notch for these folders under Privacy & Security → Files and Folders."
        case .camera:
            return "Add Notch under Privacy & Security → Camera."
        case .bluetooth:
            return "Add Notch under Privacy & Security → Bluetooth."
        case .notifications:
            return "Turn notifications on for Notch in System Settings → Notifications."
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

/// The non-blocking half of the Apple Events consent check.
///
/// Consent is asked for once per target app, on a queue of its own, and the
/// answer is cached; every caller reads the cache. Two properties matter and
/// both are load-bearing:
///
/// - **No caller ever waits.** This is asked on the main thread, on the
///   scripting queue, and from the media probe. The underlying call blocks
///   while an Automation prompt is unanswered, so a synchronous version takes
///   whichever of those asked down with it — on the main thread that is the
///   entire notch.
/// - **An unanswered target reads as "not allowed".** That is the safe
///   answer: it is what stops a speculative Apple Event from being the thing
///   that puts a prompt on screen. It costs at most the first moment after
///   launch, and the real answer replaces it as soon as it lands.
///
/// A lookup that hangs is never retried: the in-flight marker stays set, so a
/// stuck tccd costs one parked worker instead of one per caller.
private final class AutomationConsent {
    static let shared = AutomationConsent()

    /// How long an answer is trusted before it is looked up again, so a grant
    /// made in System Settings lands without a relaunch. A target whose lookup
    /// is still in flight keeps its old answer regardless of age.
    private static let ttl: TimeInterval = 30

    private let lock = NSLock()
    private var answers: [String: (allowed: Bool, checked: Date)] = [:]
    private var lookupsInFlight: Set<String> = []

    /// Deliberately not `com.notch.applescript`: one hung lookup on that serial
    /// queue would take every script behind it with it.
    private let queue = DispatchQueue(label: "com.notch.automation-consent", qos: .utility)

    func isAllowed(_ bundleID: String) -> Bool {
        lock.lock()
        let answer = answers[bundleID]
        let stale = answer.map { Date().timeIntervalSince($0.checked) >= Self.ttl } ?? true
        let shouldLook = stale && !lookupsInFlight.contains(bundleID)
        if shouldLook { lookupsInFlight.insert(bundleID) }
        lock.unlock()

        if shouldLook {
            queue.async {
                let allowed = IntegrationPermissions.automationPermission(
                    for: bundleID, askUser: false
                ) == noErr
                self.lock.lock()
                self.answers[bundleID] = (allowed, Date())
                self.lookupsInFlight.remove(bundleID)
                self.lock.unlock()
            }
        }

        return answer?.allowed ?? false
    }
}
