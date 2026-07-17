import Foundation

/// Small formatting helpers shared by the panel and tests.
public enum Format {
    public static func percent(_ value: Double?) -> String {
        guard let value else { return "–%" }
        return "\(Int(value.rounded()))%"
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

    /// "1h 10m", "45m", "2m" — a compact duration for the pace line.
    public static func shortDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "🔥 fast · ~1h 10m left" / "steady" / "slow".
    public static func pace(_ pace: Pace?) -> String {
        guard let pace else { return "" }
        var text: String
        switch pace.state {
        case .fast: text = "🔥 fast"
        case .steady: text = "steady"
        case .slow: text = "slow"
        }
        if let ttl = pace.timeToLimit {
            text += " · ~\(shortDuration(ttl)) left"
        }
        return text
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
