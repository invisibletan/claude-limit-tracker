import Foundation

/// Maps the official usage windows onto the two headline meters.
public enum SnapshotBuilder {
    public static func build(from usage: OfficialUsage, now: Date = Date()) -> UsageSnapshot {
        func meter(_ window: OfficialUsage.Window?) -> Meter {
            Meter(
                percent: window.map { min(100, max(0, $0.utilization)) },
                resetText: Format.reset(window?.resetsAt, now: now)
            )
        }
        let fiveHour = usage.fiveHour
        return UsageSnapshot(
            fiveHour: meter(fiveHour),
            weekly: meter(usage.sevenDay),
            // Mascot spin tracks how full the 5-hour window is.
            activityLevel: min(1, max(0, (fiveHour?.utilization ?? 0) / 100)),
            updatedAt: now
        )
    }
}
