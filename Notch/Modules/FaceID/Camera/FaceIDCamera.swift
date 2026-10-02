@preconcurrency import AVFoundation
import CoreImage
import Observation

enum FaceIDCameraPermission {
    case notDetermined
    case granted
    case denied
}

/// One frame, with both the working copy and the source it came from.
///
/// Both are `CIImage`s — lazy recipes rather than rendered pixels — so
/// publishing a frame renders nothing: the downscale is a transform, and the
/// pixels are produced by `workingImage(from:)` on the thread that wants them.
/// The shape before that carried a rendered `CGImage`, built inside the sample
/// buffer callback, which parked AVFoundation's delivery thread on Core
/// Image's own workers (see `workingImage(from:)`); holding onto either recipe
/// costs nothing, and both keep the pixel buffer alive the same way.
struct FaceIDCameraFrame {
    let id: UInt64
    /// Downscaled working image, which is what Vision runs on.
    let image: CIImage
    /// Pixel size `image` renders to. The crop maths needs it before anything
    /// has rendered, and asking the recipe's extent is exact.
    let workingSize: CGSize
    let source: CIImage
    let sourceSize: CGSize
}

/// The camera, for face recognition rather than for looking at yourself.
///
/// Ported from Glance (`CameraManager.swift`, MIT © Jonathan Zhou). It is a
/// second capture session rather than a mode added to `CameraController`
/// because the two have opposite lifecycles: the preview starts only while its
/// screen is open and stops the moment it closes, whereas this one starts when a
/// scan is armed and stops when the scan ends — and the preview's session is
/// deliberately never warmed "in case".
///
/// Everything runs on-device. Frames live in memory, are never written to disk,
/// and the only thing that outlives a scan is the embedding the model produced.
@Observable
final class FaceIDCamera: NSObject {
    private(set) var permission: FaceIDCameraPermission = .notDetermined
    private(set) var isRunning = false
    private(set) var currentFrame: FaceIDCameraFrame?
    private(set) var errorMessage: String?

    /// Exposed so a preview layer can attach to the same session the detector
    /// reads from, rather than opening a second device.
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.notchapp.Notch.faceID.camera", qos: .userInitiated)

    /// Handed to the sample-buffer delegate outside the main actor; it hops back
    /// through `publish`, so nothing else touches it off the queue.
    private let framePublisher = FramePublisher()

    override init() {
        super.init()
        framePublisher.owner = self
        Self.warmRenderContext()
    }

    /// Opens the device, asking for permission if it has never been asked.
    /// Idempotent, so a scan cycle can call it without checking first.
    func start() async {
        guard !Task.isCancelled else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permission = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard !Task.isCancelled else { return }
            permission = granted ? .granted : .denied
        default:
            permission = .denied
        }

        guard permission == .granted else {
            errorMessage = "Camera access isn't granted (status: \(describe(status))). "
                + (status == .restricted
                    ? "macOS reports this as restricted rather than as a denial, which usually means Screen Time "
                        + "content restrictions or an MDM policy is blocking the camera for this app — toggling it "
                        + "in System Settings won't help until that is lifted."
                    : "Enable it in System Settings → Privacy & Security → Camera, then try again.")
            return
        }

        guard !Task.isCancelled else { return }
        errorMessage = nil
        configureSessionIfNeeded()
        reconcileDeviceIfNeeded()
        guard errorMessage == nil else { return }

        await withCheckedContinuation { continuation in
            sessionQueue.async { [session] in
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
        guard !Task.isCancelled else {
            stop()
            return
        }
        isRunning = true
    }

    /// Releases the device. The hardware light goes out here, which is the point
    /// — a session left running after a scan is a camera nobody is watching.
    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
        isRunning = false
        currentFrame = nil
    }

    private func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    private var isConfigured = false
    private var currentInput: AVCaptureDeviceInput?

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        // `.high` doesn't guarantee the sensor's maximum resolution, but macOS
        // doesn't fight an explicitly set `activeFormat` the way iOS does, so
        // leaving the preset here and locking the format separately is enough.
        session.sessionPreset = .high

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // A scan is a real-time loop with a rolling window: a queued late frame
        // would be measured as if it were the present, which corrupts the
        // motion cues rather than merely delaying them.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(framePublisher, queue: sessionQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }

    /// Called on every `start()` so a camera preference change takes effect on
    /// the next scan rather than at the next app launch.
    private func reconcileDeviceIfNeeded() {
        guard let device = FaceIDCameraCatalog.resolvedDevice() else {
            errorMessage = "No camera device found."
            return
        }
        guard device.uniqueID != currentInput?.device.uniqueID else { return }

        session.beginConfiguration()
        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                errorMessage = "macOS couldn't add the selected camera to the capture session."
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            currentInput = input
            selectHighestResolutionFormat(for: device)
        } catch {
            errorMessage = "Couldn't open the selected camera: \(error.localizedDescription)"
        }
        session.commitConfiguration()
    }

    /// Highest resolution regardless of frame rate. Vision works fine from the
    /// downscaled working frame; this only decides what `FaceIDCameraFrame.source`
    /// — and therefore the glare cue's crop — has to work with.
    private func selectHighestResolutionFormat(for device: AVCaptureDevice) {
        let best = device.formats.max { lhs, rhs in
            let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(left.width) * Int(left.height) < Int(right.width) * Int(right.height)
        }
        guard let best else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.unlockForConfiguration()
        } catch {
            errorMessage = "Couldn't select the camera's highest-resolution format: \(error.localizedDescription)"
        }
    }

    fileprivate func publish(frame: FaceIDCameraFrame) {
        currentFrame = frame
    }

    /// Renders a native-resolution crop of `imageRect` from `frame.source`, for
    /// the spoof cues that need pixel detail — screen texture, moiré, gloss —
    /// which the downscaled working frame has already thrown away.
    static func renderCrop(
        from frame: FaceIDCameraFrame,
        imageRect: CGRect,
        maxEdge: CGFloat = 448
    ) -> CGImage? {
        let workingWidth = frame.workingSize.width
        let workingHeight = frame.workingSize.height
        guard workingWidth > 0, workingHeight > 0 else { return nil }
        let scaleX = frame.sourceSize.width / workingWidth
        let scaleY = frame.sourceSize.height / workingHeight

        // Expanded about 1.3x so device edges and bezels are inside the crop the
        // texture and moiré cues read.
        let expanded = imageRect.insetBy(dx: -imageRect.width * 0.15, dy: -imageRect.height * 0.15)

        // Flipped out of `imageRect`'s top-left, y-down space into Core Image's
        // bottom-left, y-up space — the reverse of
        // `FaceDetector.convertToImageSpace`.
        let nativeX = expanded.origin.x * scaleX
        let nativeWidth = expanded.width * scaleX
        let nativeHeight = expanded.height * scaleY
        let nativeY = frame.sourceSize.height - (expanded.origin.y + expanded.height) * scaleY
        var nativeRect = CGRect(x: nativeX, y: nativeY, width: nativeWidth, height: nativeHeight)

        let sourceExtent = CGRect(origin: .zero, size: frame.sourceSize)
        nativeRect = nativeRect.intersection(sourceExtent)
        guard !nativeRect.isEmpty else { return nil }

        var cropped = frame.source.cropped(to: nativeRect)
            .transformed(by: CGAffineTransform(translationX: -nativeRect.minX, y: -nativeRect.minY))
        let longEdge = max(nativeRect.width, nativeRect.height)
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            cropped = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        return renderContext.createCGImage(cropped, from: cropped.extent)
    }

    /// Renders a frame's working copy — the downscaled image Vision runs on.
    ///
    /// Called by the scan loops, on the threads that own them, and never by the
    /// capture callback. That is the whole point of the frame carrying a recipe:
    /// a Core Image render is synchronous and dispatches to Core Image's own
    /// workers, so doing it inside `captureOutput` parks AVFoundation's delivery
    /// thread — which runs at a real-time quality of service — on threads at a
    /// lower one, which the Thread Performance Checker reports as a priority
    /// inversion. The conversion still has to happen; it belongs where the
    /// pixels are wanted, and the scan loops already run their work off the main
    /// thread.
    static func workingImage(from frame: FaceIDCameraFrame) -> CGImage? {
        renderContext.createCGImage(frame.image, from: frame.image.extent)
    }

    /// One `CIContext` for both renders in this file: the working copy every
    /// frame needs, and the native-resolution crop the spoof cues ask for.
    ///
    /// Safe to reuse concurrently, and expensive to *create*: the initialiser
    /// talks to the GPU stack and dispatches to Core Image's workers, so
    /// building one parks the calling thread on them. It used to be a stored
    /// property of `FramePublisher`, which meant every `FaceIDCamera()` built
    /// one on whichever thread constructed it — the app's launch path and the
    /// Face ID settings pane's preview both do that on the main thread, and the
    /// Thread Performance Checker reported exactly that as a priority inversion
    /// (a user-interactive thread waiting on Core Image's utility-QoS workers,
    /// at this property's line). Created once now, off the main thread, by
    /// `warmRenderContext()`.
    private static let renderContext = CIContext()

    /// Builds `renderContext` ahead of the first frame that wants it.
    ///
    /// Fire and forget, on a queue whose quality of service is no higher than
    /// Core Image's own workers, so neither the main thread nor a scan's first
    /// render ever pays for the build or waits on it.
    private static func warmRenderContext() {
        renderWarmupQueue.async { _ = renderContext }
    }

    private static let renderWarmupQueue = DispatchQueue(
        label: "com.notchapp.Notch.faceID.renderWarmup",
        qos: .utility
    )

    /// Sample buffers arrive on `sessionQueue`, off the main thread; this
    /// delegate builds the frame's two recipes there and hops back to publish.
    /// It renders nothing: see `workingImage(from:)` for why that must not
    /// happen on this thread.
    private final class FramePublisher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        weak var owner: FaceIDCamera?
        /// Detection only needs a modest resolution, and the live preview renders
        /// from the capture session directly so it is unaffected by this. The
        /// undownscaled `source` is kept alongside for `renderCrop`.
        private let maxLongEdge: CGFloat = 640
        private var nextFrameID: UInt64 = 0

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
            let sourceExtent = sourceImage.extent
            // A transform on the recipe, not a render: the working copy is the
            // same buffer at a smaller scale until somebody asks for pixels.
            var workingImage = sourceImage
            let longEdge = max(workingImage.extent.width, workingImage.extent.height)
            if longEdge > maxLongEdge {
                let scale = maxLongEdge / longEdge
                workingImage = workingImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }

            nextFrameID &+= 1
            let frame = FaceIDCameraFrame(
                id: nextFrameID,
                image: workingImage,
                workingSize: workingImage.extent.integral.size,
                source: sourceImage,
                sourceSize: sourceExtent.size
            )

            DispatchQueue.main.async { [weak owner] in
                owner?.publish(frame: frame)
            }
        }
    }
}
