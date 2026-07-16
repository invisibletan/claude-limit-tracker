import Foundation

/// Small formatting helpers shared by the panel and tests.
public enum Format {
    public static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    public static func percent(_ value: Double?) -> String {
        guard let value else { return "–%" }
        return "\(Int(value.rounded()))%"
    }

    /// "76.9k tok/min" style burn rate.
    public static func tokensPerMinute(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM tok/min", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk tok/min", value / 1_000)
        }
        return String(format: "%.0f tok/min", value)
    }

    /// "resets in 49 min", "resets in 3h 20m", or "resets Mon 00:00" for far-out dates.
    public static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "resetting…" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "resets in \(minutes) min" }
        if minutes < 48 * 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "resets in \(hours)h" : "resets in \(hours)h \(rest)m"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return "resets \(formatter.string(from: date))"
    }

    /// "updated 12s ago" / "updated 3m ago".
    public static func updatedAgo(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "updated \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "updated \(minutes)m ago" }
        return "updated \(minutes / 60)h ago"
    }
}
