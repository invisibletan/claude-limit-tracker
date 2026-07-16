import Foundation

/// Exact usage percentages from Anthropic's OAuth usage endpoint — the same
/// numbers claude.ai shows in Settings → Usage and Claude Code shows in /usage.
///
/// Requires an OAuth access token supplied by the user (e.g. from `claude setup-token`).
/// This module never reads the macOS Keychain or any credential store.
public struct OfficialUsage: Sendable {
    /// One rate-limit window (5-hour, weekly, model-specific weekly, …).
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

    /// All windows the endpoint reported, in display order.
    public var windows: [Window]

    public init(windows: [Window]) {
        self.windows = windows
    }

    public var fiveHour: Window? { windows.first { $0.key == "five_hour" } }
    public var sevenDay: Window? { windows.first { $0.key == "seven_day" } }
    /// Windows beyond the two headline meters (e.g. per-model weekly limits).
    public var extraWindows: [Window] {
        windows.filter { $0.key != "five_hour" && $0.key != "seven_day" }
    }

    public var fiveHourUtilization: Double? { fiveHour?.utilization }
    public var fiveHourResetsAt: Date? { fiveHour?.resetsAt }
    public var sevenDayUtilization: Double? { sevenDay?.utilization }
    public var sevenDayResetsAt: Date? { sevenDay?.resetsAt }
}

public enum OfficialAPIError: Error, LocalizedError {
    case httpStatus(Int)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return code == 401
                ? "Token rejected (401) — refresh it with `claude setup-token`."
                : "Usage endpoint returned HTTP \(code)."
        case .malformedResponse:
            return "Usage endpoint returned an unexpected payload."
        }
    }
}

public enum OfficialAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Preferred display order for known window keys; unknown keys follow after.
    private static let knownOrder = ["five_hour", "seven_day"]

    public static func request(token: String) -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        return req
    }

    public static func fetch(token: String, session: URLSession = .shared) async throws -> OfficialUsage {
        let (data, response) = try await session.data(for: request(token: token))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw OfficialAPIError.httpStatus(http.statusCode)
        }
        return try parse(data)
    }

    /// Tolerant parser: the payload is undocumented, so treat every top-level
    /// object carrying a numeric `utilization` as a rate-limit window. That
    /// keeps `five_hour`/`seven_day` working and picks up model-specific
    /// windows (e.g. `seven_day_opus`) without knowing their names in advance.
    public static func parse(_ data: Data) throws -> OfficialUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OfficialAPIError.malformedResponse
        }
        var windows: [OfficialUsage.Window] = []
        for (key, value) in root {
            guard let dict = value as? [String: Any],
                  let number = dict["utilization"] as? NSNumber else { continue }
            // Some payload generations report 0–1, others 0–100. Normalize to 0–100.
            let raw = number.doubleValue
            let utilization = raw <= 1.0 ? raw * 100 : raw
            var resetsAt: Date?
            if let stamp = dict["resets_at"] as? String {
                resetsAt = parseISO8601(stamp)
            }
            windows.append(OfficialUsage.Window(
                key: key,
                label: label(forKey: key),
                utilization: utilization,
                resetsAt: resetsAt
            ))
        }
        guard !windows.isEmpty else {
            throw OfficialAPIError.malformedResponse
        }
        windows.sort { sortRank($0.key) < sortRank($1.key) }
        return OfficialUsage(windows: windows)
    }

    private static func sortRank(_ key: String) -> (Int, String) {
        ((knownOrder.firstIndex(of: key) ?? knownOrder.count), key)
    }

    /// "five_hour" → "5-hour limit", "seven_day_opus" → "Weekly · Opus",
    /// anything else → prettified snake_case.
    public static func label(forKey key: String) -> String {
        switch key {
        case "five_hour": return "5-hour limit"
        case "seven_day": return "Weekly limit"
        default:
            if key.hasPrefix("seven_day_") {
                let model = key.dropFirst("seven_day_".count)
                    .split(separator: "_").map { $0.capitalized }.joined(separator: " ")
                return "Weekly · \(model)"
            }
            return key.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }

    public static func parseISO8601(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
