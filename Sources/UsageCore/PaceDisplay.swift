import Foundation

/// Legacy menu bar pace modes from the picker-based UI. Retained only so
/// stored preference strings keep decoding — the live model is per-state
/// checkboxes (`PaceSelection`) since the symmetric-groups layout.
public enum PaceDisplay: String, CaseIterable, Sendable {
    case all
    case hideSlow
    case fireOnly
    case ringTint
    case off

    /// Monochrome SF Symbol per pace state (template — tinted by the drawing code).
    public static func symbolName(for state: Pace.State) -> String {
        switch state {
        case .fast: return "flame.fill"
        case .steady: return "equal"
        case .slow: return "tortoise.fill"
        }
    }

    /// Maps a stored (possibly legacy) picker value onto the two-set checkbox
    /// model: all → every state · hideSlow → steady+fast · fireOnly → fast ·
    /// ringTint (removed mode) → the default look · off → glyph ELEMENT off
    /// with no group filtering · unknown/missing → the shipped defaults.
    public static func migrateLegacy(rawValue: String?) -> (selection: PaceSelection, glyphs: Bool) {
        switch rawValue.flatMap(PaceDisplay.init(rawValue:)) {
        case .all, .ringTint, nil: return (.all, true)
        case .hideSlow: return (PaceSelection(slow: false, steady: true, fast: true), true)
        case .fireOnly: return (PaceSelection(slow: false, steady: false, fast: true), true)
        case .off: return (.all, false)
        }
    }
}

/// The user's slow/steady/fast checkboxes for one window. These filter the
/// WHOLE window group: while the window's current pace is an unchecked state,
/// that account's ring + percent + glyph for the window are hidden entirely.
public struct PaceSelection: Sendable, Equatable {
    public var slow: Bool
    public var steady: Bool
    public var fast: Bool

    public init(slow: Bool, steady: Bool, fast: Bool) {
        self.slow = slow
        self.steady = steady
        self.fast = fast
    }

    public static let all = PaceSelection(slow: true, steady: true, fast: true)
    public static let none = PaceSelection(slow: false, steady: false, fast: false)

    public func shows(_ state: Pace.State) -> Bool {
        switch state {
        case .slow: return slow
        case .steady: return steady
        case .fast: return fast
        }
    }

    /// Whether the window group renders at all for the given current pace.
    /// Unknown pace (too early in the window to judge) never hides data.
    public func showsGroup(for state: Pace.State?) -> Bool {
        state.map(shows) ?? true
    }
}

/// The user's menu bar composition: which elements render, per window.
public struct MenuBarConfig: Sendable, Equatable {
    public var showMascot = true
    public var sessionRing = true
    public var sessionPercent = true
    /// Element toggle for the session pace glyph (set 1: Ring/Percent/Glyph).
    public var sessionGlyph = true
    /// Group-visibility filter by current pace (set 2: Slow/Steady/Fast).
    public var sessionPace = PaceSelection.all
    /// New in the symmetric-groups layout; ships off to preserve the prior look.
    public var weeklyRing = false
    public var weeklyPercent = true
    public var weeklyGlyph = true
    public var weeklyPace = PaceSelection.all

    public init() {}
}

/// Which composable elements of a menu bar segment actually render, given the
/// user's toggles. Pure guard logic so no combination produces an empty item.
public enum MenuBarLayout {
    /// A visible mascot — or any structural element (a ring or a percent, in
    /// either window) — is a sufficient clickable anchor. Only when the mascot
    /// is hidden AND every structural element is off does the session ring get
    /// forced back: the item must never render empty. Pace glyphs don't count
    /// as anchors because they're data-dependent (absent early in a window).
    public static func effective(_ config: MenuBarConfig, mascotVisible: Bool) -> MenuBarConfig {
        var out = config
        let anyStructural = config.sessionRing || config.sessionPercent || config.weeklyRing || config.weeklyPercent
        if !mascotVisible && !anyStructural { out.sessionRing = true }
        return out
    }

    /// With no account segments the mascot is the only clickable target, so the
    /// hide-mascot preference only applies while at least one segment renders.
    public static func showsMascot(preference: Bool, hasEntries: Bool) -> Bool {
        preference || !hasEntries
    }
}

/// When menu bar data should be shown dimmed as untrusted (the last successful
/// fetch is too old — the visible numbers may no longer reflect reality).
public enum Staleness {
    /// Stale once age exceeds 3 missed refresh cycles, with a 10-minute floor so
    /// fast refresh intervals don't flap the dim state on a single blip.
    public static func isStale(lastSuccess: Date?, refreshInterval: TimeInterval, now: Date = Date()) -> Bool {
        guard let lastSuccess else { return false }
        let threshold = max(3 * refreshInterval, 600)
        return now.timeIntervalSince(lastSuccess) > threshold
    }
}
