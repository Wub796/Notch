import AppKit
import Foundation

enum NotchMediaSource: Equatable {
    case spotify
    case appleMusic
    case genericSystem
}

struct NotchMediaTrack: Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: NSImage?
    let duration: TimeInterval
    let currentPosition: TimeInterval
    let isPlaying: Bool
    let mediaSource: NotchMediaSource

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.duration == rhs.duration
            && lhs.currentPosition == rhs.currentPosition
            && lhs.isPlaying == rhs.isPlaying
            && lhs.mediaSource == rhs.mediaSource
    }
}
