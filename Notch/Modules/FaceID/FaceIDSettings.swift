import Foundation
import Observation

/// Face ID's own preferences, backed directly by `UserDefaults.standard` —
/// each property's `didSet` writes through immediately, so there is no
/// explicit save step and no way to hold a change that was never persisted.
///
/// Kept apart from `NotchSettings` because none of these are notch
/// preferences: they describe an unlock mechanism, they are the only values
/// this app stores that gate a security decision, and mixing them into the
/// app's general defaults would make both harder to audit. The keys share a
/// `faceID.` prefix for the same reason.
///
/// Ported from Glance (`Settings/GlanceSettings.swift`, MIT © Jonathan Zhou)
/// with the keys re-prefixed and the two properties that don't apply here
/// (onboarding resume, display pinning) removed.
@Observable
final class FaceIDSettings {
    static let shared = FaceIDSettings()

    private enum Key {
        static let isEnabled = "faceID.isEnabled"
        static let matchThreshold = "faceID.matchThreshold"
        static let livenessChecksEnabled = "faceID.livenessChecksEnabled"
        static let livenessMode = "faceID.livenessMode"
        static let minimumFaceWidth = "faceID.minimumFaceWidth"
        static let unlockAnimationStyle = "faceID.unlockAnimationStyle"
        static let showUnlockAnimation = "faceID.showUnlockAnimation"
        static let unlockTriggers = "faceID.unlockTriggers"
        static let retryOnHover = "faceID.retryOnHover"
        static let faceDetectionSeconds = "faceID.faceDetectionSeconds"
        static let autoRetryOnce = "faceID.autoRetryOnce"
        static let hapticFeedbackEnabled = "faceID.hapticFeedbackEnabled"
        static let preferredDisplayID = "faceID.preferredDisplayID"
        static let preferredDisplayName = "faceID.preferredDisplayName"
        static let autoLockIntervalDays = "faceID.autoLockIntervalDays"
        static let defaultCameraID = "faceID.defaultCameraID"
        static let builtInDisplayCameraID = "faceID.builtInDisplayCameraID"
        static let externalDisplayCameraID = "faceID.externalDisplayCameraID"
        static let hasAcknowledgedSetup = "faceID.hasAcknowledgedSetup"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Master switch. Off means no lock/wake arming, no camera, no overlay —
    /// everything in `FaceIDController` is conditioned on this rather than on
    /// each call site remembering to check.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    /// Cosine similarity an enrolled identity must reach to match — see
    /// `FaceRecognitionPipeline.bestMatch(in:threshold:)`. Shares its scale
    /// with the Face ID screen's own test readout, so the number shown when
    /// you try a scan is the number the unlock gate used.
    var matchThreshold: Float {
        didSet { defaults.set(matchThreshold, forKey: Key.matchThreshold) }
    }

    /// Master switch for liveness checking. Off means face recognition alone
    /// decides an unlock — a printed photo of the enrolled user would pass.
    var livenessChecksEnabled: Bool {
        didSet { defaults.set(livenessChecksEnabled, forKey: Key.livenessChecksEnabled) }
    }

    /// Light (deny-only) or Heavy (deny cues plus a required proof of life) —
    /// see `LivenessMode`.
    var livenessMode: LivenessMode {
        didSet { defaults.set(livenessMode.rawValue, forKey: Key.livenessMode) }
    }

    /// Below this fraction of the frame's width, a face is a bystander rather
    /// than a candidate. Mirrored into `FaceRecognitionPipeline` on every
    /// change because that value is read from background work.
    var minimumFaceWidth: Float {
        didSet {
            defaults.set(minimumFaceWidth, forKey: Key.minimumFaceWidth)
            FaceRecognitionPipeline.minimumProminentFaceWidth = minimumFaceWidth
        }
    }

    /// The remembered pick (`.minimal`/`.original` only). `showUnlockAnimation`
    /// tracks on/off separately, so switching back on restores the prior pick.
    /// Read `effectiveUnlockAnimationStyle` to decide what to actually show.
    var unlockAnimationStyle: UnlockAnimationStyle {
        didSet { defaults.set(unlockAnimationStyle.rawValue, forKey: Key.unlockAnimationStyle) }
    }

    var showUnlockAnimation: Bool {
        didSet { defaults.set(showUnlockAnimation, forKey: Key.showUnlockAnimation) }
    }

    /// What the overlay should actually render — the pick, or `.none` when
    /// animations are switched off entirely.
    var effectiveUnlockAnimationStyle: UnlockAnimationStyle {
        showUnlockAnimation ? unlockAnimationStyle : .none
    }

    /// Which signals arm Face ID. Persisted as raw-value strings; the setter
    /// refuses to store an empty set, since a Mac with none armed would never
    /// show the notch at all.
    var unlockTriggers: Set<UnlockTrigger> {
        didSet {
            // Belt and braces behind the picker's own min-one rule. This
            // reassignment re-enters didSet once, then terminates, because the
            // corrected value is never itself empty.
            if unlockTriggers.isEmpty {
                unlockTriggers = oldValue.isEmpty ? Set(UnlockTrigger.allCases) : oldValue
            }
            defaults.set(unlockTriggers.map(\.rawValue), forKey: Key.unlockTriggers)
        }
    }

    /// Whether hovering a failed scan retries it.
    var retryOnHover: Bool {
        didSet { defaults.set(retryOnHover, forKey: Key.retryOnHover) }
    }

    /// How long each scan cycle looks for a face before giving up. Shared with
    /// `FaceIDOverlayController.scanTimeoutDuration` so the background loop and
    /// the panel's own timeout expire together.
    var faceDetectionSeconds: Int {
        didSet {
            // Only reassign when clamping actually changes the value —
            // unconditional reassignment would recurse forever, since the
            // slider only ever produces in-range values.
            let clamped = min(max(faceDetectionSeconds, Self.faceDetectionRange.lowerBound),
                              Self.faceDetectionRange.upperBound)
            guard clamped == faceDetectionSeconds else {
                faceDetectionSeconds = clamped
                return
            }
            defaults.set(faceDetectionSeconds, forKey: Key.faceDetectionSeconds)
        }
    }

    static let faceDetectionRange = 3...10

    /// One automatic retry per lock session when the first scan fails. One
    /// shot, because an auto-retry that could itself auto-retry would keep the
    /// camera on for the whole lock session.
    var autoRetryOnce: Bool {
        didSet { defaults.set(autoRetryOnce, forKey: Key.autoRetryOnce) }
    }

    /// Trackpad haptic on hovering the notch and on a successful unlock.
    var hapticFeedbackEnabled: Bool {
        didSet { defaults.set(hapticFeedbackEnabled, forKey: Key.hapticFeedbackEnabled) }
    }

    /// Which display Face ID shows on. `nil` follows `FaceIDGeometry`'s own
    /// default (a notched display, else the main one); a pinned display has
    /// deliberately no fallback if it goes away.
    var preferredDisplayID: String? {
        didSet { defaults.set(preferredDisplayID, forKey: Key.preferredDisplayID) }
    }

    /// The chosen display's name at pick time — cosmetic only, so the row can
    /// show something recognizable while that display is disconnected.
    var preferredDisplayName: String? {
        didSet { defaults.set(preferredDisplayName, forKey: Key.preferredDisplayName) }
    }

    /// Enforced by `FaceIDSessionAutoLocker`, not stored and checked here.
    var autoLockInterval: AutoLockInterval {
        didSet { defaults.set(autoLockInterval.rawValue, forKey: Key.autoLockIntervalDays) }
    }

    /// Device `uniqueID`s rather than device objects: devices disconnect and
    /// reconnect between launches, but their unique ID is stable.
    var defaultCameraID: String? {
        didSet { defaults.set(defaultCameraID, forKey: Key.defaultCameraID) }
    }

    var builtInDisplayCameraID: String? {
        didSet { defaults.set(builtInDisplayCameraID, forKey: Key.builtInDisplayCameraID) }
    }

    var externalDisplayCameraID: String? {
        didSet { defaults.set(externalDisplayCameraID, forKey: Key.externalDisplayCameraID) }
    }

    /// Gates the one-time warning the Face ID screen shows before the feature
    /// can be switched on: this is a convenience, not a security upgrade, and
    /// the stored password is typed into the lock screen on its behalf.
    var hasAcknowledgedSetup: Bool {
        didSet { defaults.set(hasAcknowledgedSetup, forKey: Key.hasAcknowledgedSetup) }
    }

    private init() {
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? false
        // 0.66 is Glance's validated default for the ArcFace model in this
        // repo — comfortably above the ~0.28-0.40 textbook cutoffs, which were
        // tuned for pristine datasets rather than a laptop webcam at an angle.
        matchThreshold = defaults.object(forKey: Key.matchThreshold) as? Float ?? 0.66
        livenessChecksEnabled = defaults.object(forKey: Key.livenessChecksEnabled) as? Bool ?? true
        // Light by default: Heavy wants a blink or a real head turn, which a
        // still, unblinking user may never produce — while Light still catches
        // the main attack, a photo held up to the camera.
        livenessMode = defaults.string(forKey: Key.livenessMode)
            .flatMap(LivenessMode.init(rawValue:)) ?? .light
        minimumFaceWidth = defaults.object(forKey: Key.minimumFaceWidth) as? Float ?? 0.21

        let storedStyle = defaults.string(forKey: Key.unlockAnimationStyle)
            .flatMap(UnlockAnimationStyle.init(rawValue:)) ?? .original
        unlockAnimationStyle = storedStyle == .none ? .original : storedStyle
        showUnlockAnimation = defaults.object(forKey: Key.showUnlockAnimation) as? Bool
            ?? (storedStyle != .none)

        let storedTriggers = (defaults.array(forKey: Key.unlockTriggers) as? [String])?
            .compactMap(UnlockTrigger.init(rawValue:))
        // Wake and lock by default, not space: `.onSpace` needs Input
        // Monitoring, which a fresh install should not request unprompted.
        unlockTriggers = storedTriggers.map(Set.init).flatMap { $0.isEmpty ? nil : $0 }
            ?? [.onWake, .onLock]
        retryOnHover = defaults.object(forKey: Key.retryOnHover) as? Bool ?? true
        faceDetectionSeconds = (defaults.object(forKey: Key.faceDetectionSeconds) as? Int)
            .map { min(max($0, Self.faceDetectionRange.lowerBound), Self.faceDetectionRange.upperBound) }
            ?? 5
        autoRetryOnce = defaults.object(forKey: Key.autoRetryOnce) as? Bool ?? false
        hapticFeedbackEnabled = defaults.object(forKey: Key.hapticFeedbackEnabled) as? Bool ?? true
        preferredDisplayID = defaults.string(forKey: Key.preferredDisplayID)
        preferredDisplayName = defaults.string(forKey: Key.preferredDisplayName)
        // A week: long enough not to nag daily users, short enough not to leave
        // an abandoned session live indefinitely.
        autoLockInterval = (defaults.object(forKey: Key.autoLockIntervalDays) as? Int)
            .flatMap(AutoLockInterval.init(rawValue:)) ?? .sevenDays
        defaultCameraID = defaults.string(forKey: Key.defaultCameraID)
        builtInDisplayCameraID = defaults.string(forKey: Key.builtInDisplayCameraID)
        externalDisplayCameraID = defaults.string(forKey: Key.externalDisplayCameraID)
        hasAcknowledgedSetup = defaults.object(forKey: Key.hasAcknowledgedSetup) as? Bool ?? false

        // Push into the pipeline's mirror immediately, or it would keep its own
        // default until the slider is first touched.
        FaceRecognitionPipeline.minimumProminentFaceWidth = minimumFaceWidth
    }
}

/// How long the Touch-ID-unlocked session may sit idle before it re-locks.
///
/// The unit is days because that is the honest scale of the decision: this key
/// is what decrypts the stored password and the face templates, and every
/// interval here is long enough that the session is effectively "unlocked
/// until you stop using the Mac for a while".
enum AutoLockInterval: Int, CaseIterable, Identifiable {
    case oneDay = 1
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    var id: Int { rawValue }

    var title: String { rawValue == 1 ? "1 day" : "\(rawValue) days" }

    var duration: TimeInterval { TimeInterval(rawValue) * 24 * 60 * 60 }

    /// Position in `allCases`, driving the discrete four-stop slider.
    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> AutoLockInterval {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .sevenDays
    }
}

/// The success/failure animation shown in the notch.
enum UnlockAnimationStyle: String, CaseIterable, Identifiable {
    /// No panel at all. Still a valid stored value, but now produced by the
    /// "Show animation" toggle rather than offered as a tile.
    case none
    /// The notch widens to reveal a lock glyph and the scan video; see
    /// `FaceIDMinimalUnlockView`.
    case minimal
    /// The notch expands into the full square scan panel.
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .minimal: "Minimal"
        case .original: "Original"
        }
    }

    /// What the picker offers. `.none` is deliberately absent — it is what the
    /// on/off toggle produces.
    static let selectableCases: [UnlockAnimationStyle] = [.minimal, .original]
}

/// What can prompt a scan. Multi-select, and at least one is always kept
/// selected: a Mac with none armed would never show the notch.
enum UnlockTrigger: String, CaseIterable, Identifiable {
    /// The display turned back on — see `LockEventKind.wake`.
    case onWake
    /// The screen just became locked, no wake involved.
    case onLock
    /// Pressing the space bar on the lock screen starts a scan. The lock
    /// screen's Secure Event Input blocks ordinary event taps, so this is read
    /// through IOKit HID instead (see `SpaceKeyMonitor`).
    case onSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onWake: "On wake"
        case .onLock: "On lock"
        case .onSpace: "On space"
        }
    }

    var iconName: String {
        switch self {
        case .onWake: "moon.fill"
        case .onLock: "lock.laptopcomputer"
        case .onSpace: "space"
        }
    }

    var explanation: String {
        switch self {
        case .onWake: "The display comes back on, from sleep or the screensaver."
        case .onLock: "The screen is locked while it is already awake."
        case .onSpace: "Space is pressed at the lock screen. Needs Input Monitoring."
        }
    }
}
