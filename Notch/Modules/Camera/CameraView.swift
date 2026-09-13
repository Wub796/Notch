import AVFoundation
import AppKit
import SwiftUI

/// The camera screen: a live mirror, for checking yourself before a call.
///
/// Starts the capture session on appear and stops it on disappear, which is
/// what keeps the hardware light honest — see `CameraController`.
struct CameraView: View {
    let state: NotchState

    private var camera: CameraController { state.camera }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchTheme.Space.m) {
            ScreenHeader("Camera", subtitle: subtitle) {
                if camera.status == .running {
                    NotchIconButton(
                        systemImage: camera.isMirrored
                            ? "arrow.left.and.right.righttriangle.left.righttriangle.right.fill"
                            : "arrow.left.and.right.righttriangle.left.righttriangle.right",
                        isActive: camera.isMirrored,
                        help: camera.isMirrored ? "Show unmirrored" : "Mirror the preview",
                        activeTint: .blue
                    ) {
                        withAnimation(NotchAnimations.content) {
                            camera.isMirrored.toggle()
                        }
                    }
                }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var subtitle: String {
        switch camera.status {
        case .running: camera.isMirrored ? "Mirrored" : "As others see you"
        case .denied: "Camera access is off"
        case .unavailable: "No camera found"
        case .idle: "Starting…"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch camera.status {
        case .running:
            if let session = camera.session {
                CameraPreviewLayer(session: session, isMirrored: camera.isMirrored)
                    .clipShape(
                        RoundedRectangle(cornerRadius: NotchTheme.Radius.card, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: NotchTheme.Radius.card, style: .continuous)
                            .strokeBorder(NotchTheme.Surface.borderStrong, lineWidth: 1)
                    }
                    .transition(.opacity)
            }

        case .denied:
            ScreenEmptyState(
                symbol: "video.slash",
                title: "Camera access is off",
                caption: "Turn Notch on under Privacy & Security → Camera."
            )
            .onTapGesture {
                if let url = URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }

        case .unavailable:
            ScreenEmptyState(
                symbol: "video.slash",
                title: "No camera found",
                caption: "Nothing is reporting itself as a video device."
            )

        case .idle:
            ScreenEmptyState(symbol: "video", title: "Starting the camera…")
        }
    }
}

/// Hosts `AVCaptureVideoPreviewLayer`. A layer rather than a SwiftUI surface
/// because the preview is a hardware-backed feed — drawing it any other way
/// means copying frames for no reason.
private struct CameraPreviewLayer: NSViewRepresentable {
    let session: AVCaptureSession
    let isMirrored: Bool

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.attach(session)
        view.setMirrored(isMirrored)
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.attach(session)
        view.setMirrored(isMirrored)
    }

    final class PreviewView: NSView {
        private let preview = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func attach(_ session: AVCaptureSession) {
            guard preview.session !== session else { return }
            preview.session = session
        }

        func setMirrored(_ mirrored: Bool) {
            guard let connection = preview.connection,
                  connection.isVideoMirroringSupported
            else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            guard connection.isVideoMirrored != mirrored else { return }
            connection.isVideoMirrored = mirrored
        }

        override func layout() {
            super.layout()
            // No implicit animation: the layer would otherwise slide into place
            // every time the panel resizes.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview.frame = bounds
            CATransaction.commit()
        }
    }
}
