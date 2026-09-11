import Foundation

extension Timer {
    /// A repeating timer registered in `RunLoop.Mode.common`.
    ///
    /// `Timer.scheduledTimer` registers in `.default` only, which means it
    /// stops firing for the duration of any *tracking* run loop — a menu open,
    /// a window or scroll view being dragged, a modal sheet. For a background
    /// job that is harmless, but every periodic timer in this app feeds
    /// something the user is watching: the playback progress and lyric line,
    /// the collapsed lyric activity, the audio visualizer, the media probe, the
    /// hover probe. On the default mode those freeze mid-interaction — the
    /// progress bar stalls while a list is scrolled, the visualizer flatlines
    /// during a menu, and the notch stops reacting to the pointer while the
    /// user is dragging inside it.
    ///
    /// `.common` is the union of the default, tracking, and modal modes, so the
    /// timer stays live throughout. Registering with `Timer(timeInterval:…)`
    /// and adding it by hand (rather than `scheduledTimer` and then adding)
    /// keeps it in exactly one mode set instead of two.
    ///
    /// The body is called on the main run loop; the timer does not retain
    /// itself or its owner, so callers must keep the returned timer and
    /// `invalidate()` it, and capture `self` weakly.
    static func scheduledRepeating(
        every interval: TimeInterval,
        _ body: @escaping () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in body() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
