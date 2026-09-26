import AppIntents
import Foundation

/// The mixer's controls, exposed to Shortcuts, Siri and the Action button.
///
/// These are the same operations the notch's own sliders perform — nothing here
/// is a special path. They go through the one `MixerEngine` the app is already
/// running rather than building an engine of their own, and that is
/// load-bearing rather than tidy: the engine taps a process only once it is
/// asked to change that process, and two engines asked to change the same app
/// would each hold a tap on it, with the later tap taking that app's audio away
/// from the earlier one's render callback. One process, one engine, whichever
/// surface asked.

// MARK: - Where an intent finds the app

/// The one place that can hand out this app's running mixer.
///
/// Two callers need it and neither owns it. Intents are constructed by the
/// system, so they cannot be handed the app's state when they are created; the
/// Settings window is a separate window whose panes are built without a
/// `NotchState`. Both the same problem, so both go through here — and both must
/// reach the engine the app already has rather than making another one. The app
/// registers what it owns, at launch.
final class MixerBridge: @unchecked Sendable {
    static let shared = MixerBridge()

    /// Held for the life of the process: the state it comes from is owned by
    /// the app delegate and lives exactly as long, so a weak reference here
    /// would only ever be nil in the window it could not help.
    private var engine: MixerEngine?
    private var monitor: AudioAppMonitor?
    private let lock = NSLock()

    private init() {}

    func register(mixer: MixerEngine, audioApps: AudioAppMonitor) {
        lock.lock()
        engine = mixer
        monitor = audioApps
        lock.unlock()
    }

    var mixer: MixerEngine? {
        lock.lock()
        defer { lock.unlock() }
        return engine
    }

    /// The apps Shortcuts offers, read on the main actor because that is where
    /// the audio monitor writes its list — the same list the notch's own rows
    /// are drawn from, so a shortcut cannot address an app the app cannot see.
    @MainActor
    func knownApps() -> [AudioAppEntity] {
        lock.lock()
        let monitor = self.monitor
        lock.unlock()
        guard let monitor else { return [] }
        return monitor.apps.map { AudioAppEntity(id: $0.id, name: $0.name) }
    }
}

/// One app the mixer can rewrite, as Shortcuts sees it.
struct AudioAppEntity: AppEntity, Equatable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Audio App"
    static let defaultQuery = AudioAppQuery()

    /// The bundle identifier, not a PID: a shortcut is saved and run again
    /// later, and a process id would point at nothing — or at something else —
    /// by then. Settings in the mixer are keyed the same way, for the same
    /// reason.
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Resolves the app list Shortcuts shows in its picker.
struct AudioAppQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AudioAppEntity] {
        let known = await MixerBridge.shared.knownApps()
        // An identifier that is not in the list is handed back as-is rather
        // than dropped: it is an app that is not running now, and the mixer's
        // settings for it are still real and still addressable by bundle id.
        return identifiers.map { identifier in
            known.first { $0.id == identifier }
                ?? AudioAppEntity(id: identifier, name: identifier)
        }
    }

    func suggestedEntities() async throws -> [AudioAppEntity] {
        await MixerBridge.shared.knownApps()
    }
}

/// The built-in EQ curves, as a closed list Shortcuts can offer as a menu.
enum MixerEQPresetChoice: String, AppEnum {
    case flat
    case vocal
    case bass
    case treble
    case podcast
    case night

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Equalizer Preset"

    static let caseDisplayRepresentations: [MixerEQPresetChoice: DisplayRepresentation] = [
        .flat: "Flat",
        .vocal: "Vocal",
        .bass: "Bass",
        .treble: "Treble",
        .podcast: "Podcast",
        .night: "Night",
    ]
}

// MARK: - The shortcuts themselves

/// Sets one app's level, boost included.
struct MixerSetAppVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set App Volume"
    static let description = IntentDescription(
        "Sets one app's own level, without touching the system volume. Above 100% boosts it, up to 400%."
    )

    @Parameter(title: "App")
    var app: AudioAppEntity

    @Parameter(title: "Percent")
    var percent: Int

    func perform() async throws -> some IntentResult {
        let appID = app.id
        let gain = Float(percent) / 100
        await MainActor.run {
            MixerBridge.shared.mixer?.setGain(gain, for: appID)
        }
        return .result()
    }
}

/// Silences or restores one app.
struct MixerMuteAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute App"
    static let description = IntentDescription("Mutes or unmutes one app's audio.")

    @Parameter(title: "App")
    var app: AudioAppEntity

    @Parameter(title: "Muted")
    var muted: Bool

    func perform() async throws -> some IntentResult {
        let appID = app.id
        await MainActor.run {
            guard let mixer = MixerBridge.shared.mixer else { return }
            // The engine's own toggle, applied only when it would change
            // anything, so asking for a state the app is already in is not a
            // write — and a saved shortcut stays idempotent when it re-runs.
            if mixer.mix(for: appID).isMuted != muted {
                mixer.toggleMute(for: appID)
            }
        }
        return .result()
    }
}

/// Applies one of the built-in curves to one app.
struct MixerSetEqualizerIntent: AppIntent {
    static let title: LocalizedStringResource = "Set App Equalizer"
    static let description = IntentDescription(
        "Applies one of the built-in equalizer curves to a single app, or returns it to flat."
    )

    @Parameter(title: "App")
    var app: AudioAppEntity

    @Parameter(title: "Preset")
    var preset: MixerEQPresetChoice

    func perform() async throws -> some IntentResult {
        let appID = app.id
        let presetID = preset.rawValue
        await MainActor.run {
            guard let mixer = MixerBridge.shared.mixer else { return }
            guard EqualizerPreset.preset(for: presetID) != nil else { return }
            mixer.setEqualizer(presetID, bands: nil, for: appID)
        }
        return .result()
    }
}

/// Switches loudness compensation on or off for one app.
struct MixerSetLoudnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Loudness Compensation"
    static let description = IntentDescription(
        "Keeps an app's low end and detail as the output level drops, the way quiet listening loses both."
    )

    @Parameter(title: "App")
    var app: AudioAppEntity

    @Parameter(title: "Enabled")
    var enabled: Bool

    func perform() async throws -> some IntentResult {
        let appID = app.id
        await MainActor.run {
            guard let mixer = MixerBridge.shared.mixer else { return }
            if mixer.mix(for: appID).loudnessCompensation != enabled {
                mixer.setLoudnessCompensation(enabled, for: appID)
            }
        }
        return .result()
    }
}

/// Puts one app back on the system's own path.
struct MixerResetAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset App Audio"
    static let description = IntentDescription(
        "Returns one app to its untouched level and output, and stops processing it at all."
    )

    @Parameter(title: "App")
    var app: AudioAppEntity

    func perform() async throws -> some IntentResult {
        let appID = app.id
        await MainActor.run {
            MixerBridge.shared.mixer?.reset(appID)
        }
        return .result()
    }
}

/// The mixer's master switch, the same one the notch's Mixer row carries.
struct MixerSetEnabledIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Mixer On or Off"
    static let description = IntentDescription(
        "Switches the per-app mixer on or off. Off removes every tap, leaving each app untouched."
    )

    @Parameter(title: "Enabled")
    var enabled: Bool

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            MixerBridge.shared.mixer?.isEnabled = enabled
        }
        return .result()
    }
}

/// Sets the volume of the speakers inside an external display.
struct MixerSetDisplayVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display Speaker Volume"
    static let description = IntentDescription(
        "Sets the speakers built into an external display, over the display's own control channel."
    )

    /// Left optional: with one controllable display the name is noise, and
    /// Shortcuts should not require the user to type it. Empty means the first
    /// display that answers.
    @Parameter(title: "Display")
    var display: String?

    @Parameter(title: "Percent")
    var percent: Int

    func perform() async throws -> some IntentResult {
        let wanted = (display ?? "").lowercased()
        let volume = Float(percent) / 100
        await MainActor.run {
            let controller = DisplayVolumeController.shared
            let displays = controller.controllableDisplays()
            let target = wanted.isEmpty
                ? displays.first
                : displays.first { $0.name.lowercased().contains(wanted) }
            guard let target else { return }
            controller.setVolume(volume, for: target.id)
        }
        return .result()
    }
}
