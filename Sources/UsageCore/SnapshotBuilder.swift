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

        // Spin signal: prefer live burn rate, else how full the 5-hour window is.
        let activity: Double
        if let tpm = block?.tokensPerMinute {
            activity = min(1, tpm / 200_000)
        } else {
            activity = min(1, max(0, (fiveHour.percent ?? 0) / 100))
        }

        return UsageSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            extraMeters: extras,
            burnRateText: burnRateText,
            activityLevel: activity,
            source: official != nil ? .officialAPI : .localEstimate,
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
