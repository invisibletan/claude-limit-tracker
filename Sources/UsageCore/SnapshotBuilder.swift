import Foundation

/// Merges the two data sources into one `UsageSnapshot`.
///
/// Priority: official API percentages and reset times when available (exact,
/// matches claude.ai Settings → Usage); ccusage fills in cost detail and burn
/// rate, and carries the whole snapshot alone when no token is configured.
public enum SnapshotBuilder {
    public static func build(
        official: OfficialUsage?,
        block: CCUsage.ActiveBlock?,
        weeklyCostUSD: Double?,
        caps: EstimateCaps,
        now: Date = Date()
    ) -> UsageSnapshot {
        let fiveHour = fiveHourMeter(official: official, block: block, caps: caps, now: now)
        let weekly = weeklyMeter(official: official, weeklyCostUSD: weeklyCostUSD, caps: caps, now: now)

        // Per-model weekly windows the official endpoint reports beyond the headline two.
        let extras = (official?.extraWindows ?? []).map { window in
            ExtraMeter(
                title: window.label,
                meter: Meter(
                    percent: min(100, max(0, window.utilization)),
                    detail: "",
                    resetText: Format.reset(window.resetsAt, now: now)
                )
            )
        }

        var burnRateText: String?
        if let tpm = block?.tokensPerMinute {
            burnRateText = Format.tokensPerMinute(tpm)
        }

        return UsageSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            extraMeters: extras,
            burnRateText: burnRateText,
            source: official != nil ? .officialAPI : .localEstimate,
            updatedAt: now
        )
    }

    /// Builds a snapshot from windows scraped off claude.ai Settings → Usage,
    /// keeping ccusage's burn rate / cost detail for context.
    public static func buildFromWeb(
        windows: [WebWindow],
        block: CCUsage.ActiveBlock?,
        weeklyCostUSD: Double?,
        now: Date = Date()
    ) -> UsageSnapshot {
        func meter(for window: WebWindow, costDetail: String = "") -> Meter {
            Meter(
                percent: min(100, max(0, window.percent)),
                detail: costDetail,
                resetText: window.resetText
            )
        }

        // Map the page's labels onto the two headline meters; the rest become extras.
        var fiveHour: Meter?
        var weekly: Meter?
        var extras: [ExtraMeter] = []

        var fiveHourDetail = ""
        if let block {
            fiveHourDetail = "\(Format.money(block.costUSD)) used"
            if let projected = block.projectedCostUSD {
                fiveHourDetail += " · projected \(Format.money(projected))"
            }
        }
        let weeklyDetail = weeklyCostUSD.map { "\(Format.money($0)) used" } ?? ""

        for window in windows {
            let lower = window.label.lowercased()
            if fiveHour == nil, lower.contains("session") || lower.contains("5-hour") || lower.contains("5 hour") {
                fiveHour = meter(for: window, costDetail: fiveHourDetail)
            } else if weekly == nil, lower.contains("all models") || lower.contains("weekly") {
                weekly = meter(for: window, costDetail: weeklyDetail)
            } else {
                extras.append(ExtraMeter(title: window.label, meter: meter(for: window)))
            }
        }

        var burnRateText: String?
        if let tpm = block?.tokensPerMinute {
            burnRateText = Format.tokensPerMinute(tpm)
        }

        return UsageSnapshot(
            fiveHour: fiveHour ?? Meter(percent: nil, detail: fiveHourDetail, resetText: ""),
            weekly: weekly ?? Meter(percent: nil, detail: weeklyDetail, resetText: ""),
            extraMeters: extras,
            burnRateText: burnRateText,
            source: .webSession,
            updatedAt: now
        )
    }

    static func fiveHourMeter(
        official: OfficialUsage?,
        block: CCUsage.ActiveBlock?,
        caps: EstimateCaps,
        now: Date
    ) -> Meter {
        var detailParts: [String] = []
        if let block {
            detailParts.append("\(Format.money(block.costUSD)) used")
            if let projected = block.projectedCostUSD {
                detailParts.append("projected \(Format.money(projected))")
            }
        }

        if let utilization = official?.fiveHourUtilization {
            return Meter(
                percent: min(100, max(0, utilization)),
                detail: detailParts.isEmpty ? "official usage" : detailParts.joined(separator: " · "),
                resetText: Format.reset(official?.fiveHourResetsAt, now: now)
            )
        }

        guard let block else {
            return Meter(percent: 0, detail: "no active session", resetText: "")
        }
        let percent = caps.fiveHourUSD > 0 ? min(100, block.costUSD / caps.fiveHourUSD * 100) : nil
        return Meter(
            percent: percent,
            detail: detailParts.joined(separator: " · "),
            resetText: Format.reset(block.endTime, now: now)
        )
    }

    static func weeklyMeter(
        official: OfficialUsage?,
        weeklyCostUSD: Double?,
        caps: EstimateCaps,
        now: Date
    ) -> Meter {
        var detail = ""
        if let weeklyCostUSD {
            detail = "\(Format.money(weeklyCostUSD)) used"
        }

        if let utilization = official?.sevenDayUtilization {
            return Meter(
                percent: min(100, max(0, utilization)),
                detail: detail.isEmpty ? "official usage" : detail,
                resetText: Format.reset(official?.sevenDayResetsAt, now: now)
            )
        }

        guard let weeklyCostUSD else {
            return Meter(percent: nil, detail: "no data", resetText: "")
        }
        let percent = caps.weeklyUSD > 0 ? min(100, weeklyCostUSD / caps.weeklyUSD * 100) : nil
        return Meter(percent: percent, detail: detail, resetText: "rolling 7 days")
    }
}
