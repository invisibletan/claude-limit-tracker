import Foundation
import Testing
@testable import UsageCore

@Suite struct UsageTierTests {
    // MARK: pace drives the tier

    @Test func slowPaceIsSafe() {
        #expect(UsageTier.resolve(pace: .slow, percent: 10) == .safe)
    }

    @Test func steadyPaceIsOnTrack() {
        #expect(UsageTier.resolve(pace: .steady, percent: 40) == .onTrack)
    }

    @Test func fastPaceIsDanger() {
        // Fast burn is a danger even at a low absolute level — that's the point:
        // warn on the trajectory so usage can be slowed before the cap.
        #expect(UsageTier.resolve(pace: .fast, percent: 30) == .danger)
    }

    // MARK: near-cap override wins over pace

    @Test func nearCapForcesDangerEvenWhenSlow() {
        // 95% used but pacing slow — still about to hit the wall.
        #expect(UsageTier.resolve(pace: .slow, percent: 95) == .danger)
    }

    @Test func nearCapForcesDangerEvenWhenSteady() {
        #expect(UsageTier.resolve(pace: .steady, percent: 92) == .danger)
    }

    @Test func nearCapForcesDangerWhenPaceUnknown() {
        // No pace reading yet, but already near the cap → danger, not neutral.
        #expect(UsageTier.resolve(pace: nil, percent: 90) == .danger)
    }

    @Test func exactlyAtNearCapThresholdIsDanger() {
        #expect(UsageTier.resolve(pace: .steady, percent: UsageTier.nearCapPercent) == .danger)
    }

    @Test func justBelowNearCapDefersToPace() {
        // 79.9% steady is still just on-track — the override starts at 80.
        #expect(UsageTier.resolve(pace: .steady, percent: 79.9) == .onTrack)
    }

    @Test func nearCapThresholdIsEighty() {
        #expect(UsageTier.nearCapPercent == 80)
    }

    // MARK: unknown pace

    @Test func unknownPaceBelowCapIsUnknown() {
        #expect(UsageTier.resolve(pace: nil, percent: 20) == .unknown)
    }

    @Test func unknownPaceWithNilPercentIsUnknown() {
        #expect(UsageTier.resolve(pace: nil, percent: nil) == .unknown)
    }

    // MARK: alarm flag (drives the red percent readout)

    @Test func onlyDangerIsAlarm() {
        #expect(UsageTier.danger.isAlarm)
        #expect(!UsageTier.safe.isAlarm)
        #expect(!UsageTier.onTrack.isAlarm)
        #expect(!UsageTier.unknown.isAlarm)
    }
}
