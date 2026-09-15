import AppKit
import WebKit

/// The Spotify sign-in window.
///
/// It loads Spotify's real accounts page in a web view and waits for the
/// `sp_dc` cookie their login sets. The user types their password into
/// Spotify's own page — nothing here reads, relays, or stores anything but the
/// one session cookie, and only once it appears. A non-persistent data store
/// keeps the session out of any shared cookie jar; the cookie we keep goes to
/// the keychain via `SpotifyCanvasSession`.
@MainActor
final class SpotifyCanvasLoginWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    static let shared = SpotifyCanvasLoginWindowController()

    private var webView: WKWebView?
    private var session: SpotifyCanvasSession?
    private var pollTimer: Timer?
    private var captured = false

    private init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Sign in to Spotify"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SpotifyCanvasLoginWindowController does not support NSCoding")
    }

    func present(session: SpotifyCanvasSession) {
        self.session = session
        captured = false

        // A fresh, non-persistent store every time: signing in again starts
        // from a clean slate rather than a half-remembered session, and the
        // credentials never touch the default cookie jar.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.customUserAgent = SpotifyCanvasSession.userAgent
        window?.contentView = webView
        self.webView = webView

        webView.load(URLRequest(url: URL(string: "https://accounts.spotify.com/en/login")!))

        // The cookie can be set by a redirect that fires no navigation
        // callback, so poll the store as well as checking on each commit.
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForCookie() }
        }

        AppWindows.present(window)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in checkForCookie() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in checkForCookie() }
    }

    private func checkForCookie() {
        guard !captured, let webView, let session else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.captured else { return }
            guard let cookie = cookies.first(where: {
                $0.name == "sp_dc" && $0.domain.contains("spotify.com")
            }) else { return }
            self.captured = true
            let value = cookie.value
            Task { @MainActor in
                await session.signIn(cookie: value)
                self.finish()
            }
        }
    }

    private func finish() {
        pollTimer?.invalidate()
        pollTimer = nil
        // Tear the web view down so its session does not linger in memory.
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        window?.contentView = NSView()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        webView?.navigationDelegate = nil
        webView = nil
        session = nil
        AppWindows.didClose(window)
    }
}
