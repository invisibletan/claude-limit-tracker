import Foundation
import Testing
@testable import UsageCore

@Suite struct PaceAlertTests {
    // Crossing INTO fast — from any known-or-unknown non-fast prior state.
    @Test func crossesToFastFromBelow() {
        #expect(PaceAlerts.alert(from: .steady, to: .fast) == .crossedToFast)
        #expect(PaceAlerts.alert(from: .slow, to: .fast) == .crossedToFast)
        // Unknown last time (fresh window) then judged fast counts as a crossing —
        // the caller only invokes this once a prior observation exists, so nil here
        // means "observed unknown", not "never seen".
        #expect(PaceAlerts.alert(from: nil, to: .fast) == .crossedToFast)
    }

    // Dropping BACK BELOW fast — only via a genuine slow-down to a known state.
    @Test func dropsBelowFastToKnownState() {
        #expect(PaceAlerts.alert(from: .fast, to: .steady) == .droppedBelowFast)
        #expect(PaceAlerts.alert(from: .fast, to: .slow) == .droppedBelowFast)
    }

    // A window reset (fast → unknown) is NOT a recovery — stay silent.
    @Test func windowResetDoesNotFire() {
        #expect(PaceAlerts.alert(from: .fast, to: nil) == nil)
    }

    // No crossing → nothing.
    @Test func nonCrossingsAreSilent() {
        #expect(PaceAlerts.alert(from: .fast, to: .fast) == nil)
        #expect(PaceAlerts.alert(from: .steady, to: .slow) == nil)
        #expect(PaceAlerts.alert(from: .slow, to: .steady) == nil)
        #expect(PaceAlerts.alert(from: .steady, to: .steady) == nil)
        #expect(PaceAlerts.alert(from: nil, to: .steady) == nil)
        #expect(PaceAlerts.alert(from: nil, to: nil) == nil)
        #expect(PaceAlerts.alert(from: .steady, to: nil) == nil)
    }
}

@Suite struct PaceCrossingsTests {
    private func states(_ s: Pace.State?, _ w: Pace.State?, _ f: Pace.State?) -> WindowPaceStates {
        WindowPaceStates(session: s, weekly: w, fable: f)
    }

    @Test func firstObservationSeedsSilently() {
        // No prior baseline — even an all-Fast snapshot must not fire at launch.
        let now = states(.fast, .fast, .fast)
        #expect(PaceAlerts.crossings(from: nil, to: now).isEmpty)
    }

    @Test func perWindowIndependence() {
        let prev = states(.steady, .fast, nil)
        let next = states(.fast, .steady, .fast)
        let out = PaceAlerts.crossings(from: prev, to: next)
        #expect(out == [
            PaceCrossing(window: .session, alert: .crossedToFast),
            PaceCrossing(window: .weekly, alert: .droppedBelowFast),
            PaceCrossing(window: .fable, alert: .crossedToFast),
        ])
    }

    @Test func steadyStateProducesNoCrossings() {
        let prev = states(.steady, .slow, .fast)
        #expect(PaceAlerts.crossings(from: prev, to: prev).isEmpty)
    }

    @Test func fableResetIsSilentButSessionStillFires() {
        let prev = states(.steady, .steady, .fast)
        let next = states(.fast, .steady, nil)   // fable window reset → unknown
        let out = PaceAlerts.crossings(from: prev, to: next)
        #expect(out == [PaceCrossing(window: .session, alert: .crossedToFast)])
    }
}
