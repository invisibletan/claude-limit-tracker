import Foundation

/// The exact usage windows shown at claude.ai Settings → Usage. The app reads
/// these from `/v1/messages` rate-limit headers (`RateLimitUsage`); `OfficialAPI`
/// parses the same shape from a JSON payload.
public struct OfficialUsage: Sendable {
    /// Utilization arrives on a 0–1 scale in some payloads and 0–100 in others;
    /// normalize to 0–100.
    public static func normalizedPercent(_ raw: Double) -> Double {
        raw <= 1.0 ? raw * 100 : raw
    }

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
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return "Usage endpoint returned an unexpected payload."
        }
    }
}

/// Tolerant parser for a JSON usage payload of `{ window_key: { utilization, resets_at } }`.
/// Kept as a general parser for any future JSON usage source; the app currently
/// reads the same `OfficialUsage` windows from rate-limit headers (`RateLimitUsage`).
public enum OfficialAPI {
    /// Preferred display order for known window keys; unknown keys follow after.
    private static let knownOrder = ["five_hour", "seven_day"]

    /// Treats every top-level object carrying a numeric `utilization` as a
    /// window — keeps `five_hour`/`seven_day` working and picks up model-specific
    /// windows (e.g. `seven_day_opus`) without knowing their names in advance.
    public static func parse(_ data: Data) throws -> OfficialUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OfficialAPIError.malformedResponse
        }
        var windows: [OfficialUsage.Window] = []
        for (key, value) in root {
            guard let dict = value as? [String: Any],
                  let number = dict["utilization"] as? NSNumber else { continue }
            var resetsAt: Date?
            if let stamp = dict["resets_at"] as? String {
                resetsAt = Format.parseISO8601(stamp)
            }
            windows.append(OfficialUsage.Window(
                key: key,
                label: label(forKey: key),
                utilization: OfficialUsage.normalizedPercent(number.doubleValue),
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
}
