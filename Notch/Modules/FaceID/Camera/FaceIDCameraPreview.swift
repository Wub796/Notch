import AVFoundation
import AppKit
import SwiftUI

/// Hosts `AVCaptureVideoPreviewLayer` for the Face ID camera, optionally drawing
/// a box around the face Vision found — which is what makes the enrollment
/// screen's "move closer" and "turn left" prompts legible rather than a guess at
/// whether the detector can see you at all.
///
/// Ported from Glance (`CameraPreviewView.swift`, MIT © Jonathan Zhou). Two
/// details are load-bearing and neither is obvious: the preview is mirrored at
/// the layer level rather than through the capture connection, which has no
/// effect here, and the layout sets `bounds`/`position` rather than `frame`,
/// because Core Animation mis-reports `frame` once a non-identity transform is
/// applied — and mirroring is exactly that.
struct FaceIDCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var faces: [DetectedFace] = []

    func makeNSView(context: Context) -> PreviewHostView {
        PreviewHostView(session: session)
    }

    func updateNSView(_ nsView: PreviewHostView, context: Context) {
        nsView.updateFaceBoxes(faces)
    }

    final class PreviewHostView: NSView {
        private let previewLayer: AVCaptureVideoPreviewLayer
        private var boxLayers: [CAShapeLayer] = []

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            // Fills rather than fits: with `.resizeAspect` the sensor's aspect
            // ratio leaves bars inside a rounded mask, which reads as a broken
            // preview instead of as a fitting one.
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            // No implicit animation: the layer would otherwise slide into place
            // every time the panel resizes.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
            CATransaction.commit()
        }

        func updateFaceBoxes(_ faces: [DetectedFace]) {
            boxLayers.forEach { $0.removeFromSuperlayer() }
            boxLayers = faces.map { face in
                let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: face.normalizedBoundingBox)
                let shape = CAShapeLayer()
                shape.path = CGPath(rect: rect, transform: nil)
                shape.strokeColor = NSColor.systemGreen.cgColor
                shape.fillColor = NSColor.clear.cgColor
                shape.lineWidth = 2
                previewLayer.addSublayer(shape)
                return shape
            }
        }
    }
}
