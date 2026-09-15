import Foundation

/// Client for the bundled mediaremote-adapter (ungive/mediaremote-adapter,
/// BSD-3-Clause, © 2025 Jonas van den Berg — see MediaRemoteAdapter/LICENSE).
/// This is the now-playing source that works on macOS 15.4+, where an app's
/// own MediaRemote calls are gated and answer with silence ("Operation not
/// permitted").
///
/// How it works: /usr/bin/perl is a system binary that already carries the
/// entitlement to talk to mediaremoted, so running the adapter's Perl script
/// under it returns real now-playing data. The script prints one JSON document
/// per stdout line — the full state when `diff` is false, a merged update when
/// true. This class owns the subprocess: spawn, line-parse, merge, terminate.
final class MediaRemoteAdapter {
    /// Adapter payload keys (camelCase, as documented by the adapter).
    enum Key {
        static let processIdentifier = "processIdentifier"
        static let playing = "playing"
        static let title = "title"
        static let artist = "artist"
        static let album = "album"
        static let duration = "duration"
        static let elapsedTime = "elapsedTime"
        static let timestamp = "timestamp"
        // Microsecond variants. The plain keys drop sub-second precision — the
        // framework serializes `timestamp` truncated to whole seconds, which
        // put the elapsed anchor ~0.5s behind real audio on average, and that
        // lag showed up directly as delayed lyric highlighting. The stream
        // runs with `--micros` so the capture time keeps its fraction.
        static let durationMicros = "durationMicros"
        static let elapsedTimeMicros = "elapsedTimeMicros"
        static let timestampEpochMicros = "timestampEpochMicros"
        static let playbackRate = "playbackRate"
        static let artworkData = "artworkData"
        static let mediaType = "mediaType"
    }

    /// MRCommand IDs the adapter's `send` command understands (kMRPlay = 0,
    /// kMRATogglePlayPause = 2, kMRNextTrack = 4, kMRPreviousTrack = 5).
    enum Command: Int32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    /// Called on the main queue with the merged now-playing info whenever the
    /// stream reports a change. An empty dictionary means the adapter says no
    /// player is reporting right now.
    var onInfo: (([String: Any]) -> Void)?

    /// Called on the main queue when the stream process died on its own —
    /// never for stop(). The owner decides whether to restart or fall back.
    var onTerminated: (() -> Void)?

    private var process: Process?
    private var pipe: Pipe?
    private var readSource: DispatchSourceRead?
    private var lineBuffer = Data()
    /// The merged full state. diff=false replaces it; diff=true merges, with
    /// null values deleting their keys ("when a key is not present anymore,
    /// it's set to null in the payload and its previous value should be
    /// removed").
    private var state: [String: Any] = [:]
    /// Whether any non-empty payload has arrived yet. The stream's *first*
    /// event is an empty full-state payload even while a player is active —
    /// that is initial state, not "nothing playing" — so nothing is forwarded
    /// until real data has been seen.
    private var hasSeenNonEmpty = false
    private var stopped = false
    private let queue = DispatchQueue(label: "notch.mediaremote-adapter")

    /// Whether the script and framework are present in the app bundle.
    static var isBundled: Bool {
        scriptURL() != nil && frameworkURL() != nil
    }

    /// The script and framework both ship as plain resources under Resources/.
    private static func scriptURL() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("mediaremote-adapter.pl")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func frameworkURL() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("MediaRemoteAdapter.framework")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func perlURL() -> URL {
        URL(fileURLWithPath: "/usr/bin/perl")
    }

    /// Runs the adapter's `test` command: "Tests if the adapter is entitled to
    /// use the MediaRemote framework. An exit code other than 0 indicates the
    /// adapter is non-functional." Blocking, so only call off the main thread.
    static func verifyFunctional() -> Bool {
        guard isBundled, let script = scriptURL(), let framework = frameworkURL() else { return false }
        let process = Process()
        process.executableURL = perlURL()
        process.arguments = [script.path, framework.path, "test"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Spawns the stream. Updates arrive on `onInfo` until stop() or the
    /// process dies. May be called again after termination (one-shot restart).
    func startStream() {
        queue.async { [weak self] in
            self?.startStreamOnQueue()
        }
    }

    private func startStreamOnQueue() {
        guard process == nil,
              let script = Self.scriptURL(),
              let framework = Self.frameworkURL()
        else { return }

        let newProcess = Process()
        let newPipe = Pipe()
        newProcess.executableURL = Self.perlURL()
        // `--micros` keeps the timestamp at microsecond precision; without it
        // the framework truncates the capture time to whole seconds, which
        // put the elapsed anchor ~0.5s behind the audio — late lyrics.
        newProcess.arguments = [script.path, framework.path, "stream", "--micros"]
        newProcess.standardOutput = newPipe
        newProcess.standardError = FileHandle.nullDevice
        stopped = false
        process = newProcess
        pipe = newPipe
        lineBuffer = Data()
        state = [:]
        hasSeenNonEmpty = false

        let handle = newPipe.fileHandleForReading
        let source = DispatchSource.makeReadSource(
            fileDescriptor: handle.fileDescriptor,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        source.resume()
        readSource = source

        newProcess.terminationHandler = { [weak self] _ in
            // Drain the pipe tail so a final line that arrived with EOF is not
            // lost, then hand the death to the owner on the main queue.
            guard let self else { return }
            self.queue.async {
                self.readSource?.cancel()
                self.readSource = nil
                let tail = handle.readDataToEndOfFile()
                if !tail.isEmpty { self.consume(tail) }
                self.process = nil
                self.pipe = nil
                guard !self.stopped else { return }
                DispatchQueue.main.async {
                    self.onTerminated?()
                }
            }
        }

        do {
            try newProcess.run()
        } catch {
            process = nil
            pipe = nil
            readSource?.cancel()
            readSource = nil
            DispatchQueue.main.async { [weak self] in
                self?.onTerminated?()
            }
        }
    }

    /// One-shot `send` of a playback command (kMRCommand ID). Off the main thread.
    func sendCommand(_ command: Command) {
        spawnOneShot(arguments: ["send", "\(command.rawValue)"])
    }

    /// One-shot `seek` to an absolute position; the adapter expects microseconds.
    /// Off the main thread.
    func seek(to seconds: TimeInterval) {
        spawnOneShot(arguments: ["seek", "\(Int(seconds * 1_000_000))"])
    }

    private func spawnOneShot(arguments: [String]) {
        queue.async {
            guard let script = Self.scriptURL(),
                  let framework = Self.frameworkURL()
            else { return }
            let process = Process()
            process.executableURL = Self.perlURL()
            process.arguments = [script.path, framework.path] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    deinit {
        // Nothing reaps a spawned child when the parent exits; without this
        // the perl stream would linger holding a MediaRemote connection until
        // it happened to write to the closed pipe (SIGPIPE). Safe to sync on
        // the queue: no in-flight queue block can hold this instance strongly
        // once deinit begins.
        queue.sync {
            stopped = true
            readSource?.cancel()
            readSource = nil
            if let process = process, process.isRunning {
                process.terminate()
            }
            process = nil
        }
    }

    /// Tears the stream down (SIGTERM, which the script exits on). Safe to
    /// call multiple times; never fires onTerminated.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.readSource?.cancel()
            self.readSource = nil
            if let process = self.process, process.isRunning {
                process.terminate()
            }
            self.process = nil
            self.pipe = nil
        }
    }

    // MARK: - Line parsing

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer[..<newline]
            lineBuffer = Data(lineBuffer[lineBuffer.index(after: newline)...])
            parse(line)
        }
    }

    private func parse(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let document = object as? [String: Any],
              document["type"] as? String == "data",
              let payload = document["payload"] as? [String: Any]
        else { return }

        let isDiff = document["diff"] as? Bool ?? false
        if isDiff {
            for (key, value) in payload {
                if value is NSNull {
                    state.removeValue(forKey: key)
                } else {
                    state[key] = value
                }
            }
        } else {
            state = payload
        }
        if !payload.isEmpty {
            hasSeenNonEmpty = true
        }

        // The leading empty full-state event is initial state — the adapter
        // emits it before now-playing data resolves, even while a player is
        // active — so forward nothing until real data has arrived.
        guard hasSeenNonEmpty else { return }

        let info = Self.normalizedInfo(from: state)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.process != nil else { return }
            self.onInfo?(info)
        }
    }

    /// Maps the adapter's camelCase payload onto the controller's info keys.
    private static func normalizedInfo(from state: [String: Any]) -> [String: Any] {
        var info: [String: Any] = [:]

        if let value = state[Key.title] as? String {
            info[MediaRemoteBridge.InfoKey.title] = value
        }
        if let value = state[Key.artist] as? String {
            info[MediaRemoteBridge.InfoKey.artist] = value
        }
        if let value = state[Key.album] as? String {
            info[MediaRemoteBridge.InfoKey.album] = value
        }
        if let micros = Self.microsValue(state[Key.durationMicros]) {
            info[MediaRemoteBridge.InfoKey.duration] = micros
        } else if let value = state[Key.duration] as? Double {
            info[MediaRemoteBridge.InfoKey.duration] = value
        } else if let value = state[Key.duration] as? Int {
            info[MediaRemoteBridge.InfoKey.duration] = Double(value)
        }
        if let micros = Self.microsValue(state[Key.elapsedTimeMicros]) {
            info[MediaRemoteBridge.InfoKey.elapsedTime] = micros
        } else if let value = state[Key.elapsedTime] as? Double {
            info[MediaRemoteBridge.InfoKey.elapsedTime] = value
        } else if let value = state[Key.elapsedTime] as? Int {
            info[MediaRemoteBridge.InfoKey.elapsedTime] = Double(value)
        }
        if let micros = state[Key.timestampEpochMicros] as? NSNumber {
            // Epoch microseconds → the exact capture instant, sub-second
            // fraction intact, so the extrapolated playhead agrees with the
            // audio instead of trailing it by up to a second.
            info[MediaRemoteBridge.InfoKey.timestamp] =
                Date(timeIntervalSince1970: micros.doubleValue / 1_000_000)
        } else if let rawTimestamp = state[Key.timestamp] as? String,
                  let date = Self.timestampDate(from: rawTimestamp) {
            info[MediaRemoteBridge.InfoKey.timestamp] = date
        }
        // `playing` wins over `playbackRate`. It is the adapter's own answer to
        // "is this app playing" and is kept current, while the rate is only
        // sent when the player chooses to — so the merged state could hold a
        // rate of 1 from before a pause long after `playing` went false. Every
        // later diff then re-reported the track as playing, and the lyrics
        // carried on through the pause.
        let rate = (state[Key.playbackRate] as? NSNumber)?.doubleValue
        if let playing = state[Key.playing] as? Bool {
            info[MediaRemoteBridge.InfoKey.playbackRate] = playing ? max(rate ?? 1, 1) : 0.0
        } else if let rate {
            info[MediaRemoteBridge.InfoKey.playbackRate] = rate
        }
        if let base64 = state[Key.artworkData] as? String,
           let data = Data(base64Encoded: base64) {
            info[MediaRemoteBridge.InfoKey.artworkData] = data
        }

        // Keys the controller reads directly from the adapter payload.
        if let pid = state[Key.processIdentifier] as? Int {
            info[Key.processIdentifier] = pid
        }
        if let type = state[Key.mediaType] as? String {
            info[Key.mediaType] = type
        }
        return info
    }

    /// Converts a microsecond-valued payload number to seconds.
    private static func microsValue(_ raw: Any?) -> TimeInterval? {
        guard let number = raw as? NSNumber else { return nil }
        return number.doubleValue / 1_000_000
    }

    /// Fresh formatters per call: parsing happens once per track change, and
    /// static formatters would be flagged as non-Sendable shared state under
    /// strict concurrency.
    private static func timestampDate(from raw: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }
}
