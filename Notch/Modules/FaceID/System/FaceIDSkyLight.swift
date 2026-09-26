import AppKit

/// Private, undocumented SkyLight window-server API — the only way found to
/// make a window visible on the real macOS lock screen, which is exactly where
/// this feature has to draw.
///
/// Ported from Glance (`NotchOverlay/NotchSkyLight.swift`, MIT © Jonathan
/// Zhou), itself adapted from Lakr233/SkyLightWindow (MIT).
///
/// **RISK, and it is a real one.** This `dlopen`s a private Apple framework and
/// calls undocumented C symbols. Apple can change or remove them in any macOS
/// update, and their use would disqualify Mac App Store distribution — Notch
/// ships through GitHub releases and Developer ID notarization, so that last
/// part is not a blocker here, but an OS update breaking it is. `shared` is
/// `nil` if anything fails to load, so the failure mode is "no lock-screen
/// visibility" rather than a crash: the feature degrades to invisible rather
/// than taking the app down with it.
///
/// Delegation is only ever in place while the screen is actually locked — see
/// `FaceIDOverlayWindowController.show()` and `hide()`.
final class FaceIDSkyLight {
    /// Notification Center's own level at the lock screen. Higher than the
    /// plain `screenLock` level, which is why it is the one used here — the
    /// panel has to sit above the login window, not below it.
    private enum SpaceLevel: Int32 {
        case notificationCenterAtScreenLock = 400
    }

    /// `nil` if the private framework or any symbol couldn't be loaded, which
    /// callers must treat as "lock-screen visibility unavailable".
    static let shared: FaceIDSkyLight? = FaceIDSkyLight()

    private let connection: Int32
    private let space: Int32

    private typealias F_SLSMainConnectionID = @convention(c) () -> Int32
    private typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias F_SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private let addWindowsAndRemoveFromSpaces: F_SLSSpaceAddWindowsAndRemoveFromSpaces
    private let removeWindowsFromSpaces: F_SLSRemoveWindowsFromSpaces

    private init?() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW
        ) else { return nil }

        guard
            let mainConnectionSymbol = dlsym(handle, "SLSMainConnectionID"),
            let spaceCreateSymbol = dlsym(handle, "SLSSpaceCreate"),
            let setLevelSymbol = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSpacesSymbol = dlsym(handle, "SLSShowSpaces"),
            let addRemoveSymbol = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces"),
            let removeSymbol = dlsym(handle, "SLSRemoveWindowsFromSpaces")
        else { return nil }

        let mainConnectionID = unsafeBitCast(mainConnectionSymbol, to: F_SLSMainConnectionID.self)
        let spaceCreate = unsafeBitCast(spaceCreateSymbol, to: F_SLSSpaceCreate.self)
        let setAbsoluteLevel = unsafeBitCast(setLevelSymbol, to: F_SLSSpaceSetAbsoluteLevel.self)
        let showSpaces = unsafeBitCast(showSpacesSymbol, to: F_SLSShowSpaces.self)
        addWindowsAndRemoveFromSpaces = unsafeBitCast(
            addRemoveSymbol, to: F_SLSSpaceAddWindowsAndRemoveFromSpaces.self
        )
        removeWindowsFromSpaces = unsafeBitCast(removeSymbol, to: F_SLSRemoveWindowsFromSpaces.self)

        connection = mainConnectionID()
        // The `1` flag is load-bearing: any other value makes Finder draw
        // desktop icons into this space.
        space = spaceCreate(connection, 1, 0)
        _ = setAbsoluteLevel(connection, space, SpaceLevel.notificationCenterAtScreenLock.rawValue)
        _ = showSpaces(connection, [space] as CFArray)
    }

    /// Adds `window` to the elevated-level space, making it visible on the lock
    /// screen. Call only while the screen is actually locked.
    func delegate(_ window: NSWindow) {
        _ = addWindowsAndRemoveFromSpaces(connection, space, [window.windowNumber] as CFArray, 7)
    }

    /// Returns `window` to normal window-server behaviour. Call as soon as the
    /// screen unlocks — a window left in this space would keep floating above
    /// everything afterwards.
    func undelegate(_ window: NSWindow) {
        _ = removeWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
