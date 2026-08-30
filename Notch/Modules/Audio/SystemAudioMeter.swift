import AudioToolbox
import CoreAudio
import CoreGraphics
import CoreMedia
import Foundation
import Observation
import ScreenCaptureKit

/// Real output metering: taps the system audio mix through ScreenCaptureKit
/// and publishes three band energies for the visualiser.
///
/// Why this and not something quieter. Reading what other apps are actually
/// playing is privileged on macOS. There are exactly three routes: a Core
/// Audio process tap (`kAudioHardwareProperty…Tap`, macOS 14.4 SDK only), a
/// HAL plug-in the user installs, or ScreenCaptureKit's audio capture. The
/// first needs an SDK this project cannot assume; the second is an installer.
/// So it is this one — which is genuine PCM from the output mix, and which
/// costs a Screen Recording permission, so it stays **opt-in** and off until
/// the user turns it on. With it off, the visualiser falls back to the output
/// volume, which is real but is not the waveform.
@Observable
final class SystemAudioMeter: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Low, mid and high band energy, 0...1, smoothed for display.
    private(set) var bands: [Float] = [0, 0, 0]

    /// True while samples are genuinely arriving, so the view knows whether
    /// what it is drawing is the audio or the fallback.
    private(set) var isLive = false

    /// Set when the capture could not start — no permission, or no display.
    private(set) var failureReason: String?

    private var stream: SCStream?
    private var starting = false
    private var captureGeneration = 0
    private let sampleQueue = DispatchQueue(label: "com.notch.audiometer", qos: .userInitiated)

    /// One-pole filter states, kept between buffers so the split does not
    /// restart at every callback.
    private var lowState: Float = 0
    private var midState: Float = 0

    /// Display-side envelope: fast attack, slow release, the way a meter reads.
    private var envelope: [Float] = [0, 0, 0]
    private var lastPublish = Date.distantPast

    // MARK: - Lifecycle

    /// Whether Screen Recording is already granted. Never prompts.
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Raises the system prompt, once. macOS only shows it if it has never
    /// been answered; otherwise the user has to visit System Settings.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func start() {
        guard stream == nil, !starting else { return }
        guard Self.hasPermission else {
            failureReason = "Screen Recording permission is needed to read the audio output."
            return
        }
        starting = true
        captureGeneration += 1
        let generation = captureGeneration

        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false
                )
                guard let display = content.displays.first else {
                    await MainActor.run { [weak self] in
                        guard let self, self.captureGeneration == generation else { return }
                        self.starting = false
                        self.failureReason = "No display to capture audio from."
                    }
                    return
                }

                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: [],
                    exceptingWindows: []
                )

                guard let owner = self else { return }

                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 48_000
                configuration.channelCount = 2
                // No video is consumed, so ask for the smallest, slowest frame
                // the API will accept rather than a full-screen pipeline.
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                configuration.queueDepth = 3

                let stream = SCStream(filter: filter, configuration: configuration, delegate: owner)
                try stream.addStreamOutput(
                    owner, type: .audio, sampleHandlerQueue: owner.sampleQueue
                )
                try await stream.startCapture()

                await MainActor.run { [weak self] in
                    guard let self, self.captureGeneration == generation else {
                        Task { try? await stream.stopCapture() }
                        return
                    }
                    self.stream = stream
                    self.starting = false
                    self.failureReason = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.captureGeneration == generation else { return }
                    self.starting = false
                    self.isLive = false
                    self.failureReason = "Couldn't read the audio output: "
                        + error.localizedDescription
                }
            }
        }
    }

    /// A capture stream that outlives its owner keeps the screen-recording
    /// indicator lit, so this is not optional bookkeeping.
    deinit {
        guard let capture = stream else { return }
        Task { try? await capture.stopCapture() }
    }

    func stop() {
        captureGeneration += 1
        starting = false
        let capture = stream
        stream = nil
        isLive = false
        bands = [0, 0, 0]
        envelope = [0, 0, 0]
        guard let capture else { return }
        Task {
            try? await capture.stopCapture()
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.stream = nil
            self?.isLive = false
            self?.failureReason = error.localizedDescription
        }
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        var blockBuffer: CMBlockBuffer?
        var list = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        var lowSum: Float = 0
        var midSum: Float = 0
        var highSum: Float = 0
        var count = 0

        for buffer in UnsafeMutableAudioBufferListPointer(&list) {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard frames > 0 else { continue }

            // Two one-pole low passes split the signal into three bands: what
            // the slow filter keeps is bass, the gap between the filters is
            // the midrange, and what neither keeps is treble. Not an FFT, but
            // the energies are the track's own, sample by sample.
            for index in 0..<frames {
                let sample = samples[index]
                lowState += 0.02 * (sample - lowState)
                midState += 0.18 * (sample - midState)
                lowSum += lowState * lowState
                let mid = midState - lowState
                midSum += mid * mid
                let high = sample - midState
                highSum += high * high
            }
            count += frames
        }

        guard count > 0 else { return }
        let scale = 1 / Float(count)
        // RMS with heightened dynamic scaling for punchy visual response
        let measured = [
            Self.shape(sqrt(lowSum * scale) * 4.8),
            Self.shape(sqrt(midSum * scale) * 6.5),
            Self.shape(sqrt(highSum * scale) * 8.2),
        ]

        DispatchQueue.main.async { [weak self] in
            self?.publish(measured)
        }
    }

    /// Fast attack, quick release on pause/silence, capped at 30 updates/sec.
    private func publish(_ measured: [Float]) {
        guard stream != nil else { return }
        for index in envelope.indices {
            let target = measured[index]
            let coefficient: Float = target > envelope[index] ? 0.85 : 0.40
            envelope[index] += coefficient * (target - envelope[index])
            if envelope[index] < 0.01 {
                envelope[index] = 0
            }
        }

        if !isLive { isLive = true }

        let now = Date()
        guard now.timeIntervalSince(lastPublish) >= 1.0 / 30 else { return }
        lastPublish = now
        bands = envelope
    }

    private static func shape(_ value: Float) -> Float {
        min(max(powf(min(max(value, 0), 1), 0.65), 0), 1)
    }
}
