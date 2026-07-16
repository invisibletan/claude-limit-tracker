import Foundation
import UsageCore

/// Stores OAuth credentials in a 0600-permission JSON file under Application
/// Support. Deliberately NOT the macOS Keychain — this machine's security
/// policy forbids automated Keychain access, and a plain file the user can
/// inspect and delete is the transparent alternative.
enum TokenStore {
    static var tokenURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClaudeUsageTracker/token", isDirectory: false)
    }

    /// Reads credentials; also accepts a legacy bare `sk-ant-…` token file.
    static func loadCredentials() -> ClaudeOAuth.Credentials? {
        guard let raw = try? String(contentsOf: tokenURL, encoding: .utf8) else { return nil }
        return ClaudeOAuth.Credentials.parse(fileContents: raw)
    }

    static func save(_ credentials: ClaudeOAuth.Credentials) throws {
        let dir = tokenURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try credentials.serialized().write(to: tokenURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: tokenURL)
    }
}
