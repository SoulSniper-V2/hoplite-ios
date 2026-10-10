import AuthenticationServices
import UIKit
import CryptoKit
import Foundation
import Security

nonisolated enum Keychain {
    private static let service = "sh.hoplite.mobile"

    static func set(_ data: Data?, for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }
}

nonisolated struct OAuthTokens: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

/// Stored sign-in. Persisted in the Keychain, never in UserDefaults.
nonisolated enum StoredCredential: Codable, Sendable, Equatable {
    case apiKey(String)
    case oauth(OAuthTokens)

    private static let account = "credential.v1"

    static func load() -> StoredCredential? {
        Keychain.get(account).flatMap { try? JSONDecoder().decode(StoredCredential.self, from: $0) }
    }

    func save() { Keychain.set(try? JSONEncoder().encode(self), for: Self.account) }
    static func clear() { Keychain.set(nil, for: account) }

    var label: String {
        switch self {
        case .apiKey(let key): "API key · \(key.prefix(8))…\(key.suffix(4))"
        case .oauth: "Signed in with Hoplite"
        }
    }
}

/// OAuth 2.1 authorization-code + PKCE against Hoplite's authorization server, with
/// dynamic client registration so the app ships no client secret.
@MainActor
final class HopliteOAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated static let issuer = URL(string: "https://api.hoplite.sh/api/auth")!
    nonisolated static let redirectURI = "hoplite-ios://oauth/callback"
    nonisolated static let scopes = "openid profile email offline_access api:read api:write project:read thread:create thread:read thread:update"

    private var session: ASWebAuthenticationSession?

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
            return scene.keyWindow ?? ASPresentationAnchor(windowScene: scene)
        }
    }

    func signIn() async throws -> OAuthTokens {
        let clientId = try await registeredClientId()
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(24)

        var components = URLComponents(url: Self.issuer.appending(path: "oauth2/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "consent"),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callback: .customScheme("hoplite-ios")) { url, error in
                if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? URLError(.cancelled)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw APIError(status: 0, code: "oauth_state_mismatch") }
        if let error = items.first(where: { $0.name == "error" })?.value { throw APIError(status: 0, code: error) }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw APIError(status: 0, code: "oauth_missing_code") }

        return try await Self.token(form: [
            "grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI,
            "client_id": clientId, "code_verifier": verifier,
        ])
    }

    nonisolated static func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refresh = tokens.refreshToken, let clientId = UserDefaults.standard.string(forKey: "oauth.clientId") else {
            throw APIError(status: 401, code: "auth_required")
        }
        var next = try await token(form: ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientId])
        if next.refreshToken == nil { next.refreshToken = refresh }
        return next
    }

    private func registeredClientId() async throws -> String {
        if let id = UserDefaults.standard.string(forKey: "oauth.clientId") { return id }
        var request = URLRequest(url: Self.issuer.appending(path: "oauth2/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Hoplite for iPhone",
            "redirect_uris": [Self.redirectURI],
            "token_endpoint_auth_method": "none",
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        struct R: Decodable { var client_id: String }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let id = try? JSONDecoder().decode(R.self, from: data).client_id
        else { throw APIError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, code: "oauth_registration_failed") }
        UserDefaults.standard.set(id, forKey: "oauth.clientId")
        return id
    }

    nonisolated private static func token(form: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: issuer.appending(path: "oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(status: 0, code: "network") }
        guard (200..<300).contains(http.statusCode) else { throw HopliteClient.error(from: data, response: http) }
        struct R: Decodable { var access_token: String; var refresh_token: String?; var expires_in: Double? }
        let r = try JSONDecoder().decode(R.self, from: data)
        return OAuthTokens(accessToken: r.access_token, refreshToken: r.refresh_token, expiresAt: Date().addingTimeInterval(r.expires_in ?? 3600))
    }

    nonisolated private static func randomString(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URL
    }
}

extension Data {
    nonisolated var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
