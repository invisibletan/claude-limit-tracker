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
    /// The Fable-tier weekly window (wire prefix `7d_oi`, representative claim
    /// `seven_day_overage_included`). Only present when the probe hit the Fable
    /// model — claude.ai renders it as "Current week (Fable)".
    public var fableWeekly: Window? { windows.first { $0.key == "seven_day_oi" } }

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
            window(prefix: "7d_oi", key: "seven_day_oi", label: "Weekly limit (Fable)"),
        ].compactMap { $0 }

        guard !windows.isEmpty else { throw RateLimitError.noHeaders }
        return OfficialUsage(windows: windows)
    }

    /// Which model the 1-token probe calls. The Fable probe is primary — it is
    /// the only call that returns the Fable weekly (`7d_oi`) window. Haiku is
    /// the fallback that keeps the two headline meters alive when Fable is
    /// unavailable (plan without Fable, model retired, capacity 429).
    public enum Probe: Sendable {
        case fable
        case haiku
    }

    public static func request(token: String, probe: Probe = .haiku) -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        // Smallest possible call — one token — just to read the headers.
        var body: [String: Any] = [
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
        ]
        switch probe {
        case .fable:
            body["model"] = "claude-fable-5"
            // OAuth inference tokens are gated to Claude-Code-shaped requests on
            // premium models; without this system prompt the API answers with a
            // headerless 429 instead of usage headers.
            body["system"] = "You are Claude Code, Anthropic's official CLI for Claude."
        case .haiku:
            body["model"] = "claude-haiku-4-5-20251001"
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    public static func fetchUsage(token: String, session: URLSession = .shared) async throws -> OfficialUsage {
        do {
            return try await fetchUsage(token: token, probe: .fable, session: session)
        } catch let error where shouldFallBackToHaiku(error) {
            // The Fable window is unavailable (plan without Fable, capacity, or a
            // missing/renamed model) — fall back so the 5-hour + weekly meters
            // stay live. The Fable meter simply reads unknown.
            return try await fetchUsage(token: token, probe: .haiku, session: session)
        }
    }

    /// Whether a failed Fable probe is worth retrying on Haiku. Only signals that
    /// mean "Fable *specifically* is unavailable" fall back: 403 (plan without
    /// Fable), 404 (model retired/renamed), 429 (Fable-overage rejected), or no
    /// usage headers. A bad token (401), a network failure, or a 5xx would fail
    /// identically on Haiku, so those propagate immediately instead of doubling
    /// the latency and burning a second doomed request.
    static func shouldFallBackToHaiku(_ error: Error) -> Bool {
        switch error {
        case RateLimitError.httpStatus(let code): return code == 403 || code == 404 || code == 429
        case RateLimitError.noHeaders: return true
        default: return false
        }
    }

    static func fetchUsage(token: String, probe: Probe, session: URLSession) async throws -> OfficialUsage {
        let (_, response) = try await session.data(for: request(token: token, probe: probe))
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
