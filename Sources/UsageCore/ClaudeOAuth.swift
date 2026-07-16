import Foundation
import CryptoKit

/// The OAuth 2.0 PKCE flow Claude Code itself uses, so the app can hold its
/// own `user:profile`-scoped credentials for the usage endpoint. The user
/// approves in their browser and pastes back the displayed code; refresh
/// tokens keep the session alive afterwards. No Keychain involved.
public enum ClaudeOAuth {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    public static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    public static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    public static let scopes = "org:create_api_key user:profile user:inference"

    public struct Credentials: Codable, Sendable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date?

        public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
        }

        public var needsRefresh: Bool {
            guard let expiresAt else { return false }
            return expiresAt.timeIntervalSinceNow < 60
        }

        /// Parses stored credentials: JSON (current format) or a legacy bare
        /// `sk-ant-…` access token from the old paste-a-token flow.
        public static func parse(fileContents: String) -> Credentials? {
            let trimmed = fileContents.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try? decoder.decode(Credentials.self, from: Data(trimmed.utf8))
            }
            if trimmed.hasPrefix("sk-ant-") {
                return Credentials(accessToken: trimmed)
            }
            return nil
        }

        public func serialized() throws -> String {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return String(decoding: try encoder.encode(self), as: UTF8.self)
        }
    }

    public struct PKCE: Sendable {
        public let verifier: String
        public let challenge: String
        public let state: String
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func challenge(forVerifier verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func generatePKCE() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        var stateBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, stateBytes.count, &stateBytes)
        return PKCE(
            verifier: verifier,
            challenge: challenge(forVerifier: verifier),
            state: base64URL(Data(stateBytes))
        )
    }

    public static func authorizeURL(pkce: PKCE) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components.url!
    }

    /// The approval page displays `code#state`; users sometimes copy only the code.
    public static func splitPastedCode(_ raw: String) -> (code: String, state: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = trimmed.firstIndex(of: "#") else { return (trimmed, nil) }
        let code = String(trimmed[..<hash])
        let state = String(trimmed[trimmed.index(after: hash)...])
        return (code, state.isEmpty ? nil : state)
    }

    public static func parseTokenResponse(_ data: Data, now: Date = Date()) throws -> Credentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = root["access_token"] as? String, !accessToken.isEmpty else {
            throw ClaudeOAuthError.malformedResponse(serverMessage(from: data))
        }
        var expiresAt: Date?
        if let expiresIn = (root["expires_in"] as? NSNumber)?.doubleValue {
            expiresAt = now.addingTimeInterval(expiresIn)
        }
        return Credentials(
            accessToken: accessToken,
            refreshToken: root["refresh_token"] as? String,
            expiresAt: expiresAt
        )
    }

    public static func exchange(
        pastedCode: String,
        pkce: PKCE,
        session: URLSession = .shared
    ) async throws -> Credentials {
        let (code, pastedState) = splitPastedCode(pastedCode)
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": pastedState ?? pkce.state,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier,
        ]
        return try await postToken(body: body, session: session)
    }

    public static func refresh(
        refreshToken: String,
        session: URLSession = .shared
    ) async throws -> Credentials {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        return try await postToken(body: body, session: session)
    }

    private static func postToken(body: [String: Any], session: URLSession) async throws -> Credentials {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClaudeOAuthError.httpStatus(http.statusCode, serverMessage(from: data))
        }
        return try parseTokenResponse(data)
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return (root["error_description"] as? String) ?? (root["error"] as? String)
    }
}

public enum ClaudeOAuthError: Error, LocalizedError {
    case httpStatus(Int, String?)
    case malformedResponse(String?)

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let message):
            return "Sign-in failed (HTTP \(code))\(message.map { ": \($0)" } ?? "")."
        case .malformedResponse(let message):
            return "Sign-in failed: \(message ?? "unexpected response from the token endpoint")."
        }
    }
}
