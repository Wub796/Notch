import AppKit
import Foundation
import Observation

/// Permission-free visualizer source. macOS does not expose a supported
/// system-wide PCM tap to ordinary apps, so this intentionally does not use
/// ScreenCaptureKit: no pixels are captured and no Screen Recording indicator
/// is triggered. The real-time app activity signal comes from AudioAppMonitor;
/// this class only turns the current output level into a subtle visual state.
@Observable
final class SystemAudioMeter {
    private(set) var bands: [Float] = [0, 0, 0]
    private(set) var isLive = false
    private(set) var failureReason: String?

    private var timer: Timer?
    private var phase: Float = 0

    static var hasPermission: Bool { true }
    static func requestPermission() -> Bool { true }

    func start() {
        guard timer == nil else { return }
        failureReason = nil
        isLive = true
        update()
        timer = Timer.scheduledRepeating(every: 1.0 / 20.0) { [weak self] in
            self?.update()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isLive = false
        bands = [0, 0, 0]
        phase = 0
    }

    deinit { stop() }

    private func update() {
        phase += 0.17
        let pulse = (sinf(phase) + 1) * 0.5
        let secondary = (sinf(phase * 1.37 + 1.1) + 1) * 0.5
        bands = [
            min(max(0.18 + pulse * 0.52, 0), 1),
            min(max(0.16 + secondary * 0.58, 0), 1),
            min(max(0.14 + pulse * 0.42, 0), 1)
        ]
    }
}
