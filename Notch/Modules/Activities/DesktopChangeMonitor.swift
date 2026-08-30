import AppKit
import Foundation

/// Announces Space (desktop) switches in the notch with the exact Space number.
/// Driven by the workspace notification and SkyLight/CoreGraphics Spaces query.
final class DesktopChangeMonitor {
    /// Called on the main queue when the active Space changes, passing the 1-based desktop number.
    var onChange: ((Int) -> Void)?

    private(set) var currentSpaceIndex: Int = 1
    private var observer: NSObjectProtocol?

    private typealias CGSConnectionID = Int32
    private typealias CGSMainConnectionIDFunc = @convention(c) () -> CGSConnectionID
    private typealias CGSCopyManagedDisplaySpacesFunc = @convention(c) (CGSConnectionID) -> CFArray?

    private var cgsMainConnectionID: CGSMainConnectionIDFunc?
    private var cgsCopyManagedDisplaySpaces: CGSCopyManagedDisplaySpacesFunc?

    init() {
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_NOW
        ) ?? dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_NOW
        ) {
            if let sym = dlsym(handle, "CGSMainConnectionID") {
                cgsMainConnectionID = unsafeBitCast(sym, to: CGSMainConnectionIDFunc.self)
            }
            if let sym = dlsym(handle, "CGSCopyManagedDisplaySpaces") {
                cgsCopyManagedDisplaySpaces = unsafeBitCast(sym, to: CGSCopyManagedDisplaySpacesFunc.self)
            }
        }
        currentSpaceIndex = queryCurrentSpaceIndex()
    }

    func queryCurrentSpaceIndex() -> Int {
        guard let cgsMainConnectionID, let cgsCopyManagedDisplaySpaces else { return 1 }
        let cid = cgsMainConnectionID()
        guard let info = cgsCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return 1 }

        for displayInfo in info {
            guard let currentSpace = displayInfo["Current Space"] as? [String: Any],
                  let currentID = currentSpace["id64"] as? Int64
                    ?? (currentSpace["id64"] as? Int).map({ Int64($0) })
                    ?? (currentSpace["ManagedSpaceID"] as? Int).map({ Int64($0) }),
                  let spaces = displayInfo["Spaces"] as? [[String: Any]]
            else { continue }

            var userSpaceIndex = 1
            for space in spaces {
                let spaceID = space["id64"] as? Int64
                    ?? (space["id64"] as? Int).map({ Int64($0) })
                    ?? (space["ManagedSpaceID"] as? Int).map({ Int64($0) })
                if spaceID == currentID {
                    return userSpaceIndex
                }
                userSpaceIndex += 1
            }
        }
        return 1
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let index = self.queryCurrentSpaceIndex()
            self.currentSpaceIndex = index
            self.onChange?(index)
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
