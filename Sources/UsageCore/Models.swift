import Foundation

/// One limit meter (5-hour or weekly).
public struct Meter: Sendable {
    /// 0–100, nil when unknown.
    public var percent: Double?
    /// e.g. "resets in 49 min" / "resets Sat 20:00"
    public var resetText: String
    /// How fast this window is being consumed; nil when unknown/too early.
    public var pace: Pace?

    public init(percent: Double?, resetText: String, pace: Pace? = nil) {
        self.percent = percent
        self.resetText = resetText
        self.pace = pace
    }
}

/// The full state rendered by the menu bar UI.
public struct UsageSnapshot: Sendable {
    public var fiveHour: Meter
    public var weekly: Meter
    /// 0–1 signal driving the menu bar mascot's spin speed (higher = busier).
    public var activityLevel: Double
    public var updatedAt: Date

    public init(fiveHour: Meter, weekly: Meter, activityLevel: Double = 0, updatedAt: Date) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.activityLevel = activityLevel
        self.updatedAt = updatedAt
    }
}
