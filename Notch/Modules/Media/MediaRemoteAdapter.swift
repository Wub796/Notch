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
        /// The adapter's own estimate of the position *now*, only emitted by
        /// `get --now`. `elapsedTime` is not a live position on this platform:
        /// Spotify publishes it as 0 and leans on the pair's timestamp, which
        /// the player only refreshes when its state changes — so a long-lived
        /// stream holds a zero anchor from whenever the song last changed
        /// state, and a playhead read from it can be a minute or more behind.
        static let elapsedTimeNow = "elapsedTimeNow"
        static let timestamp = "timestamp"
        // Microsecond variants. The plain keys drop sub-second precision — the
        // framework serializes `timestamp` truncated to whole seconds, which
        // put the elapsed anchor ~0.5s behind real audio on average, and that
        // lag showed up directly as delayed lyric highlighting. The stream
        // runs with `--micros` so the capture time keeps its fraction.
        static let durationMicros = "durationMicros"
        static let elapsedTimeMicros = "elapsedTimeMicros"
        static let elapsedTimeNowMicros = "elapsedTimeNowMicros"
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

    /// One-shot now-playing query (the framework's `get` verb): spawns a
    /// short-lived process and returns the merged payload through the same
    /// normalization the stream uses. On Macs where MediaRemote's push
    /// notifications are gated this still answers — including the playing
    /// state, which the stream demonstrably fails to push on pause — and it
    /// needs no user consent, unlike the Apple Events fallback.
    func getNowPlaying(_ completion: @escaping ([String: Any]?) -> Void) {
        Self.oneShotQueue.async { [weak self] in
            guard let self,
                  let script = Self.scriptURL(),
                  let framework = Self.frameworkURL() else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = Self.perlURL()
            // `--now` makes the framework add its own estimate of the position
            // at query time. Without it the payload's only position field is
            // `elapsedTime`, which the player leaves at zero — and a query that
            // answers "0" looks like a deliberate rewind to the caller.
            process.arguments = [script.path, framework.path, "get", "--now"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            var payload: [String: Any]?
            if let object = try? JSONSerialization.jsonObject(with: data),
               let document = object as? [String: Any],
               let raw = document["payload"] as? [String: Any], !raw.isEmpty {
                // Same mapping the stream path uses, so the controller sees
                // identical keys (playbackRate, elapsedTime, timestamp…).
                payload = Self.normalizedInfo(from: raw, carried: Set(raw.keys))
            }
            DispatchQueue.main.async { completion(payload) }
        }
    }

    /// Dedicated queue for one-shot queries: `readDataToEndOfFile` blocks for
    /// the subprocess lifetime, which must never delay the stream's events.
    private static let oneShotQueue = DispatchQueue(label: "com.notchapp.MediaRemoteAdapter.get", qos: .utility)

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

        // The event's own keys, not just the merged state: the position pair
        // below may only be forwarded when *this* event carried it.
        let info = Self.normalizedInfo(from: state, carried: Set(payload.keys))
        DispatchQueue.main.async { [weak self] in
            guard let self, self.process != nil else { return }
            self.onInfo?(info)
        }
    }

    /// Maps the adapter's camelCase payload onto the controller's info keys.
    ///
    /// `carried` is the key set of the event being parsed. It matters for the
    /// position pair: the adapter merges diffs into one state, so an event
    /// carrying a fresh `timestampEpochMicros` but no elapsed would otherwise
    /// re-publish the *last* position with the *new* capture time — and the
    /// controller, reading that as "the playhead is here now", rewound the
    /// song. Spotify sends exactly that shape on track changes and rate
    /// updates, so mid-playback the playhead (and with it the lyric line, the
    /// scrubber and the remaining time) kept jumping back to wherever the last
    /// real position report had left it.
    private static func normalizedInfo(
        from state: [String: Any],
        carried: Set<String> = []
    ) -> [String: Any] {
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
        // A position is only worth reporting when it arrives with the instant
        // it was captured. Where it does not, the previous position stands and
        // the controller goes on extrapolating from it.
        let carriesElapsed = carried.contains(Key.elapsedTimeMicros)
            || carried.contains(Key.elapsedTime)
        let carriesTimestamp = carried.contains(Key.timestampEpochMicros)
            || carried.contains(Key.timestamp)
        var elapsed: TimeInterval?
        if let micros = Self.microsValue(state[Key.elapsedTimeMicros]) {
            elapsed = micros
        } else if let value = state[Key.elapsedTime] as? Double {
            elapsed = value
        } else if let value = state[Key.elapsedTime] as? Int {
            elapsed = Double(value)
        }
        // The live estimate, when this payload carries one (`get --now`).
        // Reported alongside — not instead of — the elapsed/timestamp pair:
        // the controller has to know the answer is a fresh position before it
        // is entitled to re-anchor to it.
        if let micros = Self.microsValue(state[Key.elapsedTimeNowMicros]) {
            info[MediaRemoteBridge.InfoKey.elapsedTimeNow] = micros
        } else if let value = state[Key.elapsedTimeNow] as? Double {
            info[MediaRemoteBridge.InfoKey.elapsedTimeNow] = value
        } else if let value = state[Key.elapsedTimeNow] as? Int {
            info[MediaRemoteBridge.InfoKey.elapsedTimeNow] = Double(value)
        }
        if carriesElapsed, let elapsed {
            info[MediaRemoteBridge.InfoKey.elapsedTime] = elapsed
            // Paired with the moment it was captured. An elapsed without its
            // own timestamp is read now, which is as close as this side can
            // get to when the player measured it.
            if carriesTimestamp, let capture = Self.captureDate(from: state) {
                info[MediaRemoteBridge.InfoKey.timestamp] = capture
            } else {
                info[MediaRemoteBridge.InfoKey.timestamp] = Date()
            }
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

    /// The instant the information was captured, from the microsecond epoch
    /// field when present and the string form otherwise.
    private static func captureDate(from state: [String: Any]) -> Date? {
        if let micros = state[Key.timestampEpochMicros] as? NSNumber {
            // Epoch microseconds → the exact capture instant, sub-second
            // fraction intact, so the extrapolated playhead agrees with the
            // audio instead of trailing it by up to a second.
            return Date(timeIntervalSince1970: micros.doubleValue / 1_000_000)
        }
        if let rawTimestamp = state[Key.timestamp] as? String {
            return timestampDate(from: rawTimestamp)
        }
        return nil
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
