import Foundation

/// A Fast-pace boundary crossing worth notifying about, for one usage window.
public enum PaceAlert: Sendable, Equatable {
    /// The window just started burning Fast (from a slower or unknown pace).
    case crossedToFast
    /// The window eased back off Fast to a known slower pace (steady/slow).
    case droppedBelowFast
}

/// One of the three usage windows, for routing a pace alert to a label + percent.
public enum PaceWindow: Sendable, Equatable {
    case session, weekly, fable
}

/// A snapshot of every window's pace state at one refresh — the unit the alert
/// engine remembers between refreshes.
public struct WindowPaceStates: Sendable, Equatable {
    public var session: Pace.State?
    public var weekly: Pace.State?
    public var fable: Pace.State?

    public init(session: Pace.State?, weekly: Pace.State?, fable: Pace.State?) {
        self.session = session
        self.weekly = weekly
        self.fable = fable
    }
}

/// A single window's Fast-boundary crossing.
public struct PaceCrossing: Sendable, Equatable {
    public var window: PaceWindow
    public var alert: PaceAlert
    public init(window: PaceWindow, alert: PaceAlert) {
        self.window = window
        self.alert = alert
    }
}

/// Pure transition logic for Fast-pace notifications — no side effects, so the
/// crossing rules are unit-tested independently of the notification framework.
public enum PaceAlerts {
    /// Every Fast-boundary crossing between two refreshes, across all windows.
    ///
    /// `old == nil` means this account has no prior observation yet: the result
    /// is empty (seed silently), so a window that is already Fast at launch does
    /// not fire. Once a baseline exists, each window is compared independently.
    public static func crossings(from old: WindowPaceStates?, to new: WindowPaceStates) -> [PaceCrossing] {
        guard let old else { return [] }
        var out: [PaceCrossing] = []
        if let a = alert(from: old.session, to: new.session) { out.append(.init(window: .session, alert: a)) }
        if let a = alert(from: old.weekly, to: new.weekly) { out.append(.init(window: .weekly, alert: a)) }
        if let a = alert(from: old.fable, to: new.fable) { out.append(.init(window: .fable, alert: a)) }
        return out
    }

    /// The alert (if any) for a window whose pace moved from `old` to `new`.
    ///
    /// - Crossing INTO fast fires whenever the new pace is Fast and the old one
    ///   wasn't — including from an unknown prior pace, since the caller only
    ///   consults this once it has a prior observation (unknown = "was fresh").
    /// - Dropping BACK BELOW fast fires only on a genuine slow-down to a *known*
    ///   pace. A window reset (fast → unknown) is deliberately silent: the limit
    ///   pressure ended by the clock, not by easing off, so it isn't a recovery.
    public static func alert(from old: Pace.State?, to new: Pace.State?) -> PaceAlert? {
        if new == .fast, old != .fast { return .crossedToFast }
        if old == .fast, let new, new != .fast { return .droppedBelowFast }
        return nil
    }
}
