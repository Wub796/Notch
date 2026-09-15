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
    /// Where a drop should go. The notch as a whole follows the instant-AirDrop
    /// setting; the shelf screen's two wells each name their own destination.
    enum DropDestination {
        case automatic
        case shelf
        case airDrop
    }

    func handleDrop(
        _ providers: [NSItemProvider],
        destination: DropDestination = .automatic,
        completion: @escaping (Int) -> Void
    ) {
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
            } else if let type = Self.fileContentType(of: provider) {
                // An image, PDF or movie dragged out of something with no file
                // to point at — a browser image, a preview. These used to fall
                // through every branch and the drop did nothing. The provider
                // deletes its copy as soon as the handler returns, so keep one.
                let suggestedName = provider.suggestedName
                group.enter()
                _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                    defer { group.leave() }
                    guard let url,
                          let kept = Self.keepCopy(of: url, suggestedName: suggestedName, type: type)
                    else { return }
                    append(kept)
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
            let sendsToAirDrop = destination == .airDrop
                || (destination == .automatic && NotchSettings.shared.instantAirDrop)
            if sendsToAirDrop {
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
        Self.thumbnail(for: item.url, size: 80) { [weak self] image in
            guard let self, let image,
                  let index = self.items.firstIndex(where: { $0.id == item.id })
            else { return }
            self.items[index].icon = image
        }
    }

    /// Generates a Quick Look thumbnail, calling back on the main queue with
    /// nil when the file has no representation. Shared with `FileCatcher`,
    /// which shows arrivals the same way the shelf shows drops.
    static func thumbnail(
        for url: URL,
        size: CGFloat,
        completion: @escaping (NSImage?) -> Void
    ) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(
            for: request
        ) { representation, _ in
            let image = representation.map {
                NSImage(cgImage: $0.cgImage, size: NSSize(width: size / 2, height: size / 2))
            }
            DispatchQueue.main.async { completion(image) }
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

    /// Called when an item has been dragged out of the shelf and accepted by
    /// something else. Honours "Clear the Shelf After Dragging Out": the shelf
    /// is a staging area, and for people who use it that way the item having
    /// landed somewhere is what makes it finished with.
    func handleDragOut(_ item: Item) {
        guard NotchSettings.shared.autoClearShelf else { return }
        remove(item)
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

    /// Where dropped content that is not already a file is kept.
    private static var dropsFolder: URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Notch Drops", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes to "Name.ext", then "Name 2.ext" and so on, until one did not
    /// already exist. `write` must refuse to overwrite, which makes the name
    /// check and the write one step even when several drops resolve at once.
    ///
    /// Text drops used to be named by the whole second, so two inside the
    /// same second wrote the same file: the second overwrote the first, and
    /// the shelf — which dedupes by URL — silently dropped it.
    private static func writeUnique(
        named base: String,
        extension ext: String,
        _ write: (URL) throws -> Void
    ) -> URL? {
        let folder = dropsFolder
        for index in 1 ... 500 {
            var url = folder.appendingPathComponent(index == 1 ? base : "\(base) \(index)")
            if !ext.isEmpty { url.appendPathExtension(ext) }
            do {
                try write(url)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            } catch {
                return nil
            }
        }
        return nil
    }

    private static func writeTemporaryTextFile(_ text: String) -> URL? {
        writeUnique(named: "Dropped Text", extension: "txt") { url in
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
        }
    }

    /// The file-backed content type a non-file drop carries, if the shelf can
    /// hold it as a file. Deliberately narrow: text drags carry data types too
    /// (web archives, RTF), and those are better shelved as the plain text.
    private static func fileContentType(of provider: NSItemProvider) -> UTType? {
        provider.registeredTypeIdentifiers
            .compactMap { UTType($0) }
            .first { $0.conforms(to: .image) || $0.conforms(to: .pdf) || $0.conforms(to: .movie) }
    }

    /// Copies a provider's short-lived file into the drops folder.
    private static func keepCopy(of url: URL, suggestedName: String?, type: UTType) -> URL? {
        let name = suggestedName.map { ($0 as NSString).deletingPathExtension }
            ?? url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty
            ? (type.preferredFilenameExtension ?? "")
            : url.pathExtension
        return writeUnique(named: name.isEmpty ? "Dropped File" : name, extension: ext) { destination in
            try FileManager.default.copyItem(at: url, to: destination)
        }
    }
}
