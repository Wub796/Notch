import AVFoundation
import AppKit

struct FaceIDCameraDevice: Identifiable, Hashable {
    /// `AVCaptureDevice.uniqueID`.
    let id: String
    let name: String
}

/// Resolves the camera preference — a flat default, or one camera per kind of
/// display — into the device the session actually opens.
///
/// Ported from Glance (`CameraDeviceCatalog.swift`, MIT © Jonathan Zhou). The
/// per-display split exists because the built-in camera sees a different angle
/// of the same face depending on whether you are sitting at the Mac's own screen
/// or at a monitor: same person, different geometry, and enrolling both is
/// cheaper than weakening the threshold for everyone.
///
/// Deliberately free of SwiftUI, like the rest of the recognition path, so it can
/// be typechecked and reasoned about without a view in the way —
/// `FaceIDCameraPreview` is the view half and lives next to the camera.
enum FaceIDCameraCatalog {
    static func availableDevices() -> [FaceIDCameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { FaceIDCameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// True when the currently-active screen is the Mac's own display rather than
    /// an external monitor, which is what picks between the two overrides.
    static func isUsingBuiltInDisplay() -> Bool {
        guard let screen = NSScreen.main,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return true }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    /// Display-specific override, then the flat default, then the system default
    /// camera.
    static func resolvedDevice() -> AVCaptureDevice? {
        let settings = FaceIDSettings.shared
        let preferredID = isUsingBuiltInDisplay()
            ? (settings.builtInDisplayCameraID ?? settings.defaultCameraID)
            : (settings.externalDisplayCameraID ?? settings.defaultCameraID)

        if let preferredID, let device = AVCaptureDevice(uniqueID: preferredID) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }
}
