import Foundation
import Testing
@testable import UsageCore

@Suite struct PKCETests {
    @Test func challengeMatchesRFC7636Vector() {
        // RFC 7636 appendix B test vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(ClaudeOAuth.challenge(forVerifier: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedPKCEIsWellFormed() {
        let pkce = ClaudeOAuth.generatePKCE()
        let base64URLChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(pkce.verifier.count >= 43)
        #expect(pkce.verifier.unicodeScalars.allSatisfy { base64URLChars.contains($0) })
        #expect(pkce.challenge == ClaudeOAuth.challenge(forVerifier: pkce.verifier))
        #expect(!pkce.state.isEmpty)
    }

    @Test func authorizeURLCarriesAllParameters() throws {
        let pkce = ClaudeOAuth.PKCE(verifier: "v", challenge: "c123", state: "s456")
        let url = ClaudeOAuth.authorizeURL(pkce: pkce)
        #expect(url.host() == "claude.ai")
        #expect(url.path() == "/oauth/authorize")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["code"] == "true")
        #expect(query["client_id"] == ClaudeOAuth.clientID)
        #expect(query["response_type"] == "code")
        #expect(query["redirect_uri"] == "https://platform.claude.com/oauth/code/callback")
        #expect(query["scope"] == "user:inference user:profile user:sessions:claude_code user:mcp_servers")
        #expect(query["code_challenge"] == "c123")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == "s456")
    }

    @Test func formEncoding() {
        let encoded = ClaudeOAuth.formEncode([
            "grant_type": "authorization_code",
            "scope": "user:profile user:inference",
            "redirect_uri": "https://platform.claude.com/oauth/code/callback",
        ])
        #expect(encoded == "grant_type=authorization_code"
            + "&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback"
            + "&scope=user%3Aprofile%20user%3Ainference")
    }
}

@Suite struct OAuthParsingTests {
    @Test func splitPastedCode() {
        let both = ClaudeOAuth.splitPastedCode("  abc123#state456\n")
        #expect(both.code == "abc123")
        #expect(both.state == "state456")

        let codeOnly = ClaudeOAuth.splitPastedCode("abc123")
        #expect(codeOnly.code == "abc123")
        #expect(codeOnly.state == nil)
    }

    @Test func parseTokenResponse() throws {
        let now = Date()
        let payload = """
        {"access_token": "at-1", "refresh_token": "rt-1", "expires_in": 28800, "token_type": "Bearer"}
        """.data(using: .utf8)!
        let creds = try ClaudeOAuth.parseTokenResponse(payload, now: now)
        #expect(creds.accessToken == "at-1")
        #expect(creds.refreshToken == "rt-1")
        let expiresAt = try #require(creds.expiresAt)
        #expect(abs(expiresAt.timeIntervalSince(now) - 28800) < 1)
    }

    @Test func parseTokenResponseRejectsErrorPayload() {
        let payload = #"{"error": {"type": "invalid_grant", "message": "expired"}}"#.data(using: .utf8)!
        #expect(throws: ClaudeOAuthError.self) { try ClaudeOAuth.parseTokenResponse(payload) }
    }

    @Test func credentialsRoundTripAndLegacyMigration() throws {
        let creds = ClaudeOAuth.Credentials(
            accessToken: "at-2",
            refreshToken: "rt-2",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let restored = try #require(ClaudeOAuth.Credentials.parse(fileContents: try creds.serialized()))
        #expect(restored.accessToken == "at-2")
        #expect(restored.refreshToken == "rt-2")
        #expect(restored.expiresAt == creds.expiresAt)

        // Legacy file: bare token from the old paste-a-token flow.
        let legacy = try #require(ClaudeOAuth.Credentials.parse(fileContents: "sk-ant-oat01-legacy\n"))
        #expect(legacy.accessToken == "sk-ant-oat01-legacy")
        #expect(legacy.refreshToken == nil)
        #expect(!legacy.needsRefresh)

        #expect(ClaudeOAuth.Credentials.parse(fileContents: "garbage") == nil)
    }

    @Test func needsRefreshOnlyNearExpiry() {
        var creds = ClaudeOAuth.Credentials(accessToken: "a", expiresAt: Date().addingTimeInterval(3600))
        #expect(!creds.needsRefresh)
        creds.expiresAt = Date().addingTimeInterval(30)
        #expect(creds.needsRefresh)
        creds.expiresAt = nil
        #expect(!creds.needsRefresh)
    }
}
