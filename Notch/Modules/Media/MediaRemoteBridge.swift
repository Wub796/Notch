import Foundation

/// Runtime bridge to the private MediaRemote framework, which is the only way
/// to observe system-wide now-playing metadata (any player: Music, Spotify,
/// Safari…) on macOS. Loaded with dlopen/dlsym so the app degrades gracefully
/// on systems where the framework or its symbols are unavailable (macOS 15.4+
/// restricted these entry points; MediaController falls back to Apple Events).
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    static let infoDidChange = Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    static let isPlayingDidChange = Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

    enum InfoKey {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
    }

    enum Command: Int32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias GetNowPlayingInfoFunc =
        @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias GetIsPlayingFunc =
        @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias RegisterNotificationsFunc =
        @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFunc =
        @convention(c) (Int32, CFDictionary?) -> Bool

    private var getNowPlayingInfoFunc: GetNowPlayingInfoFunc?
    private var getIsPlayingFunc: GetIsPlayingFunc?
    private var registerNotificationsFunc: RegisterNotificationsFunc?
    private var sendCommandFunc: SendCommandFunc?

    let isAvailable: Bool

    private init() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else {
            isAvailable = false
            return
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        getNowPlayingInfoFunc = symbol("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfoFunc.self)
        getIsPlayingFunc = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlayingFunc.self)
        registerNotificationsFunc = symbol("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterNotificationsFunc.self)
        sendCommandFunc = symbol("MRMediaRemoteSendCommand", as: SendCommandFunc.self)

        isAvailable = getNowPlayingInfoFunc != nil && registerNotificationsFunc != nil
    }

    /// Starts delivery of the now-playing notifications to the default
    /// NotificationCenter. Push-based: costs nothing between track changes.
    func registerForNotifications() {
        registerNotificationsFunc?(.main)
    }

    func nowPlayingInfo(_ completion: @escaping ([String: Any]) -> Void) {
        guard let getNowPlayingInfoFunc else {
            completion([:])
            return
        }
        getNowPlayingInfoFunc(.main) { info in
            completion(info as? [String: Any] ?? [:])
        }
    }

    func isPlaying(_ completion: @escaping (Bool) -> Void) {
        guard let getIsPlayingFunc else {
            completion(false)
            return
        }
        getIsPlayingFunc(.main) { playing in
            completion(playing)
        }
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        sendCommandFunc?(command.rawValue, nil) ?? false
    }
}
