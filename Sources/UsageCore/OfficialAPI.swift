import Foundation

/// Exact usage percentages from Anthropic's OAuth usage endpoint — the same
/// numbers claude.ai shows in Settings → Usage and Claude Code shows in /usage.
///
/// Requires an OAuth access token supplied by the user (e.g. from `claude setup-token`).
/// This module never reads the macOS Keychain or any credential store.
public struct OfficialUsage: Sendable {
    public var fiveHourUtilization: Double?
    public var fiveHourResetsAt: Date?
    public var sevenDayUtilization: Double?
    public var sevenDayResetsAt: Date?

    public init(
        fiveHourUtilization: Double? = nil,
        fiveHourResetsAt: Date? = nil,
        sevenDayUtilization: Double? = nil,
        sevenDayResetsAt: Date? = nil
    ) {
        self.fiveHourUtilization = fiveHourUtilization
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayUtilization = sevenDayUtilization
        self.sevenDayResetsAt = sevenDayResetsAt
    }
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

    /// Tolerant parser: the payload is undocumented, so accept either
    /// `{"five_hour": {"utilization": 68, "resets_at": "..."}}`-style windows
    /// or a flat variant, and ignore anything unrecognized.
    public static func parse(_ data: Data) throws -> OfficialUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OfficialAPIError.malformedResponse
        }
        var usage = OfficialUsage()
        if let window = windowValues(root["five_hour"]) {
            usage.fiveHourUtilization = window.utilization
            usage.fiveHourResetsAt = window.resetsAt
        }
        if let window = windowValues(root["seven_day"]) {
            usage.sevenDayUtilization = window.utilization
            usage.sevenDayResetsAt = window.resetsAt
        }
        guard usage.fiveHourUtilization != nil || usage.sevenDayUtilization != nil else {
            throw OfficialAPIError.malformedResponse
        }
        return usage
    }

    private static func windowValues(_ value: Any?) -> (utilization: Double?, resetsAt: Date?)? {
        guard let dict = value as? [String: Any] else { return nil }
        var utilization: Double?
        if let number = dict["utilization"] as? NSNumber {
            // Some payload generations report 0–1, others 0–100. Normalize to 0–100.
            let raw = number.doubleValue
            utilization = raw <= 1.0 ? raw * 100 : raw
        }
        var resetsAt: Date?
        if let stamp = dict["resets_at"] as? String {
            resetsAt = parseISO8601(stamp)
        }
        return (utilization, resetsAt)
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
