import Foundation
import Testing
@testable import UsageCore

@Suite struct MenuBarEntryTests {
    private func snapshot(session: Double?, sessionState: Pace.State?, weekly: Double?, weeklyState: Pace.State?) -> UsageSnapshot {
        func pace(_ state: Pace.State?) -> Pace? {
            guard let state else { return nil }
            return Pace(ratio: 1, state: state, projectedPercent: 50, timeToLimit: nil)
        }
        return UsageSnapshot(
            fiveHour: Meter(percent: session, resetText: "", pace: pace(sessionState)),
            weekly: Meter(percent: weekly, resetText: "", pace: pace(weeklyState)),
            updatedAt: Date()
        )
    }

    @Test func mapsSnapshotFields() {
        let entry = MenuBarEntry(name: "work", snapshot: snapshot(session: 42, sessionState: .fast, weekly: 12, weeklyState: .slow))
        #expect(entry.name == "work")
        #expect(entry.sessionPercent == 42)
        #expect(entry.sessionPace == .fast)
        #expect(entry.weeklyPercent == 12)
        #expect(entry.weeklyPace == .slow)
    }

    @Test func missingSnapshotYieldsEmptyEntry() {
        let entry = MenuBarEntry(name: nil, snapshot: nil)
        #expect(entry.name == nil)
        #expect(entry.sessionPercent == nil)
        #expect(entry.sessionPace == nil)
        #expect(entry.weeklyPercent == nil)
        #expect(entry.weeklyPace == nil)
    }

    @Test func nilPaceStaysNil() {
        let entry = MenuBarEntry(name: "a", snapshot: snapshot(session: 1, sessionState: nil, weekly: 2, weeklyState: nil))
        #expect(entry.sessionPace == nil)
        #expect(entry.weeklyPace == nil)
    }

    @Test func stalenessDefaultsFalseAndIsCarried() {
        let snap = snapshot(session: 1, sessionState: nil, weekly: 2, weeklyState: nil)
        #expect(!MenuBarEntry(name: nil, snapshot: snap).isStale)
        #expect(MenuBarEntry(name: nil, snapshot: snap, isStale: true).isStale)
    }
}

@Suite struct PaceStateEmojiTests {
    @Test func emojiPerState() {
        #expect(Format.paceEmoji(Pace.State.fast) == "🔥")
        #expect(Format.paceEmoji(Pace.State.steady) == "😎")
        #expect(Format.paceEmoji(Pace.State.slow) == "🐢")
    }
}
