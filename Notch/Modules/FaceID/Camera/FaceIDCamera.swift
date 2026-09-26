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
/// `source` is a `CIImage` — a lazy recipe rather than rendered pixels — so
/// holding onto it costs nothing until `renderCrop` uses it.
struct FaceIDCameraFrame {
    let id: UInt64
    /// Downscaled working image, which is what Vision runs on.
    let image: CGImage
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
    }

    /// Opens the device, asking for permission if it has never been asked.
    /// Idempotent, so a scan cycle can call it without checking first.
    func start() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permission = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
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

        errorMessage = nil
        configureSessionIfNeeded()
        reconcileDeviceIfNeeded()

        sessionQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
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
        }
        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
            selectHighestResolutionFormat(for: device)
        } else {
            currentInput = nil
            errorMessage = "No camera device found."
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
        let workingWidth = CGFloat(frame.image.width)
        let workingHeight = CGFloat(frame.image.height)
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

        return cropRenderContext.createCGImage(cropped, from: cropped.extent)
    }

    /// `CIContext` is expensive to create and safe to reuse concurrently.
    private static let cropRenderContext = CIContext()

    /// Sample buffers arrive on `sessionQueue`, off the main thread; this
    /// delegate converts there and then hops back to publish.
    private final class FramePublisher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        weak var owner: FaceIDCamera?
        private let ciContext = CIContext()
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
            var workingImage = sourceImage
            let longEdge = max(workingImage.extent.width, workingImage.extent.height)
            if longEdge > maxLongEdge {
                let scale = maxLongEdge / longEdge
                workingImage = workingImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            guard let cgImage = ciContext.createCGImage(workingImage, from: workingImage.extent) else { return }

            nextFrameID &+= 1
            let frame = FaceIDCameraFrame(
                id: nextFrameID,
                image: cgImage,
                source: sourceImage,
                sourceSize: sourceExtent.size
            )

            DispatchQueue.main.async { [weak owner] in
                owner?.publish(frame: frame)
            }
        }
    }
}
