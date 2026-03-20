import Foundation
import AuthenticationServices
import Security
import Combine
import CryptoKit
#if os(macOS)
import AppKit
#endif

@MainActor
final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated: Bool = false
    @Published var accessToken: String? = nil

    private let service = "com.countriesxl.auth"
    private let account = "xenforo"
    
    private var currentSession: ASWebAuthenticationSession?
    private var expectedState: String?
    private var codeVerifier: String?

    // Configure with your OAuth2 details
    struct Config {
        var clientID: String
        var clientSecret: String?
        var redirectURI: String
        var authURL: URL
        var tokenURL: URL
        var revokeURL: URL
        var scope: String
    }

    var config: Config?

    func configure(clientID: String, clientSecret: String? = nil, redirectURI: String, authURL: URL, tokenURL: URL, revokeURL: URL, scope: String = "read write") {
        self.config = Config(clientID: clientID, clientSecret: clientSecret, redirectURI: redirectURI, authURL: authURL, tokenURL: tokenURL, revokeURL: revokeURL, scope: scope)
    }

    private func loadConfigFromPlist() {
        guard config == nil else { return }
        let plist = Bundle.main.infoDictionary
        guard let clientID = plist?["XenForoOAuthClientID"] as? String, !clientID.isEmpty else { return }
        guard let redirectURI = plist?["XenForoOAuthRedirectURI"] as? String, !redirectURI.isEmpty else { return }
        guard let authURLString = plist?["XenForoOAuthAuthURL"] as? String,
              let tokenURLString = plist?["XenForoOAuthTokenURL"] as? String,
              let revokeURLString = plist?["XenForoOAuthRevokeURL"] as? String,
              let authURL = URL(string: authURLString),
              let tokenURL = URL(string: tokenURLString),
              let revokeURL = URL(string: revokeURLString) else { return }
        let scope = (plist?["XenForoOAuthScope"] as? String) ?? "read write"
        let clientSecret = plist?["XenForoOAuthClientSecret"] as? String
        configure(clientID: clientID, clientSecret: clientSecret, redirectURI: redirectURI, authURL: authURL, tokenURL: tokenURL, revokeURL: revokeURL, scope: scope)
    }

    func restoreFromKeychain() {
        if let token: String = Keychain.read(service: service, account: account) {
            accessToken = token
            isAuthenticated = true
        }
    }

    func signOut() {
        Keychain.delete(service: service, account: account)
        accessToken = nil
        isAuthenticated = false
    }

    func signIn() async {
        loadConfigFromPlist()
        guard let config else { return }

        let state = UUID().uuidString
        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        self.expectedState = state
        self.codeVerifier = verifier

        var components = URLComponents(url: config.authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "scope", value: config.scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else { return }

        let callbackScheme = URL(string: config.redirectURI)?.scheme
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self else { return }
            Task { @MainActor in
                if let callbackURL, error == nil {
                    await self.handleCallback(url: callbackURL, expectedState: state)
                }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.currentSession = session
        session.start()
    }
    
    func handleIncomingURL(_ url: URL) {
        guard let expectedState = expectedState else { return }
        Task { @MainActor in
            await self.handleCallback(url: url, expectedState: expectedState)
            self.expectedState = nil
            self.currentSession?.cancel()
            self.currentSession = nil
        }
    }

    private func handleCallback(url: URL, expectedState: String) async {
        guard let config else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == expectedState else { return }

        guard let verifier = codeVerifier else { return }
        codeVerifier = nil

        // Exchange code for token
        var req = URLRequest(url: config.tokenURL)
        req.httpMethod = "POST"
        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            "grant_type=authorization_code",
            "code=\(code)",
            "client_id=\(config.clientID)",
            "redirect_uri=\(config.redirectURI)",
            "code_verifier=\(verifier)"
        ]
        if let secret = config.clientSecret, !secret.isEmpty {
            params.append("client_secret=\(secret)")
        }
        let body = params.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            if let token = try? JSONDecoder().decode(TokenResponse.self, from: data).access_token {
                Keychain.save(token, service: service, account: account)
                accessToken = token
                isAuthenticated = true
            }
        } catch {
            // handle error
        }
    }

    func revokeTokenIfPossible() async {
        guard let config, let token = accessToken else { return }
        var req = URLRequest(url: config.revokeURL)
        req.httpMethod = "POST"
        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            "token=\(token)",
            "client_id=\(config.clientID)"
        ]
        if let secret = config.clientSecret, !secret.isEmpty {
            params.append("client_secret=\(secret)")
        }
        req.httpBody = params.joined(separator: "&").data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - PKCE
    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        return base64URLEncode(data)
    }

    private static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return base64URLEncode(Data(digest))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            return window
        }
        #endif
        return ASPresentationAnchor()
    }
}

private struct TokenResponse: Decodable {
    let access_token: String
}

// MARK: - Simple Keychain Helpers
enum Keychain {
    static func save(_ string: String, service: String, account: String) {
        let data = Data(string.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read<T: LosslessStringConvertible>(service: String, account: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let string = String(data: data, encoding: .utf8) else { return nil }
        return T(string)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

