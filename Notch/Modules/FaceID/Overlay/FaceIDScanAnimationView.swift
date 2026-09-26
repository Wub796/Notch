import AppKit
import AVFoundation
import SwiftUI

/// Which media the panel is showing.
///
/// `.idle` is a still — the first frame of the success video — so the transition
/// into a playing video is seamless rather than a visible swap between two
/// different-looking images.
enum FaceIDScanMedia: Equatable {
    case idle
    case success
    case failure

    var videoResourceName: String? {
        switch self {
        case .idle: nil
        case .success: "unlockanimation"
        case .failure: "unsuccessfulunlockanimation"
        }
    }
}

/// Plays a scan animation once and holds its final frame. Deliberately not
/// looping: each clip ends on a resolved state — an open padlock or a cross —
/// and a loop would turn that state back into a loading spinner.
///
/// Ported from Glance (`NotchOverlay/ScanAnimationView.swift`, MIT © Jonathan
/// Zhou), including the two details that are invisible until they're wrong: the
/// player is muted, because this can play at the lock screen and nothing there
/// should make a sound, and the still is swapped for the video only once the
/// layer reports itself ready for display, since a fixed delay raced the real
/// decode time and flashed a black frame.
struct FaceIDScanAnimationView: NSViewRepresentable {
    let media: FaceIDScanMedia

    func makeNSView(context: Context) -> ScanAnimationHostView {
        let view = ScanAnimationHostView()
        view.apply(media: media)
        return view
    }

    func updateNSView(_ nsView: ScanAnimationHostView, context: Context) {
        nsView.apply(media: media)
    }

    final class ScanAnimationHostView: NSView {
        private var player: AVPlayer?
        private let playerLayer = AVPlayerLayer()
        private let stillImageLayer = CALayer()
        private var currentMedia: FaceIDScanMedia?
        private var readyObservation: NSKeyValueObservation?
        private var fallbackRevealWorkItem: DispatchWorkItem?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()

            stillImageLayer.contentsGravity = .resizeAspect
            if let still = Self.loadStillFromBundle() {
                stillImageLayer.contents = still
            }
            layer?.addSublayer(stillImageLayer)

            playerLayer.videoGravity = .resizeAspect
            playerLayer.isHidden = true
            layer?.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            stillImageLayer.frame = bounds
            CATransaction.commit()
        }

        func apply(media: FaceIDScanMedia) {
            guard media != currentMedia else { return }
            currentMedia = media
            readyObservation = nil
            fallbackRevealWorkItem?.cancel()

            guard let resource = media.videoResourceName else {
                teardownPlayer()
                playerLayer.isHidden = true
                stillImageLayer.isHidden = false
                return
            }

            guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
                assertionFailure("\(resource).mp4 is missing from the bundle — check Notch/Modules/FaceID/Resources")
                return
            }

            teardownPlayer()
            let newPlayer = AVPlayer(url: url)
            // This can play at the lock screen, where nothing may make a sound.
            newPlayer.isMuted = true
            // Leaves the player paused on its final frame rather than rewinding it.
            newPlayer.actionAtItemEnd = .none

            playerLayer.player = newPlayer
            player = newPlayer

            // Waits for `isReadyForDisplay` rather than a fixed delay, which raced
            // the real decode time and produced a black-frame flash.
            let reveal: () -> Void = { [weak self] in
                guard let self else { return }
                // Without disabling implicit actions, toggling `isHidden`
                // cross-fades both layers over CALayer's default duration instead
                // of swapping instantly.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.playerLayer.isHidden = false
                self.stillImageLayer.isHidden = true
                CATransaction.commit()
            }
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, change in
                guard change.newValue == true else { return }
                DispatchQueue.main.async {
                    self?.fallbackRevealWorkItem?.cancel()
                    reveal()
                    self?.readyObservation = nil
                }
            }
            // A safety net only: if `isReadyForDisplay` never fires for some
            // reason, this must not sit on the still image forever.
            let fallback = DispatchWorkItem { reveal() }
            fallbackRevealWorkItem = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: fallback)

            newPlayer.seek(to: .zero)
            newPlayer.play()
        }

        private func teardownPlayer() {
            readyObservation = nil
            fallbackRevealWorkItem?.cancel()
            player?.pause()
            player = nil
            playerLayer.player = nil
        }

        /// The still lives in the resources folder rather than an asset catalog —
        /// `NSImage(named:)` looks in catalogs, so this loads by URL.
        private static func loadStillFromBundle() -> NSImage? {
            guard let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "png") else { return nil }
            return NSImage(contentsOf: url)
        }
    }
}
