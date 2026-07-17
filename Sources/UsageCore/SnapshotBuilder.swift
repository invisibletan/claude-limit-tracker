import Foundation

/// Maps the official usage windows onto the two headline meters.
public enum SnapshotBuilder {
    public static func build(from usage: OfficialUsage, now: Date = Date()) -> UsageSnapshot {
        func meter(_ window: OfficialUsage.Window?, _ kind: UsageWindow) -> Meter {
            let percent = window.map { min(100, max(0, $0.utilization)) }
            var pace: Pace?
            if let window, let resetsAt = window.resetsAt {
                pace = Pace.compute(percent: window.utilization, resetsAt: resetsAt, window: kind, now: now)
            }
            return Meter(percent: percent, resetText: Format.reset(window?.resetsAt, now: now), pace: pace)
        }
        let fiveHour = usage.fiveHour
        return UsageSnapshot(
            fiveHour: meter(fiveHour, .fiveHour),
            weekly: meter(usage.sevenDay, .weekly),
            // Mascot spin tracks how full the 5-hour window is.
            activityLevel: min(1, max(0, (fiveHour?.utilization ?? 0) / 100)),
            updatedAt: now
        )
    }
}
