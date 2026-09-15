import Foundation
import Observation

/// The Spotify login the Canvas feature runs on.
///
/// Canvas — the short looping video Spotify shows behind a track — has no
/// public API. The way every third-party client reaches it is the same: the
/// user signs in to Spotify in a real web view, the `sp_dc` session cookie
/// that login leaves behind is kept, and that cookie is exchanged for the
/// web-player's own bearer token, which the internal endpoints accept.
///
/// So this holds exactly one secret, the `sp_dc` cookie, in the keychain (it
/// is account access — see `KeychainStore`), and turns it into short-lived
/// access tokens on demand. It talks only to Spotify. Nothing here is sent
/// anywhere else, and the cookie never leaves the machine.
///
/// It is deliberately fragile-tolerant: these endpoints are private and change
/// without notice, so every failure path lands on a clear status rather than
/// taking the rest of the app down with it.
@Observable
final class SpotifyCanvasSession {
    static let shared = SpotifyCanvasSession()

    enum Status: Equatable {
        case signedOut
        case signedIn
        /// Signed in once, but the cookie no longer works — expired, or revoked
        /// by "sign out everywhere". The user has to sign in again.
        case expired
        case working
        case error(String)
    }

    private(set) var status: Status = .signedOut {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }

    /// Fired when the sign-in status changes, so the Canvas controller can
    /// re-evaluate the current track the moment a sign-in lands.
    var onStatusChange: ((Status) -> Void)?

    /// The cached web-player token and when it stops being valid. Never
    /// persisted — only the cookie is; the token is always re-minted.
    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast

    private static let cookieAccount = "spotify.sp_dc"

    /// Identifies as the web player. The token endpoint hands anonymous tokens
    /// to clients it does not recognise, so the platform header matters.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private init() {
        if KeychainStore.get(Self.cookieAccount) != nil {
            status = .signedIn
        }
    }

    /// Whether there is a cookie to work with at all — signed in, or signed in
    /// but currently refreshing or lapsed. Canvas fetches gate on this.
    var hasCookie: Bool {
        switch status {
        case .signedIn, .working, .expired: true
        case .signedOut, .error: false
        }
    }

    private var cookie: String? {
        KeychainStore.get(Self.cookieAccount)
    }

    // MARK: - Sign in / out

    /// Stores a captured `sp_dc` cookie and verifies it can mint a token.
    @MainActor
    func signIn(cookie rawCookie: String) async {
        let trimmed = rawCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.set(trimmed, for: Self.cookieAccount)
        accessToken = nil
        accessTokenExpiry = .distantPast
        status = .working
        if await token() != nil {
            status = .signedIn
        } else {
            status = .error("That sign-in didn’t take. Try again.")
        }
    }

    @MainActor
    func signOut() {
        KeychainStore.delete(Self.cookieAccount)
        accessToken = nil
        accessTokenExpiry = .distantPast
        status = .signedOut
    }

    // MARK: - Token

    /// A valid web-player bearer token, minted from the cookie and cached until
    /// it expires. nil when signed out or the cookie has stopped working — in
    /// which case the status is moved to `.expired` so the UI can prompt.
    func token() async -> String? {
        if let accessToken, Date() < accessTokenExpiry {
            return accessToken
        }
        guard let cookie else { return nil }

        var request = URLRequest(
            url: URL(string:
                "https://open.spotify.com/get_access_token?reason=transport&productType=web_player")!
        )
        request.setValue("sp_dc=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            await markExpired()
            return nil
        }

        // An anonymous token means the cookie was not accepted — treat it as a
        // dead session rather than a working one that returns nothing.
        if let anonymous = json["isAnonymous"] as? Bool, anonymous {
            await markExpired()
            return nil
        }
        guard let token = json["accessToken"] as? String, !token.isEmpty else {
            await markExpired()
            return nil
        }

        let expiryMs = (json["accessTokenExpirationTimestampMs"] as? Double) ?? 0
        let expiry = expiryMs > 0
            ? Date(timeIntervalSince1970: expiryMs / 1000)
            : Date().addingTimeInterval(3000)
        // A minute of headroom so a token never expires mid-request.
        accessTokenExpiry = expiry.addingTimeInterval(-60)
        accessToken = token
        await markSignedIn()
        return token
    }

    @MainActor private func markSignedIn() {
        if status != .signedIn { status = .signedIn }
    }

    @MainActor private func markExpired() {
        // Only from a state that expected to work: a background refresh
        // failing should not clobber a fresh `.signedOut`.
        if cookie != nil { status = .expired }
    }
}
