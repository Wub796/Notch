import Sparkle

/// Owns Sparkle's updater for the agent application.
///
/// Keeping the controller alive for the lifetime of the process is required by
/// Sparkle; the standard controller also handles automatic checks and the
/// update UI. The feed URL and update policy live in Info.plist so release
/// tooling can change them without changing Swift code.
final class UpdateController {
    static let shared = UpdateController()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
