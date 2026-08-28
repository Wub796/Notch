import AppKit
import Observation
import UniformTypeIdentifiers

/// Resolves dropped item providers into URLs and hands them to the system
/// AirDrop sharing service.
@Observable
final class AirDropController {
    private(set) var isResolvingDrop = false

    /// Accepts anything: file URLs directly, plain text via a temp file.
    static let acceptedTypes: [UTType] = [.fileURL, .content]

    func share(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isResolvingDrop = true

        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()

        func append(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        append(url)
                    } else if let url = item as? URL {
                        append(url)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                group.enter()
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    defer { group.leave() }
                    guard let text = object as? String, !text.isEmpty else { return }
                    if let url = Self.writeTemporaryTextFile(text) {
                        append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isResolvingDrop = false
            guard !urls.isEmpty,
                  let service = NSSharingService(named: .sendViaAirDrop),
                  service.canPerform(withItems: urls)
            else { return }
            service.perform(withItems: urls)
        }
    }

    private static func writeTemporaryTextFile(_ text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Notch Drop \(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
