import Foundation
import Testing
@testable import UsageCore

@Suite struct PaceTests {
    // Window resets 4h from now → started 1h ago (5h window) → 20% elapsed.
    private func resetIn(_ hours: Double, from now: Date) -> Date {
        now.addingTimeInterval(hours * 3600)
    }

    @Test func fastWhenAheadOfEvenPace() throws {
        let now = Date()
        // 40% used but only 20% of the window elapsed → 2× pace.
        let pace = try #require(Pace.compute(percent: 40, resetsAt: resetIn(4, from: now), window: .fiveHour, now: now))
        #expect(pace.state == .fast)
        #expect(abs(pace.ratio - 2) < 0.01)
        #expect(abs(pace.projectedPercent - 200) < 1)
        let ttl = try #require(pace.timeToLimit)
        #expect(abs(ttl - 5400) < 60)   // ~1h30m to reach 100% at this rate
    }

    @Test func steadyWhenOnEvenPace() throws {
        let now = Date()
        let pace = try #require(Pace.compute(percent: 20, resetsAt: resetIn(4, from: now), window: .fiveHour, now: now))
        #expect(pace.state == .steady)
        #expect(abs(pace.ratio - 1) < 0.01)
    }

    @Test func slowWhenBehindEvenPace() throws {
        let now = Date()
        let pace = try #require(Pace.compute(percent: 5, resetsAt: resetIn(4, from: now), window: .fiveHour, now: now))
        #expect(pace.state == .slow)
    }

    @Test func nilTooEarlyInWindow() {
        let now = Date()
        // reset 5h out minus 30s → only 30s elapsed.
        let reset = now.addingTimeInterval(5 * 3600 - 30)
        #expect(Pace.compute(percent: 1, resetsAt: reset, window: .fiveHour, now: now) == nil)
    }

    @Test func noTimeToLimitWhenAtCap() throws {
        let now = Date()
        let pace = try #require(Pace.compute(percent: 100, resetsAt: resetIn(4, from: now), window: .fiveHour, now: now))
        #expect(pace.timeToLimit == nil)
    }

    @Test func weeklyWindowUsesSevenDays() throws {
        let now = Date()
        // Weekly resets in 6 days → 1 day elapsed of 7 (14.3%). 30% used → fast.
        let pace = try #require(Pace.compute(percent: 30, resetsAt: now.addingTimeInterval(6 * 86400), window: .weekly, now: now))
        #expect(pace.state == .fast)
    }
}

@Suite struct PaceFormattingTests {
    @Test func paceStrings() {
        #expect(Format.pace(nil) == "")
        #expect(Format.pace(Pace(ratio: 1, state: .steady, projectedPercent: 40, timeToLimit: nil)) == "steady")
        #expect(Format.pace(Pace(ratio: 0.5, state: .slow, projectedPercent: 20, timeToLimit: nil)) == "slow")
        #expect(Format.pace(Pace(ratio: 2, state: .fast, projectedPercent: 200, timeToLimit: 5400)) == "🔥 fast · ~1h 30m left")
    }

    @Test func shortDuration() {
        #expect(Format.shortDuration(90) == "2m")
        #expect(Format.shortDuration(45 * 60) == "45m")
        #expect(Format.shortDuration(3600) == "1h")
        #expect(Format.shortDuration(3600 + 10 * 60) == "1h 10m")
    }
}
