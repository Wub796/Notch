import AVFoundation
import Observation

/// The webcam, for a quick look at yourself before a call.
///
/// The whole design problem here is the lifetime of the capture session, not
/// the picture. A camera that keeps running after you have stopped looking at
/// it is a privacy problem, and on a Mac it is a *visible* one: the green
/// hardware light stays lit and people rightly assume the worst. So the
/// session is bound strictly to the view being on screen — it starts when the
/// camera screen appears and stops the moment it goes away, including when the
/// notch collapses, the app sleeps, or the user switches tabs.
///
/// It is never started speculatively, never kept warm "in case", and never
/// started to find out whether permission exists — `AVCaptureDevice` answers
/// that without opening the device.
@Observable
final class CameraController {
    enum Status: Equatable {
        case idle
        case running
        case denied
        case unavailable
    }

    private(set) var status: Status = .idle

    /// The live session, handed to the preview layer. nil while stopped, so
    /// the view cannot hold a reference to a session that is no longer running.
    private(set) var session: AVCaptureSession?

    /// Mirrored by default: a preview you are checking yourself in should
    /// behave like a mirror, not like a photograph of you.
    var isMirrored = true

    /// Everything touching `AVCaptureSession` happens here — `startRunning()`
    /// blocks for as long as the camera takes to warm up, which is long enough
    /// to stutter the open animation if it runs on main.
    private let queue = DispatchQueue(label: "com.notch.camera", qos: .userInitiated)

    /// Whether the camera screen currently wants a picture.
    ///
    /// Separate from `session` because opening the device is asynchronous:
    /// the screen can be gone before the camera has finished warming up, and
    /// a session that arrives after that must be shut down rather than
    /// published — otherwise the light comes on for a view nobody is looking
    /// at. Every publish is gated on this.
    private var isWanted = false

    var authorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Whether the notch has ever asked. macOS shows the camera prompt once
    /// per app; after that a denial can only be undone in System Settings.
    var hasBeenAsked: Bool {
        authorization != .notDetermined
    }

    // MARK: - Lifecycle

    /// Called when the camera screen appears.
    func start() {
        isWanted = true
        guard session == nil else { return }

        switch authorization {
        case .authorized:
            openSession()
        case .notDetermined:
            // Only ever from here — opening the camera screen is the user
            // asking, which is the only moment a prompt is warranted.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.isWanted else { return }
                    granted ? self.openSession() : (self.status = .denied)
                }
            }
        default:
            status = .denied
        }
    }

    /// Called when the camera screen goes away — a tab switch, a collapse, the
    /// app quitting. Tears the session down rather than pausing it, so the
    /// capture device is released and the hardware light goes out.
    func stop() {
        isWanted = false
        guard let session else {
            if status == .running { status = .idle }
            return
        }
        self.session = nil
        status = .idle
        queue.async {
            if session.isRunning { session.stopRunning() }
            session.inputs.forEach(session.removeInput)
        }
    }

    deinit {
        // Not `stop()`: that touches observable state during teardown. Just
        // make sure the hardware is released.
        if let session {
            let s = session
            queue.async {
                if s.isRunning { s.stopRunning() }
                s.inputs.forEach(s.removeInput)
            }
        }
    }

    // MARK: - Session

    private func openSession() {
        guard session == nil, isWanted else { return }

        queue.async { [weak self] in
            guard let self else { return }
            let session = AVCaptureSession()
            // A preview thumbnail does not need a full-resolution feed, and a
            // lower preset both warms up faster and costs less power.
            session.sessionPreset = .medium

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                DispatchQueue.main.async {
                    guard self.isWanted else { return }
                    self.status = .unavailable
                }
                return
            }

            session.addInput(input)
            session.startRunning()

            DispatchQueue.main.async {
                // The screen may have gone away while the device warmed up.
                // If so this session is already unwanted: shut it down rather
                // than publishing it, or the light stays on for nothing.
                guard self.isWanted else {
                    self.queue.async {
                        if session.isRunning { session.stopRunning() }
                        session.inputs.forEach(session.removeInput)
                    }
                    return
                }
                self.session = session
                self.status = .running
            }
        }
    }
}
