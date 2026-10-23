import AppKit
import SwiftUI

/// Shows only the volume and brightness bar over the lock screen, as an
/// extension of the notch. The full notch stays on the desktop.
///
/// The panel is delegated into the elevated SkyLight space only while CGSession
/// confirms the screen is locked, and is hidden again on unlock.
final class LockScreenHUDController {
    private let state: NotchState
    private var panel: NSPanel?
    private var isDelegated = false
    private var observers: [NSObjectProtocol] = []

    init(state: NotchState) {
        self.state = state
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.sync()
            },
            center.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.sync()
            },
        ]
        sync()
    }

    deinit {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    /// Re-reads the authoritative lock state and shows or hides the HUD panel.
    func sync() {
        let isLocked = LockMonitor.isScreenActuallyLocked()
        if isLocked {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        guard let screen = NSScreen.main else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        if panel.contentView == nil {
            panel.contentView = NSHostingView(rootView: LockScreenHUDView(state: state))
        }
        // Centred on the real notch, dropped just below its bottom edge, so the
        // bar reads as an extension of the notch rather than a floating strip.
        let geometry = NotchGeometry(screen: screen)
        let size = CGSize(width: 320, height: 34)
        panel.setFrame(
            NSRect(
                x: (geometry.notchCenterX - size.width / 2).rounded(),
                y: (screen.frame.maxY - geometry.notchSize.height - size.height).rounded(),
                width: size.width,
                height: size.height
            ),
            display: true
        )
        if !isDelegated, let skyLight = FaceIDSkyLight.shared {
            skyLight.delegate(panel)
            isDelegated = true
        }
        guard !panel.isVisible else { return }
        // Fade in with the notch's own content curve so it arrives smoothly.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else {
            if let panel, isDelegated, let skyLight = FaceIDSkyLight.shared {
                skyLight.undelegate(panel)
                isDelegated = false
            }
            return
        }
        // Fade out, then take it out of the elevated space once it is gone, so
        // the panel never lingers above the login window.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isDelegated, let skyLight = FaceIDSkyLight.shared {
                    skyLight.undelegate(panel)
                    self.isDelegated = false
                }
                panel.orderOut(nil)
            }
        })
    }

    private func makePanel() -> NSPanel {
        // Renders only the volume/brightness bar, never the full notch.
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        return panel
    }
}

/// Only the volume or brightness bar, drawn from the notch's current transient
/// activity. Shows nothing for any other activity.
struct LockScreenHUDView: View {
    let state: NotchState

    var body: some View {
        switch state.activities.transient {
        case let .volume(level, muted):
            DroppedHUDBar(
                kind: .volume(muted: muted),
                value: .constant(CGFloat(muted ? 0 : level)),
                showsPercentage: state.settings.showHUDPercentage
            )
        case let .brightness(level):
            DroppedHUDBar(
                kind: .brightness,
                value: .constant(CGFloat(level)),
                showsPercentage: state.settings.showHUDPercentage
            )
        default:
            Color.clear
        }
    }
}
