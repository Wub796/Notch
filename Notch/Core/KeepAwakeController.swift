import Foundation
import IOKit.pwr_mgt
import Observation

/// Caffeine-style toggle: holds an IOKit power-management assertion that keeps
/// the display (and therefore the Mac) awake while active.
@Observable
final class KeepAwakeController {
    private(set) var isActive = false
    private var assertionID = IOPMAssertionID(0)

    func toggle() {
        isActive ? stop() : start()
    }

    private func start() {
        guard !isActive else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Notch is keeping your Mac awake" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        isActive = true
    }

    private func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        isActive = false
    }

    deinit {
        if isActive {
            IOPMAssertionRelease(assertionID)
        }
    }
}
