import AppKit
import Foundation

/// Announces Space (desktop) switches in the notch — Sapphire's desktop
/// change activity. Driven by the workspace notification, so it costs nothing
/// between switches.
final class DesktopChangeMonitor {
    /// Called on the main queue when the active Space changes.
    var onChange: (() -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onChange?()
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    deinit {
        stop()
    }
}
