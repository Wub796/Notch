import AppKit
import CoreLocation
import CoreServices
import EventKit
import Foundation

enum IntegrationPermissions {
    enum Status: String {
        case undetermined
        case granted
        case denied

        var title: String {
            switch self {
            case .undetermined: return "Not requested"
            case .granted: return "Granted"
            case .denied: return "Denied"
            }
        }
    }

    private static let musicGrantedKey = "musicAutomationGranted"

    private static var locationRequester: LocationRequester?
    private static var calendarStore: EKEventStore?

    private final class LocationRequester: NSObject, CLLocationManagerDelegate {
        private let manager = CLLocationManager()
        private var completion: (() -> Void)?

        func request(completion: @escaping () -> Void) {
            self.completion = completion
            NSApp.activate(ignoringOtherApps: true)

            if manager.authorizationStatus != .notDetermined {
                finish()
                return
            }

            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            if manager.authorizationStatus != .notDetermined {
                finish()
            }
        }

        private func finish() {
            let comp = completion
            completion = nil
            DispatchQueue.main.async {
                comp?()
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
            case .music: return "Music control"
            case .calendar: return "Calendar"
            case .location: return "Weather location"
            }
        }

        var systemImage: String {
            switch self {
            case .music: return "music.note"
            case .calendar: return "calendar"
            case .location: return "location.fill"
            }
        }

        var detail: String {
            switch self {
            case .music: return "Lets the notch play, pause, and skip in Apple Music or Spotify."
            case .calendar: return "Shows your schedule and upcoming meetings in the notch."
            case .location: return "Fetches the weather shown in the compact and dashboard widgets."
            }
        }

        var status: Status {
            switch self {
            case .music:
                return checkMusicStatus()
            case .calendar:
                switch EKEventStore.authorizationStatus(for: .event) {
                case .fullAccess, .authorized:
                    return .granted
                case .denied, .restricted:
                    return .denied
                default:
                    return .undetermined
                }
            case .location:
                switch CLLocationManager().authorizationStatus {
                case .authorized, .authorizedAlways, .authorizedWhenInUse:
                    return .granted
                case .denied, .restricted:
                    return .denied
                default:
                    return .undetermined
                }
            }
        }

        private func checkMusicStatus() -> Status {
            let isGranted = UserDefaults.standard.bool(forKey: IntegrationPermissions.musicGrantedKey)

            let provider = NotchSettings.shared.musicProvider
            let bundleID = (provider == .spotify) ? "com.spotify.client" : "com.apple.Music"

            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
                return isGranted ? .granted : .undetermined
            }

            guard let data = bundleID.data(using: .utf8) else {
                return isGranted ? .granted : .undetermined
            }

            var targetDesc = AEDesc()
            let createStatus = (data as NSData).bytes.withMemoryRebound(to: UInt8.self, capacity: data.count) { ptr in
                AECreateDesc(
                    DescType(typeApplicationBundleID), // typeApplicationBundleID is 4 chars, bundleId string
                    ptr,
                    data.count,
                    &targetDesc
                )
            }

            if createStatus == noErr {
                let authStatus = AEDeterminePermissionToAutomateTarget(
                    &targetDesc,
                    DescType(typeWildCard),
                    DescType(typeWildCard),
                    false
                )
                AEDisposeDesc(&targetDesc)

                switch authStatus {
                case noErr:
                    if !isGranted {
                        UserDefaults.standard.set(true, forKey: IntegrationPermissions.musicGrantedKey)
                    }
                    return .granted
                                case -1743: // errAEEventNotPermitted
                    if isGranted {
                        UserDefaults.standard.set(false, forKey: IntegrationPermissions.musicGrantedKey)
                    }
                    return .denied
                default:
                    break
                }
            }

            return isGranted ? .granted : .undetermined
        }

        var settingsURL: URL? {
            let base = "x-apple.systempreferences:com.apple.preference.security"
            switch self {
            case .music: return URL(string: base + "?Privacy_Automation")
            case .calendar: return URL(string: base + "?Privacy_Calendars")
            case .location: return URL(string: base + "?Privacy_LocationServices")
            }
        }

        func request(_ completion: @escaping () -> Void) {
            NSApp.activate(ignoringOtherApps: true)

            switch self {
            case .music:
                let provider = NotchSettings.shared.musicProvider
                let appName = provider.appleScriptAppName ?? "Music"

                DispatchQueue.global(qos: .userInitiated).async {
                    let script = NSAppleScript(source: "tell application \"\(appName)\" to get name")
                    var error: NSDictionary?
                    script?.executeAndReturnError(&error)

                    DispatchQueue.main.async {
                        let granted = error == nil
                        if granted {
                            UserDefaults.standard.set(true, forKey: IntegrationPermissions.musicGrantedKey)
                        }
                        completion()
                    }
                }

            case .calendar:
                let store = EKEventStore()
                IntegrationPermissions.calendarStore = store

                let finish: () -> Void = {
                    DispatchQueue.main.async {
                        IntegrationPermissions.calendarStore = nil
                        completion()
                    }
                }

                if #available(macOS 14.0, *) {
                    store.requestFullAccessToEvents { _, _ in finish() }
                } else {
                    store.requestAccess(to: .event) { _, _ in finish() }
                }

            case .location:
                let requester = LocationRequester()
                IntegrationPermissions.locationRequester = requester
                requester.request {
                    IntegrationPermissions.locationRequester = nil
                    completion()
                }
            }
        }
    }
}
