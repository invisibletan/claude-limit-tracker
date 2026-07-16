import Foundation

/// Health thresholds shared by the icon and the panel meters.
public enum HealthState: Sendable {
    case good  // under 60%
    case warn  // 60–85%
    case crit  // over 85%

    public static func forPercent(_ percent: Double?) -> HealthState {
        guard let percent else { return .good }
        if percent >= 85 { return .crit }
        if percent >= 60 { return .warn }
        return .good
    }
}

/// Where the numbers came from.
public enum UsageSource: Sendable {
    /// Anthropic's OAuth usage endpoint — the same data as claude.ai Settings → Usage.
    case officialAPI
    /// Read live off claude.ai Settings → Usage via the app's own web session.
    case webSession
    /// Estimated from local `~/.claude` JSONL logs via ccusage, measured against user-set caps.
    case localEstimate
}

/// One limit meter (5-hour or weekly).
public struct Meter: Sendable {
    /// 0–100, nil when unknown.
    public var percent: Double?
    /// e.g. "$15.60 used · projected $18.63"
    public var detail: String
    /// e.g. "resets in 49 min" / "resets Mon 00:00"
    public var resetText: String

    public var state: HealthState { HealthState.forPercent(percent) }

    public init(percent: Double?, detail: String, resetText: String) {
        self.percent = percent
        self.detail = detail
        self.resetText = resetText
    }
}

/// A titled meter beyond the two headline limits (e.g. a per-model weekly limit).
public struct ExtraMeter: Sendable {
    public var title: String
    public var meter: Meter

    public init(title: String, meter: Meter) {
        self.title = title
        self.meter = meter
    }
}

/// The full state rendered by the menu bar UI.
public struct UsageSnapshot: Sendable {
    public var fiveHour: Meter
    public var weekly: Meter
    /// Additional official windows (per-model weekly limits); empty in estimate mode.
    public var extraMeters: [ExtraMeter]
    public var burnRateText: String?
    public var source: UsageSource
    public var updatedAt: Date

    public init(
        fiveHour: Meter,
        weekly: Meter,
        extraMeters: [ExtraMeter] = [],
        burnRateText: String?,
        source: UsageSource,
        updatedAt: Date
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.extraMeters = extraMeters
        self.burnRateText = burnRateText
        self.source = source
        self.updatedAt = updatedAt
    }
}

/// A usage window read off the claude.ai Settings → Usage page.
public struct WebWindow: Sendable, Codable, Equatable {
    public var label: String
    /// 0–100.
    public var percent: Double
    public var resetText: String

    public init(label: String, percent: Double, resetText: String) {
        self.label = label
        self.percent = percent
        self.resetText = resetText
    }
}

/// User-configurable caps for estimate mode (USD).
public struct EstimateCaps: Sendable {
    public var fiveHourUSD: Double
    public var weeklyUSD: Double

    public init(fiveHourUSD: Double, weeklyUSD: Double) {
        self.fiveHourUSD = fiveHourUSD
        self.weeklyUSD = weeklyUSD
    }
}
