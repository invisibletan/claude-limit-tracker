import Foundation

/// A usage window with a fixed length; used to reason about burn pace.
public enum UsageWindow: Sendable {
    case fiveHour
    case weekly

    public var seconds: Double {
        switch self {
        case .fiveHour: return 5 * 3600
        case .weekly: return 7 * 86400
        }
    }
}

/// How fast the current window is being consumed relative to an even burn.
///
/// Even pace fills the window linearly (a 5-hour window → 20%/hour). If actual
/// utilization is ahead of the elapsed fraction, usage is "fast" and the limit
/// will be hit before the window resets.
public struct Pace: Sendable, Equatable {
    public enum State: Sendable { case fast, steady, slow }

    /// utilization ÷ expected-for-elapsed-time. 1.0 = exactly even.
    public var ratio: Double
    public var state: State
    /// Linear projection of utilization at window reset (may exceed 100).
    public var projectedPercent: Double
    /// Seconds until utilization would reach 100% at the current rate; nil if
    /// already at the cap, not moving, or it wouldn't happen before reset.
    public var timeToLimit: TimeInterval?

    public init(ratio: Double, state: State, projectedPercent: Double, timeToLimit: TimeInterval?) {
        self.ratio = ratio
        self.state = state
        self.projectedPercent = projectedPercent
        self.timeToLimit = timeToLimit
    }

    public static func compute(percent: Double, resetsAt: Date, window: UsageWindow, now: Date = Date()) -> Pace? {
        let windowStart = resetsAt.addingTimeInterval(-window.seconds)
        let elapsed = now.timeIntervalSince(windowStart)
        // Too early in the window (or clock skew) to say anything meaningful.
        guard elapsed > 60 else { return nil }
        let elapsedFrac = min(1, max(0.001, elapsed / window.seconds))
        let expected = elapsedFrac * 100
        let ratio = expected > 0 ? percent / expected : 1
        let state: State = ratio >= 1.15 ? .fast : (ratio <= 0.85 ? .slow : .steady)
        let projected = min(999, percent / elapsedFrac)

        var timeToLimit: TimeInterval?
        if percent < 100, percent > 0 {
            let ratePerSecond = percent / elapsed              // % per second
            let secondsToCap = (100 - percent) / ratePerSecond
            let secondsToReset = resetsAt.timeIntervalSince(now)
            if secondsToCap > 0, secondsToCap < secondsToReset {
                timeToLimit = secondsToCap
            }
        }
        return Pace(ratio: ratio, state: state, projectedPercent: projected, timeToLimit: timeToLimit)
    }
}
