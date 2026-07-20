import Foundation
import Testing
@testable import UsageCore

@Suite struct PaceDisplayTests {
    @Test func legacyRawValuesStillParse() {
        // Stored preference strings from older builds must keep decoding so
        // migrateLegacy can map them onto PaceSelection.
        for raw in ["all", "hideSlow", "fireOnly", "ringTint", "off"] {
            #expect(PaceDisplay(rawValue: raw) != nil)
        }
        #expect(PaceDisplay(rawValue: "bogus") == nil)
    }

    @Test func symbolNamesPerState() {
        #expect(PaceDisplay.symbolName(for: .fast) == "flame.fill")
        #expect(PaceDisplay.symbolName(for: .steady) == "equal")
        #expect(PaceDisplay.symbolName(for: .slow) == "tortoise.fill")
    }
}

@Suite struct StalenessTests {
    @Test func neverFetchedIsNotStale() {
        #expect(!Staleness.isStale(lastSuccess: nil, refreshInterval: 60, now: Date()))
    }

    @Test func freshDataIsNotStale() {
        let now = Date()
        #expect(!Staleness.isStale(lastSuccess: now.addingTimeInterval(-120), refreshInterval: 60, now: now))
    }

    @Test func floorIsTenMinutesForShortIntervals() {
        let now = Date()
        // 3×60s = 180s would be stale, but the 600s floor keeps it fresh.
        #expect(!Staleness.isStale(lastSuccess: now.addingTimeInterval(-500), refreshInterval: 60, now: now))
        #expect(Staleness.isStale(lastSuccess: now.addingTimeInterval(-601), refreshInterval: 60, now: now))
    }

    @Test func longIntervalsScaleTheThreshold() {
        let now = Date()
        // 3×600s = 1800s threshold beats the 600s floor.
        #expect(!Staleness.isStale(lastSuccess: now.addingTimeInterval(-1700), refreshInterval: 600, now: now))
        #expect(Staleness.isStale(lastSuccess: now.addingTimeInterval(-1801), refreshInterval: 600, now: now))
    }
}
