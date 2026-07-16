import Foundation

/// The exact 5-hour and weekly usage windows shown at claude.ai Settings → Usage.
public struct OfficialUsage: Sendable {
    public struct Window: Sendable {
        public var key: String
        public var label: String
        /// 0–100.
        public var utilization: Double
        public var resetsAt: Date?

        public init(key: String, label: String, utilization: Double, resetsAt: Date?) {
            self.key = key
            self.label = label
            self.utilization = utilization
            self.resetsAt = resetsAt
        }
    }

    public var windows: [Window]

    public init(windows: [Window]) {
        self.windows = windows
    }

    public var fiveHour: Window? { windows.first { $0.key == "five_hour" } }
    public var sevenDay: Window? { windows.first { $0.key == "seven_day" } }

    /// Utilization arrives 0–1 in some payloads and 0–100 in others; normalize to 0–100.
    public static func normalizedPercent(_ raw: Double) -> Double {
        raw <= 1.0 ? raw * 100 : raw
    }
}

/// Reads the exact 5-hour and weekly usage from the `anthropic-ratelimit-unified-*`
/// response headers that come back on any `/v1/messages` call — the same numbers
/// as claude.ai Settings → Usage. A normal inference call only needs the
/// `user:inference` scope that `claude setup-token` grants: no Keychain, no
/// `user:profile`, no OAuth consent page.
public enum RateLimitUsage {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Builds `OfficialUsage` from response headers. Reset values are unix epoch seconds.
    public static func parseHeaders(_ headers: [String: String], now: Date = Date()) throws -> OfficialUsage {
        // Header names are case-insensitive per HTTP; normalize to lowercase.
        var lower: [String: String] = [:]
        for (key, value) in headers { lower[key.lowercased()] = value }

        func window(prefix: String, key: String, label: String) -> OfficialUsage.Window? {
            guard let raw = lower["anthropic-ratelimit-unified-\(prefix)-utilization"],
                  let value = Double(raw) else { return nil }
            var resetsAt: Date?
            if let resetRaw = lower["anthropic-ratelimit-unified-\(prefix)-reset"],
               let epoch = Double(resetRaw) {
                resetsAt = Date(timeIntervalSince1970: epoch)
            }
            return OfficialUsage.Window(
                key: key,
                label: label,
                utilization: OfficialUsage.normalizedPercent(value),
                resetsAt: resetsAt
            )
        }

        let windows = [
            window(prefix: "5h", key: "five_hour", label: "5-hour limit"),
            window(prefix: "7d", key: "seven_day", label: "Weekly limit"),
        ].compactMap { $0 }

        guard !windows.isEmpty else { throw RateLimitError.noHeaders }
        return OfficialUsage(windows: windows)
    }

    public static func request(token: String) -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        // Smallest possible call — one Haiku token — just to read the headers.
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    public static func fetchUsage(token: String, session: URLSession = .shared) async throws -> OfficialUsage {
        let (_, response) = try await session.data(for: request(token: token))
        guard let http = response as? HTTPURLResponse else { throw RateLimitError.noHeaders }
        if http.statusCode != 200 { throw RateLimitError.httpStatus(http.statusCode) }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String { headers[k] = v }
        }
        return try parseHeaders(headers)
    }
}

public enum RateLimitError: Error, LocalizedError {
    case httpStatus(Int)
    case noHeaders

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            if code == 401 { return "Token rejected (401) — regenerate it with `claude setup-token`." }
            if code == 429 { return "Rate limited (429) — try again in a moment." }
            return "Usage check returned HTTP \(code)."
        case .noHeaders:
            return "No rate-limit headers in the response."
        }
    }
}
