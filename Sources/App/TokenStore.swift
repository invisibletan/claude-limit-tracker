import Foundation

/// Stores the optional OAuth token in a 0600-permission file under
/// Application Support. Deliberately NOT the macOS Keychain — this machine's
/// security policy forbids automated Keychain access, and a plain file the
/// user can inspect and delete is the transparent alternative.
enum TokenStore {
    static var tokenURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClaudeUsageTracker/token", isDirectory: false)
    }

    static func load() -> String? {
        guard let raw = try? String(contentsOf: tokenURL, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: tokenURL)
            return
        }
        let dir = tokenURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try trimmed.write(to: tokenURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: tokenURL)
    }
}
