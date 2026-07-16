import Foundation
import Testing
@testable import UsageCore

// Shape captured from a real `ccusage blocks --active --json` run.
private let blocksJSON = """
{
  "blocks": [
    {
      "id": "2026-07-16T00:00:00.000Z",
      "startTime": "2026-07-16T00:00:00.000Z",
      "endTime": "2026-07-16T05:00:00.000Z",
      "isActive": true,
      "isGap": false,
      "entries": 56,
      "totalTokens": 31216062,
      "costUSD": 23.53784825,
      "burnRate": { "tokensPerMinute": 120262.14, "costPerHour": 5.44 },
      "projection": { "totalTokens": 35905917, "totalCost": 27.07, "remainingMinutes": 39 }
    }
  ]
}
""".data(using: .utf8)!

private let dailyJSON = """
{
  "daily": [
    { "date": "2026-07-15", "totalCost": 100.5, "totalTokens": 1 },
    { "date": "2026-07-16", "totalCost": 23.78, "totalTokens": 2 }
  ],
  "totals": {}
}
""".data(using: .utf8)!

private func nearlyEqual(_ a: Double, _ b: Double, accuracy: Double = 0.01) -> Bool {
    abs(a - b) <= accuracy
}

@Suite struct CCUsageParsingTests {
    @Test func parseActiveBlock() throws {
        let block = try #require(try CCUsage.parseActiveBlock(blocksJSON))
        #expect(nearlyEqual(block.costUSD, 23.53784825, accuracy: 0.0001))
        #expect(block.totalTokens == 31_216_062)
        #expect(nearlyEqual(block.tokensPerMinute ?? 0, 120_262.14))
        #expect(nearlyEqual(block.projectedCostUSD ?? 0, 27.07, accuracy: 0.001))
        #expect(block.endTime != nil)
    }

    @Test func parseActiveBlockNoActive() throws {
        let idle = #"{"blocks": [{"isActive": false, "costUSD": 1}]}"#.data(using: .utf8)!
        #expect(try CCUsage.parseActiveBlock(idle) == nil)
    }

    @Test func parseDailyTotalCost() throws {
        let total = try CCUsage.parseDailyTotalCost(dailyJSON)
        #expect(nearlyEqual(total, 124.28, accuracy: 0.001))
    }

    @Test func parseDailyToleratesBareEmptyArray() throws {
        // ccusage emits `[]` (no wrapper object) when the range has no data.
        let total = try CCUsage.parseDailyTotalCost("[]".data(using: .utf8)!)
        #expect(total == 0)
    }

    @Test func sinceStringIsAlwaysGregorian() {
        // Regression: on a Thai Buddhist system calendar (en_TH), Calendar.current
        // formats 2026-07-16 as 25690716, which ccusage reads as far future.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let noon = utc.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))!
        // Compare in the local zone the helper uses, keeping the test host-TZ-proof.
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone.current
        let expected = local.date(byAdding: .day, value: -6, to: noon)!
        let parts = local.dateComponents([.year, .month, .day], from: expected)
        let expectedString = String(format: "%04d%02d%02d", parts.year!, parts.month!, parts.day!)
        #expect(CCUsageRunner.sinceString(daysBack: 7, from: noon) == expectedString)
        #expect(CCUsageRunner.sinceString(daysBack: 7, from: noon).hasPrefix("2026"))
    }
}

@Suite struct OfficialAPIParsingTests {
    @Test func nestedWindows() throws {
        let payload = """
        {
          "five_hour": { "utilization": 68, "resets_at": "2026-07-16T05:00:00Z" },
          "seven_day": { "utilization": 31, "resets_at": "2026-07-20T00:00:00.000Z" }
        }
        """.data(using: .utf8)!
        let usage = try OfficialAPI.parse(payload)
        #expect(usage.fiveHourUtilization == 68)
        #expect(usage.sevenDayUtilization == 31)
        #expect(usage.fiveHourResetsAt != nil)
        #expect(usage.sevenDayResetsAt != nil)
    }

    @Test func modelSpecificAndUnknownWindows() throws {
        let payload = """
        {
          "five_hour": { "utilization": 18 },
          "seven_day": { "utilization": 5 },
          "seven_day_opus": { "utilization": 9, "resets_at": "2026-07-18T13:00:00Z" },
          "some_new_window": { "utilization": 42 },
          "not_a_window": { "foo": 1 },
          "scalar": 7
        }
        """.data(using: .utf8)!
        let usage = try OfficialAPI.parse(payload)
        #expect(usage.windows.count == 4)
        // Known keys first, in order; extras after.
        #expect(usage.windows[0].key == "five_hour")
        #expect(usage.windows[1].key == "seven_day")
        #expect(usage.fiveHour?.utilization == 18)
        #expect(usage.sevenDay?.utilization == 5)

        let extras = usage.extraWindows
        #expect(extras.count == 2)
        let opus = try #require(extras.first { $0.key == "seven_day_opus" })
        #expect(opus.label == "Weekly · Opus")
        #expect(opus.utilization == 9)
        #expect(opus.resetsAt != nil)
        let unknown = try #require(extras.first { $0.key == "some_new_window" })
        #expect(unknown.label == "Some New Window")
    }

    @Test func normalizesFractionalUtilization() throws {
        let payload = #"{"five_hour": {"utilization": 0.68}}"#.data(using: .utf8)!
        let usage = try OfficialAPI.parse(payload)
        #expect(nearlyEqual(usage.fiveHourUtilization ?? 0, 68, accuracy: 0.001))
    }

    @Test func rejectsGarbage() {
        let payload = #"{"unrelated": true}"#.data(using: .utf8)!
        #expect(throws: OfficialAPIError.self) { try OfficialAPI.parse(payload) }
    }
}

@Suite struct SnapshotTests {
    private let caps = EstimateCaps(fiveHourUSD: 35, weeklyUSD: 500)

    @Test func healthStateThresholds() {
        #expect(HealthState.forPercent(0) == .good)
        #expect(HealthState.forPercent(59.9) == .good)
        #expect(HealthState.forPercent(60) == .warn)
        #expect(HealthState.forPercent(84.9) == .warn)
        #expect(HealthState.forPercent(85) == .crit)
        #expect(HealthState.forPercent(nil) == .good)
    }

    @Test func estimateMode() throws {
        let block = try #require(try CCUsage.parseActiveBlock(blocksJSON))
        let snapshot = SnapshotBuilder.build(official: nil, block: block, weeklyCostUSD: 444.55, caps: caps)
        #expect(snapshot.source == .localEstimate)
        #expect(nearlyEqual(snapshot.fiveHour.percent ?? 0, 23.53784825 / 35 * 100))
        #expect(nearlyEqual(snapshot.weekly.percent ?? 0, 444.55 / 500 * 100))
        #expect(snapshot.fiveHour.detail.contains("$23.54 used"))
        #expect(snapshot.fiveHour.detail.contains("projected $27.07"))
        #expect(snapshot.weekly.resetText == "rolling 7 days")
        #expect(snapshot.burnRateText == "120.3k tok/min")
    }

    @Test func officialModeWinsPercentages() throws {
        let block = try #require(try CCUsage.parseActiveBlock(blocksJSON))
        let official = OfficialUsage(windows: [
            .init(key: "five_hour", label: "5-hour limit", utilization: 68,
                  resetsAt: Date(timeIntervalSinceNow: 49 * 60)),
            .init(key: "seven_day", label: "Weekly limit", utilization: 31,
                  resetsAt: Date(timeIntervalSinceNow: 3 * 86400)),
            .init(key: "seven_day_opus", label: "Weekly · Opus", utilization: 9,
                  resetsAt: Date(timeIntervalSinceNow: 2 * 86400)),
        ])
        let snapshot = SnapshotBuilder.build(official: official, block: block, weeklyCostUSD: 444.55, caps: caps)
        #expect(snapshot.source == .officialAPI)
        #expect(snapshot.fiveHour.percent == 68)
        #expect(snapshot.weekly.percent == 31)
        // Cost detail still comes from ccusage.
        #expect(snapshot.fiveHour.detail.contains("$23.54 used"))
        #expect(snapshot.fiveHour.resetText.contains("resets in"))
        // Model-specific window surfaces as an extra meter.
        #expect(snapshot.extraMeters.count == 1)
        #expect(snapshot.extraMeters[0].title == "Weekly · Opus")
        #expect(snapshot.extraMeters[0].meter.percent == 9)
    }

    @Test func idleNoData() {
        let snapshot = SnapshotBuilder.build(official: nil, block: nil, weeklyCostUSD: 10, caps: caps)
        #expect(snapshot.fiveHour.percent == 0)
        #expect(snapshot.fiveHour.detail == "no active session")
        #expect(snapshot.burnRateText == nil)
    }

    @Test func activityLevelFromBurnRate() throws {
        let block = try #require(try CCUsage.parseActiveBlock(blocksJSON))  // ~120k tok/min
        let snapshot = SnapshotBuilder.build(official: nil, block: block, weeklyCostUSD: 100, caps: caps)
        #expect(abs(snapshot.activityLevel - 120_262.14 / 200_000) < 0.001)
    }

    @Test func activityLevelFallsBackToFiveHourPercent() {
        // No block → activity tracks how full the 5-hour window is (40% → 0.40).
        let official = OfficialUsage(windows: [
            .init(key: "five_hour", label: "5-hour limit", utilization: 40, resetsAt: nil),
        ])
        let snapshot = SnapshotBuilder.build(official: official, block: nil, weeklyCostUSD: nil, caps: caps)
        #expect(abs(snapshot.activityLevel - 0.40) < 0.0001)
    }

    @Test func activityLevelClampsToOne() {
        let official = OfficialUsage(windows: [
            .init(key: "five_hour", label: "5-hour limit", utilization: 95, resetsAt: nil),
        ])
        let block = CCUsage.ActiveBlock(costUSD: 1, totalTokens: 1, tokensPerMinute: 900_000)
        let snapshot = SnapshotBuilder.build(official: official, block: block, weeklyCostUSD: nil, caps: caps)
        #expect(snapshot.activityLevel == 1)
    }
}

@Suite struct FormattingTests {
    @Test func numbers() {
        #expect(Format.money(15.6) == "$15.60")
        #expect(Format.percent(68.4) == "68%")
        #expect(Format.percent(nil) == "–%")
        #expect(Format.tokensPerMinute(76_900) == "76.9k tok/min")
        #expect(Format.tokensPerMinute(2_100_000) == "2.1M tok/min")
        #expect(Format.tokensPerMinute(320) == "320 tok/min")
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
