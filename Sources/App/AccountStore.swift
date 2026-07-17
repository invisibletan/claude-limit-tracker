import Foundation

/// A named Claude account with its own token.
struct Account: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var token: String
    var showInMenuBar: Bool = true
}

/// Persists up to 10 accounts as a JSON file (0600) under Application Support.
/// Deliberately NOT the macOS Keychain (this machine's security policy forbids
/// automated Keychain access); a plain file the user can inspect and delete.
enum AccountStore {
    static let maxAccounts = 10

    private static var baseDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageTracker", isDirectory: true)
    }
    private static var accountsURL: URL { baseDir.appendingPathComponent("accounts.json", isDirectory: false) }
    private static var legacyTokenURL: URL { baseDir.appendingPathComponent("token", isDirectory: false) }

    static func load() -> [Account] {
        if let data = try? Data(contentsOf: accountsURL),
           let accounts = try? JSONDecoder().decode([Account].self, from: data) {
            return accounts
        }
        // Migrate a legacy single-token file into one named account.
        if let raw = try? String(contentsOf: legacyTokenURL, encoding: .utf8) {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                let migrated = [Account(name: "Account 1", token: token, showInMenuBar: true)]
                try? save(migrated)
                try? FileManager.default.removeItem(at: legacyTokenURL)
                return migrated
            }
        }
        return []
    }

    static func save(_ accounts: [Account]) throws {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(accounts.prefix(maxAccounts)))
        try data.write(to: accountsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: accountsURL.path)
    }
}
