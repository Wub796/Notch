import AppKit
import CoreServices
import Observation

/// Watches the folders files *arrive* in — Downloads, and wherever macOS is
/// configured to drop screenshots — and hands each new arrival to the notch.
///
/// This is the "catch" half of the shelf. The shelf already holds files you
/// put there deliberately; the point of this is the ones you didn't, which are
/// exactly the ones that cost you a trip to Finder. A download finishes or a
/// screenshot lands, the notch shows it, and you drag it where it was always
/// going to end up.
///
/// Deliberately event-driven, not polled. A `DispatchSource` on the directory's
/// own file descriptor wakes only when the directory is written to, so an idle
/// Downloads folder costs nothing at all — which matters here because, unlike
/// most of this app's periodic work, this has to keep running while the notch
/// is closed to be useful.
@Observable
final class FileCatcher {
    /// Which folder an arrival came from, so the notch can say so and the
    /// two sources can be switched independently.
    enum Source: String, Equatable {
        case download
        case screenshot

        var label: String {
            switch self {
            case .download: "Downloaded"
            case .screenshot: "Screenshot"
            }
        }

        var symbol: String {
            switch self {
            case .download: "arrow.down.circle.fill"
            case .screenshot: "camera.viewfinder"
            }
        }
    }

    struct Catch: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let source: Source
        let name: String
        var icon: NSImage

        static func == (lhs: Catch, rhs: Catch) -> Bool { lhs.url == rhs.url }
    }

    /// The arrival currently being shown, if any. One at a time: a burst of
    /// files is a burst of replacements, not a stack.
    private(set) var latest: Catch?

    /// Fired when a file is caught, so the notch can raise its activity.
    var onCatch: ((Catch) -> Void)?

    /// Keyed by folder, not by source. The screenshot location is a user
    /// preference and is very often set to Downloads — when the two sources
    /// resolve to the same folder, one watcher must serve both or every
    /// arrival is announced twice (and shelved twice).
    private var watchers: [URL: DirectoryWatcher] = [:]
    private var known: [URL: Set<URL>] = [:]
    private var dismissWork: DispatchWorkItem?

    /// How long an arrival stays on the notch before it eases away.
    private static let dwell: TimeInterval = 6

    /// Extensions that mean "still being written". A part-file appearing is not
    /// an arrival; the real file lands under a different name when it finishes.
    private static let partialExtensions: Set<String> = [
        "download", "crdownload", "part", "partial", "tmp", "opdownload",
    ]

    // MARK: - Lifecycle

    func start() {
        syncWatchers()
    }

    func stop() {
        dismissWork?.cancel()
        dismissWork = nil
        watchers.values.forEach { $0.stop() }
        watchers.removeAll()
        known.removeAll()
        latest = nil
    }

    /// Brings the running watchers in line with the settings. Called at launch
    /// and whenever either switch is flipped.
    func syncWatchers() {
        let settings = NotchSettings.shared
        var wanted: Set<URL> = []
        if settings.catchDownloads, let folder = Self.downloadsFolder {
            wanted.insert(folder.standardizedFileURL)
        }
        if settings.catchScreenshots, let folder = Self.screenshotFolder {
            wanted.insert(folder.standardizedFileURL)
        }

        // Snapshot the keys first. `watchers.keys` is a lazy view onto the
        // dictionary, so removing entries while iterating it mutates the thing
        // being iterated — which traps. Reached by turning a catcher off, or
        // by moving the screenshot folder.
        for folder in Array(watchers.keys) where !wanted.contains(folder) {
            watchers[folder]?.stop()
            watchers[folder] = nil
            known[folder] = nil
        }

        for folder in wanted where watchers[folder] == nil {
            // Seed the baseline before watching: everything already there is
            // history, not an arrival. Without this, enabling the feature
            // would announce the last six months of downloads.
            known[folder] = Self.contents(of: folder)
            let watcher = DirectoryWatcher(folder: folder) { [weak self] in
                self?.directoryChanged(folder)
            }
            watchers[folder] = watcher
            watcher.start()
        }
    }

    // MARK: - Arrivals

    private func directoryChanged(_ folder: URL) {
        let current = Self.contents(of: folder)
        let previous = known[folder] ?? current
        known[folder] = current

        // Only additions matter. A deletion or a rename away is not an arrival.
        let added = current.subtracting(previous).filter { !Self.isPartial($0) }
        guard !added.isEmpty else { return }

        // A finished download is a rename from its part-file, so the newest
        // addition is the one the user is waiting for.
        let newest = added.max { lhs, rhs in
            (Self.modified(lhs) ?? .distantPast) < (Self.modified(rhs) ?? .distantPast)
        }
        guard let url = newest else { return }

        // Classify the file, not the folder: when both sources point at the
        // same folder the folder cannot tell us which this is.
        let source = Self.source(for: url)
        let settings = NotchSettings.shared
        switch source {
        case .download: guard settings.catchDownloads else { return }
        case .screenshot: guard settings.catchScreenshots else { return }
        }
        present(url, from: source)
    }

    /// Whether an arrival is a screenshot or an ordinary download.
    ///
    /// Spotlight marks screen captures with `kMDItemIsScreenCapture`, which is
    /// the authoritative answer and survives renaming. It is not always indexed
    /// the instant the file appears, so a name check backs it up — and anything
    /// still unclear is a download, which is the safer default label.
    private static func source(for url: URL) -> Source {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let screenshotFolder = Self.screenshotFolder?.standardizedFileURL
        let downloadsFolder = Self.downloadsFolder?.standardizedFileURL

        // Unambiguous when the two folders differ.
        if parent == screenshotFolder, parent != downloadsFolder { return .screenshot }
        guard parent == screenshotFolder else { return .download }

        if let item = MDItemCreate(nil, url.path as CFString),
           let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool {
            return flag ? .screenshot : .download
        }
        return looksLikeScreenCapture(url) ? .screenshot : .download
    }

    /// Fallback for an unindexed file. macOS names screen captures with a
    /// localized prefix, so this matches the shape rather than one language:
    /// an image whose name carries a full date-and-time stamp.
    private static func looksLikeScreenCapture(_ url: URL) -> Bool {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf"]
        guard imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
        let name = url.deletingPathExtension().lastPathComponent
        // "…2026-09-12 at 10.30.00…" — a date and a time in one filename is
        // characteristic of a screen capture and rare in a downloaded file.
        let stamp = try? NSRegularExpression(
            pattern: #"\d{4}-\d{2}-\d{2}.*\d{1,2}[.:]\d{2}[.:]\d{2}"#
        )
        let range = NSRange(location: 0, length: (name as NSString).length)
        return stamp?.firstMatch(in: name, range: range) != nil
    }

    private func present(_ url: URL, from source: Source) {
        let item = Catch(
            url: url,
            source: source,
            name: url.lastPathComponent,
            icon: NSWorkspace.shared.icon(forFile: url.path)
        )
        latest = item
        onCatch?(item)
        loadThumbnail(for: item)

        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss(url)
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: work)
    }

    /// Clears the arrival, but only if it is still the one showing — a second
    /// file landing during the first one's dwell replaces it, and the first
    /// one's timer must not then clear the second.
    func dismiss(_ url: URL? = nil) {
        if let url, latest?.url != url { return }
        dismissWork?.cancel()
        dismissWork = nil
        latest = nil
    }

    /// Upgrades the generic file icon to a real Quick Look thumbnail. Screenshots
    /// especially: the point of showing one is that you can see which it is.
    private func loadThumbnail(for item: Catch) {
        ShelfController.thumbnail(for: item.url, size: 80) { [weak self] image in
            guard let self, let image, self.latest?.url == item.url else { return }
            self.latest?.icon = image
        }
    }

    // MARK: - Folders

    static var downloadsFolder: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    /// Where macOS is currently told to put screenshots. The default is the
    /// Desktop, but it is a documented preference and plenty of people move it.
    static var screenshotFolder: URL? {
        if let raw = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location"),
           !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }

    // MARK: - Helpers

    private static func contents(of folder: URL) -> Set<URL> {
        let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return Set(urls ?? [])
    }

    private static func isPartial(_ url: URL) -> Bool {
        partialExtensions.contains(url.pathExtension.lowercased())
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }
}

/// Wakes when a directory is written to.
///
/// A `DispatchSource` on the folder's own descriptor rather than FSEvents: this
/// watches two specific folders non-recursively, which is exactly the case the
/// simpler API covers, and it needs no event-stream bookkeeping across sleep.
private final class DirectoryWatcher {
    let folder: URL

    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var debounce: DispatchWorkItem?

    /// A single file landing produces several writes to the directory. Coalesce
    /// them, or one download is announced three times.
    private static let debounceInterval: TimeInterval = 0.35

    init(folder: URL, onChange: @escaping () -> Void) {
        self.folder = folder
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleNotify()
        }
        // Closes *this* descriptor, captured by value.
        //
        // Reading `self.descriptor` here instead was a real hazard: cancelling
        // is asynchronous, so a stop-then-start — which is exactly what
        // `syncWatchers` does when a folder changes — let the old source's
        // handler run *after* the new one had opened its descriptor and stored
        // it. The handler then closed the new fd, silently killing the fresh
        // watcher, and since fd numbers are reused it could close a descriptor
        // belonging to something else entirely. Capturing by value also means
        // the handler no longer needs `self`, so it stays correct during deinit.
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit {
        stop()
    }

    private func scheduleNotify() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.debounceInterval, execute: work
        )
    }
}
