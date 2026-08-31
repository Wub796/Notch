import AppKit
import Observation
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Dropover-style holding area for files dropped onto the notch. Items can be
/// dragged back out, AirDropped (individually or all at once), copied, or
/// revealed in Finder. With "instant AirDrop" enabled the shelf is bypassed
/// and drops go straight to the share sheet.
@Observable
final class ShelfController {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let name: String
        let detail: String
        /// File icon initially; replaced by a real Quick Look thumbnail once
        /// one has been generated.
        var icon: NSImage

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.url == rhs.url
        }
    }

    private(set) var items: [Item] = []
    private(set) var isResolvingDrop = false

    static let acceptedTypes: [UTType] = [.fileURL, .content]

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    // MARK: - Drop intake

    /// Resolves dropped providers into URLs, then either shelves them or
    /// AirDrops immediately, per settings. Calls `completion` with the number
    /// of items accepted.
    func handleDrop(_ providers: [NSItemProvider], completion: @escaping (Int) -> Void) {
        guard !providers.isEmpty else {
            completion(0)
            return
        }
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
            guard let self else { return }
            self.isResolvingDrop = false
            guard !urls.isEmpty else {
                completion(0)
                return
            }
            if NotchSettings.shared.instantAirDrop {
                Self.airDrop(urls)
            } else {
                self.add(urls)
            }
            completion(urls.count)
        }
    }

    func add(_ urls: [URL]) {
        let newItems = urls
            .filter { url in !items.contains { $0.url == url } }
            .map(Self.makeItem)
        items.insert(contentsOf: newItems, at: 0)
        newItems.forEach(loadThumbnail)
    }

    /// Upgrades an item's generic file icon to a real Quick Look thumbnail.
    private func loadThumbnail(for item: Item) {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 80, height: 80),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let representation else { return }
            let image = NSImage(
                cgImage: representation.cgImage,
                size: NSSize(width: 40, height: 40)
            )
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let index = self.items.firstIndex(where: { $0.id == item.id })
                else { return }
                self.items[index].icon = image
            }
        }
    }

    // MARK: - Item actions

    func airDrop(_ item: Item) {
        Self.airDrop([item.url])
    }

    func airDropAll() {
        Self.airDrop(items.map(\.url))
    }

    func copyToPasteboard(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
    }

    func revealInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    // MARK: - Helpers

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls)
        else { return }
        service.perform(withItems: urls)
    }

    private static func makeItem(for url: URL) -> Item {
        var detail = url.pathExtension.uppercased()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                detail = "Folder"
            } else if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                detail = sizeFormatter.string(fromByteCount: Int64(size))
            }
        }
        return Item(
            url: url,
            name: url.lastPathComponent,
            detail: detail,
            icon: NSWorkspace.shared.icon(forFile: url.path)
        )
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
