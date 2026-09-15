import AVFoundation
import SwiftUI

/// Plays a Spotify Canvas: a short vertical video, looped and silent, behind
/// the album art.
///
/// A Canvas is a loop with no sound of its own — the music is the sound — so it
/// is always muted, and it plays only while on screen. An `AVPlayerLooper`
/// gives a seamless repeat rather than a visible stutter at the loop point.
struct CanvasVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.load(url)
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        view.load(url)
    }

    static func dismantleNSView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: NSView {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var loadedURL: URL?
        private let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func load(_ url: URL) {
            guard loadedURL != url else { return }
            loadedURL = url
            stop()

            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.actionAtItemEnd = .advance
            looper = AVPlayerLooper(player: queue, templateItem: item)
            playerLayer.player = queue
            player = queue
            queue.play()
        }

        func stop() {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            playerLayer.player = nil
            player = nil
            loadedURL = nil
        }

        override func layout() {
            super.layout()
            // No implicit animation: the layer must not slide on a resize.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
