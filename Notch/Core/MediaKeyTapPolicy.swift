import Foundation

/// What the media-key tap's health check should do about the tap.
///
/// Split out of `MediaKeyInterceptor` because this decision is the whole of its
/// recovery logic, and none of it needs a real `CGEventTap` to be exercised: a
/// tap cannot be built, disabled or invalidated on demand, so the rules that
/// decide what to do about a *disabled* one are checked as a pure function
/// instead of only in a live notch. Everything else in that class is plumbing
/// around this answer.
///
/// The reason it matters: a tap the system has switched off is invisible from
/// the outside. The volume and brightness keys simply raise the system HUD
/// again, which is the one thing the tap exists to prevent, and nothing on
/// screen says why.
enum MediaKeyTapAction: Equatable {
    /// Leave it alone — a tap exists and the system still has it enabled.
    case healthy
    /// Nothing to do *yet*: a tap that has only just been built is not
    /// necessarily enabled for the first moment, because the run loop serving
    /// it has not started.
    case none
    /// No tap at all: install one.
    case install
    /// Disabled and worth re-arming in place.
    case rearm
    /// Disabled, and a re-arm has already been tried for this tap: destroy the
    /// port and build another.
    case rebuild
    /// Take it down — HUD replacement is off, or the permission is gone.
    case teardown
}

enum MediaKeyTapPolicy {
    /// How long a newly armed tap is allowed not to be enabled yet — the run
    /// loop serving it has not started in that window.
    static let defaultSettleTime: TimeInterval = 3

    /// - Parameters:
    ///   - wanted: the user's HUD-replacement setting.
    ///   - trusted: Accessibility access, which an event tap needs at all.
    ///   - hasTap: a tap (with its run-loop source) exists.
    ///   - enabled: what `CGEvent.tapIsEnabled` answers.
    ///   - ageSinceArmed: how long ago the tap was created.
    ///   - settleTime: the window in which a new tap is allowed not to be
    ///     enabled yet.
    ///   - rearmAttempted: a re-arm has already been tried for this tap since
    ///     it was armed, and it is still disabled.
    static func action(
        wanted: Bool,
        trusted: Bool,
        hasTap: Bool,
        enabled: Bool,
        ageSinceArmed: TimeInterval,
        settleTime: TimeInterval,
        rearmAttempted: Bool
    ) -> MediaKeyTapAction {
        guard wanted, trusted else { return .teardown }
        guard hasTap else { return .install }
        if enabled { return .healthy }
        if ageSinceArmed < settleTime { return .none }
        // Exactly one re-arm before the port is treated as dead. `tapEnable` on
        // an invalidated port reports success and changes nothing, so asking
        // again forever would leave a tap that exists, re-arms "successfully",
        // and never receives a key — the silent failure this whole class is
        // against. Rebuilding is the only way back from a port in that state.
        return rearmAttempted ? .rebuild : .rearm
    }
}
