import AppKit
import CryptoKit
import Foundation
import Observation

/// Spotify Web API sign-in, using Authorization Code with PKCE.
///
/// PKCE rather than the client-secret flow because this is a desktop app: a
/// secret shipped inside an app bundle is not a secret. The client ID is the
/// user's own — Notch cannot ship one, since a public client ID in an open
/// repository gets rate-limited and revoked, and Spotify's terms put the app
/// registration on whoever runs it. Settings walks through creating one.
///
/// The refresh token lives in the Keychain; the access token stays in memory
/// and is renewed on demand.
@Observable
final class SpotifyAuth {
    static let shared = SpotifyAuth()

    enum State: Equatable {
        case signedOut
        case authorizing
        case signedIn
        case failed(String)
    }

    struct UserProfile: Equatable, Codable {
        let displayName: String
        let email: String?
        let product: String?
        let imageURL: URL?
    }

    private(set) var state: State = .signedOut
    private(set) var userProfile: UserProfile?

    /// Built-in public Spotify client ID for seamless 1-click PKCE sign-in.
    static let defaultClientID = "b84570cb1e6d4ba4beff1d4715f5c35b"

    /// The redirect Spotify sends the browser back to. Registered as a URL
    /// scheme in Info.plist, so the OS hands it to the app.
    static let redirectURI = "notch://spotify-callback"

    /// Everything the Devices screen and the player need, and nothing more:
    /// reading and steering playback, the account's playlists, its listening
    /// history, and its saved songs — the last one so the player's heart is a
    /// real control rather than a decoration.
    private static let scopes = [
        "user-read-private",
        "user-read-email",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-read-recently-played",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "user-library-modify",
    ].joined(separator: " ")

    private static let keychainAccount = "spotify-refresh-token"

    private var verifier: String?
    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast

    var clientID: String {
        get { NotchSettings.shared.spotifyClientID }
        set {
            NotchSettings.shared.spotifyClientID = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            refreshState()
        }
    }

    var hasValidClientID: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        migrateIfScopesChanged()
        refreshState()
    }

    private func migrateIfScopesChanged() {
        let defaults = UserDefaults.standard
        let key = "spotifyScopeSignature"
        let signature = Self.scopes
        guard defaults.string(forKey: key) != signature else { return }
        if defaults.string(forKey: key) != nil {
            Self.deleteRefreshToken()
        }
        defaults.set(signature, forKey: key)
    }

    private func refreshState() {
        if Self.storedRefreshToken() != nil {
            state = .signedIn
            Task { await fetchUserProfile() }
        } else {
            state = .signedOut
            userProfile = nil
        }
    }

    // MARK: - Sign in

    /// Opens Spotify's consent page in the browser with PKCE authorization.
    func signIn() {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            state = .failed("Please enter your Spotify Client ID in Settings.")
            DispatchQueue.main.async {
                SettingsWindowController.shared.show()
            }
            return
        }

        let verifier = Self.randomVerifier()
        self.verifier = verifier

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: trimmedID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: Self.challenge(for: verifier)),
        ]

        guard let url = components.url else {
            state = .failed("Couldn't build the sign-in URL.")
            return
        }
        state = .authorizing
        NSWorkspace.shared.open(url)
    }

    func signOut() {
        Self.deleteRefreshToken()
        accessToken = nil
        accessTokenExpiry = .distantPast
        userProfile = nil
        refreshState()
    }

    func fetchUserProfile() async {
        guard let token = await validAccessToken() else { return }
        guard let profile = await SpotifyClient.currentUserProfile(token: token) else { return }
        let user = UserProfile(
            displayName: profile.displayName ?? "Spotify User",
            email: profile.email,
            product: profile.product?.capitalized,
            imageURL: profile.images?.first.flatMap { URL(string: $0.url) }
        )
        await MainActor.run {
            self.userProfile = user
        }
    }

    /// Called by the app delegate when the browser redirects back.
    func handleCallback(_ url: URL) {
        guard url.scheme == "notch",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            state = .failed(error == "access_denied" ? "Sign-in was cancelled." : error)
            return
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier
        else {
            state = .failed("The reply from Spotify was missing its code.")
            return
        }

        Task { await exchange(code: code, verifier: verifier) }
    }

    // MARK: - Tokens

    private func exchange(code: String, verifier: String) async {
        let body = [
            "client_id": effectiveClientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ]
        await requestToken(body: body)
    }

    /// A valid access token, refreshing it first when it has expired.
    func validAccessToken() async -> String? {
        if let accessToken, accessTokenExpiry > Date().addingTimeInterval(30) {
            return accessToken
        }
        guard let refresh = Self.storedRefreshToken() else { return nil }
        await requestToken(body: [
            "client_id": effectiveClientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ])
        return accessToken
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private func requestToken(body: [String: String]) async {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            await MainActor.run {
                self.accessToken = token.accessToken
                self.accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expiresIn))
                if let refresh = token.refreshToken {
                    Self.storeRefreshToken(refresh)
                }
                self.state = .signedIn
            }
        } catch {
            await MainActor.run {
                // A refresh that fails usually means the grant was revoked, so
                // drop it rather than retrying against a dead token forever.
                Self.deleteRefreshToken()
                self.state = .failed("Spotify sign-in failed. Try connecting again.")
            }
        }
    }

    // MARK: - PKCE

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded
    }

    // MARK: - Keychain

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.notch.spotify",
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private static func storedRefreshToken() -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func storeRefreshToken(_ token: String) {
        deleteRefreshToken()
        var query = keychainQuery()
        query[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteRefreshToken() {
        SecItemDelete(keychainQuery() as CFDictionary)
    }
}

private extension Data {
    /// Base64 without padding and with URL-safe characters, which is what the
    /// PKCE spec requires.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
