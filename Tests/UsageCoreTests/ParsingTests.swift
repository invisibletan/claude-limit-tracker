import Foundation
import Testing
@testable import UsageCore

private func nearlyEqual(_ a: Double, _ b: Double, accuracy: Double = 0.01) -> Bool {
    abs(a - b) <= accuracy
}

@Suite struct SnapshotTests {
    private func usage(five: Double?, week: Double?, now: Date) -> OfficialUsage {
        var windows: [OfficialUsage.Window] = []
        if let five {
            windows.append(.init(key: "five_hour", label: "5-hour limit", utilization: five,
                                 resetsAt: now.addingTimeInterval(49 * 60)))
        }
        if let week {
            windows.append(.init(key: "seven_day", label: "Weekly limit", utilization: week, resetsAt: nil))
        }
        return OfficialUsage(windows: windows)
    }

    @Test func buildMapsWindowsToMeters() {
        let now = Date()
        let snapshot = SnapshotBuilder.build(from: usage(five: 32, week: 8, now: now), now: now)
        #expect(snapshot.fiveHour.percent == 32)
        #expect(snapshot.weekly.percent == 8)
        #expect(snapshot.fiveHour.resetText == "resets in 49 min")
        #expect(nearlyEqual(snapshot.activityLevel, 0.32))
    }

    @Test func buildClampsAndHandlesMissing() {
        let now = Date()
        let snapshot = SnapshotBuilder.build(from: usage(five: 140, week: nil, now: now), now: now)
        #expect(snapshot.fiveHour.percent == 100)   // clamped
        #expect(snapshot.weekly.percent == nil)     // no weekly window
        #expect(snapshot.activityLevel == 1)
    }

    @Test func buildMapsFableWeeklyWhenPresent() {
        let now = Date()
        var official = usage(five: 32, week: 8, now: now)
        official.windows.append(.init(key: "seven_day_oi", label: "Weekly limit (Fable)",
                                      utilization: 78, resetsAt: now.addingTimeInterval(40 * 3600)))
        let snapshot = SnapshotBuilder.build(from: official, now: now)
        #expect(snapshot.fableWeekly?.percent == 78)
        #expect(snapshot.fableWeekly?.resetText == "resets in 40h")
    }

    @Test func buildLeavesFableWeeklyNilWhenAbsent() {
        // Fallback (Haiku) probes carry no 7d_oi window — the meter must stay
        // nil (unknown), not render as 0%.
        let now = Date()
        let snapshot = SnapshotBuilder.build(from: usage(five: 32, week: 8, now: now), now: now)
        #expect(snapshot.fableWeekly == nil)
    }
}

@Suite struct FormattingTests {
    @Test func percent() {
        #expect(Format.percent(68.4) == "68%")
        #expect(Format.percent(nil) == "–%")
    }

    @Test func resetAndUpdated() {
        let now = Date()
        #expect(Format.reset(now.addingTimeInterval(49 * 60 - 1), now: now) == "resets in 49 min")
        #expect(Format.reset(now.addingTimeInterval(3 * 3600 + 20 * 60), now: now) == "resets in 3h 20m")
        #expect(Format.reset(now.addingTimeInterval(3 * 86400), now: now).hasPrefix("resets "))
        #expect(Format.reset(nil, now: now) == "")
        #expect(Format.updatedAgo(now.addingTimeInterval(-12), now: now) == "updated 12s ago")
        #expect(Format.updatedAgo(now.addingTimeInterval(-180), now: now) == "updated 3m ago")
    }
}
