import SwiftUI

/// One screen of the first-run flow.
///
/// `IntegrationPermissions.Integration` stays in System Settings order, because
/// that is what Settings → Privacy mirrors and where someone returns looking
/// for a row. The flow is a different thing: it leads with what is instant and
/// immediately visible, and leaves the two asks that send the user off to
/// System Settings for the end — where the easy grants have already paid for
/// the trip.
enum OnboardingStep: Hashable, Identifiable {
    case welcome
    case ask(IntegrationPermissions.Integration)
    case ready

    static let askOrder: [IntegrationPermissions.Integration] = [
        .calendar, .location, .music, .notifications, .camera,
        .bluetooth, .filesAndFolders, .screenCapture, .accessibility,
    ]

    static let all: [OnboardingStep] = [.welcome] + askOrder.map(OnboardingStep.ask) + [.ready]

    /// `Identifiable` so the container can hand each screen its own identity —
    /// that identity is what makes SwiftUI trade one step for the next with a
    /// transition instead of mutating a single view in place.
    var id: Self { self }

    var tint: Color {
        switch self {
        case .welcome: .white
        case let .ask(integration): integration.tint
        case .ready: OnboardingVerdict.grantedInk
        }
    }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case let .ask(integration): integration.title
        case .ready: "Ready"
        }
    }

    var integration: IntegrationPermissions.Integration? {
        guard case let .ask(integration) = self else { return nil }
        return integration
    }
}

/// The flow's own motion.
///
/// Kept beside the flow rather than in `NotchAnimations`: those springs
/// describe a notch that can be grabbed and reversed mid-flight, while these
/// describe screens replacing each other. The shape is the prototype's — in on
/// an ease-out, out on a quicker ease-in, travel in the direction of travel —
/// with one deliberate change: the screen's own travel is smaller than the
/// prototype's, because the parts inside it now arrive in order, and two
/// motions pushing the same direction read as wobble rather than as momentum.
enum OnboardingMotion {
    static var prefersReducedMotion: Bool { NotchAnimations.prefersReducedMotion }

    // MARK: Coming and going

    /// The screen itself. Shorter than a page turn on purpose: the character of
    /// an entrance belongs to the parts inside the screen (`OnboardingReveal`),
    /// and two motions pushing the same direction add up into wobble.
    static var stepIn: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .timingCurve(0.23, 1, 0.32, 1, duration: 0.26)
    }

    /// Out is quicker than in, always: it is the half nobody is watching.
    static var stepOut: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .timingCurve(0.32, 0.72, 0, 1, duration: 0.16)
    }

    /// How far the screen itself travels. Enough to say "onward", little
    /// enough that the arrival is the parts, not the page.
    static let stepTravel: CGFloat = 18

    /// A brief input gate prevents a double-click from skipping a screen or
    /// granting its next permission before the question is readable.
    static var navigationSettle: TimeInterval { prefersReducedMotion ? 0.15 : 0.28 }

    static var ambient: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .easeInOut(duration: 0.55)
    }

    static var auxiliaryTransition: AnyTransition {
        prefersReducedMotion ? .opacity : .opacity.combined(with: .offset(y: 5))
    }

    /// The window arriving: the prototype's `winIn`, kept. A whisper of scale
    /// from just under full size — never from nothing — so the first thing the
    /// flow does is demonstrate the motion the app is made of.
    static var windowEntrance: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .timingCurve(0.23, 1, 0.32, 1, duration: 0.42)
    }

    /// The progress track. Slower than a content swap: it travels a whole flow,
    /// and a spring that arrives instantly makes the distance invisible.
    static var track: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .spring(response: 0.5, dampingFraction: 0.9)
    }

    // MARK: Arriving in order

    /// A part's own entrance: quint-out, the same curve the prototype uses.
    static var reveal: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .timingCurve(0.23, 1, 0.32, 1, duration: 0.34)
    }

    /// Between one part and the next. Small: five parts of a screen should read
    /// as one arrival with a rhythm, not as five separate animations.
    static let stagger: Double = 0.045

    /// The beat between the screen starting to move and its parts following.
    static let revealLead: Double = 0.05

    /// How far a revealed part travels.
    static let revealTravel: CGFloat = 7

    /// One part's entrance, `index` of the way through a screen.
    static func revealStep(_ index: Int, extraDelay: Double = 0) -> Animation {
        guard !prefersReducedMotion else { return NotchAnimations.reduced }
        return reveal.delay(revealLead + Double(index) * stagger + extraDelay)
    }

    // MARK: Confirmation

    /// A grant landing: a spring with a little life in it, because it is the
    /// one moment in the flow worth celebrating.
    static var confirmation: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .spring(response: 0.34, dampingFraction: 0.78)
    }

    /// The ring that leaves the permission's mark when it is granted.
    static var confirmationRing: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .easeOut(duration: 0.6)
    }

    /// How long a grant holds its confirmation before the flow carries on by
    /// itself. A refusal never moves anything — the visitor says when they are
    /// done with that screen.
    static var grantHold: TimeInterval { prefersReducedMotion ? 0.25 : 0.85 }

    /// The window leaving upward, toward the notch it is describing.
    static var dismiss: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .timingCurve(0.23, 1, 0.32, 1, duration: 0.24)
    }

    /// The mini notch in the welcome screen: the app's own critically damped
    /// response (0.34s, no overshoot), so the demo moves the way the real notch
    /// does rather than the way a menu would.
    static var notchSpring: Animation {
        prefersReducedMotion ? NotchAnimations.reduced : .spring(response: 0.34, dampingFraction: 1)
    }

    // MARK: The demo

    /// The demo meter's sampler. Fast enough that the glide between samples
    /// (`NotchAnimations.clockStep`) reads as continuous motion rather than a
    /// staircase; slow enough that three decorative bands are not costing a
    /// measurable slice of a core to sit still on a first-run screen.
    static let meterStep: TimeInterval = 0.25

    /// A pointer crossing the demo notch should not flicker it shut, so the
    /// close waits a beat; opening does not.
    static let demoCloseGrace: TimeInterval = 0.16
}

extension IntegrationPermissions.Integration {
    /// The ask's one line on what the permission buys, in the first person of
    /// the feature rather than the second person of the request.
    var askHeadline: String {
        switch self {
        case .accessibility:
            "Media keys, the volume and brightness HUDs, and global hotkeys."
        case .screenCapture:
            "The three-band meter and per-app volume. Audio only — never pixels."
        case .filesAndFolders:
            "Finished downloads and new screenshots, announced the moment they land."
        case .music:
            "Drive Apple Music and Spotify directly — play, skip, scrub, and read lyrics."
        case .location:
            "Weather for where you actually are."
        case .calendar:
            "Today at the notch, with one-click meeting links."
        case .camera:
            "Face ID and the camera screen. Frames are processed in memory."
        case .bluetooth:
            "Names and battery levels for your paired audio accessories."
        case .notifications:
            "Alerts when a timer started in Notch finishes — even with the panel closed."
        }
    }

    /// And what happens without it, told as a smaller notch rather than a
    /// broken app — every one of these is optional.
    var askWithout: String {
        switch self {
        case .accessibility:
            "Without it, macOS keeps its own media-key routing and the notch stays out of your shortcuts."
        case .screenCapture:
            "Without it, the meter stays idle and the mixer cannot take an app over."
        case .filesAndFolders:
            "Without it, files you drop on the notch still work — only arrivals go unannounced."
        case .music:
            "Without it, the notch still follows whatever is already playing, and only that."
        case .location:
            "Without it, weather falls back to a rough guess based on your network."
        case .calendar:
            "Without it, the schedule stays empty and the notch skips meetings entirely."
        case .camera:
            "Without it, the camera screen stays empty and Face ID cannot see you."
        case .bluetooth:
            "Without it, accessories are still listed, just without names or battery."
        case .notifications:
            "Optional. Siri and Clock timer detection is separate; check Settings → Activities for access."
        }
    }

    var tint: Color {
        switch self {
        case .accessibility: Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255) // #8E8E93
        case .calendar: Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255) // #0A84FF
        case .location: Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255) // #30D158
        case .music: Color(red: 255 / 255, green: 138 / 255, blue: 61 / 255) // #FF8A3D
        case .screenCapture: Color(red: 191 / 255, green: 90 / 255, blue: 242 / 255) // #BF5AF2
        case .filesAndFolders: Color(red: 94 / 255, green: 92 / 255, blue: 230 / 255) // #5E5CE6
        case .camera: Color(red: 100 / 255, green: 210 / 255, blue: 255 / 255) // #64D2FF
        case .bluetooth: Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255) // #0A84FF
        case .notifications: Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255) // #FFD60A
        }
    }

    /// The two permissions whose grant is a switch in System Settings: sending
    /// someone there is the ask, so the screen says so and then waits for the
    /// switch instead of claiming a dialog decided it.
    var grantNeedsSettings: Bool {
        self == .accessibility || self == .screenCapture
    }
}
