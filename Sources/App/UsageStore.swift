import Foundation
import SwiftUI
import UsageCore

/// Defaults keys shared between the store and Preferences.
enum PrefKey {
    static let cap5h = "capFiveHourUSD"
    static let capWeekly = "capWeeklyUSD"
    static let refreshInterval = "refreshIntervalSeconds"
    static let ccusagePath = "ccusagePathOverride"
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var lastError: String?
    /// Non-fatal: the token check failed but the estimate fallback still rendered.
    @Published var officialWarning: String?
    @Published var isRefreshing = false

    private var pollTask: Task<Void, Never>?

    init() {
        registerDefaults()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = max(10.0, UserDefaults.standard.double(forKey: PrefKey.refreshInterval))
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    deinit {
        pollTask?.cancel()
    }

    private func registerDefaults() {
        // Caps calibrated to a Max 20× plan so the estimate tracks the real
        // Settings → Usage page: weekly ~$9,000 maps ~$458 spent to ~5%,
        // 5-hour ~$35 maps a hot session to ~20%. Tunable in Preferences.
        UserDefaults.standard.register(defaults: [
            PrefKey.cap5h: 35.0,
            PrefKey.capWeekly: 9000.0,
            // Each official read spends ~1 token; 60s keeps that negligible.
            PrefKey.refreshInterval: 60.0,
        ])
    }

    var caps: EstimateCaps {
        EstimateCaps(
            fiveHourUSD: UserDefaults.standard.double(forKey: PrefKey.cap5h),
            weeklyUSD: UserDefaults.standard.double(forKey: PrefKey.capWeekly)
        )
    }

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // 1. Exact 5h/weekly from the rate-limit headers, if a token is stored.
        var official: OfficialUsage?
        var officialErr: String?
        if let token = TokenStore.load() {
            do {
                official = try await RateLimitUsage.fetchUsage(token: token)
            } catch {
                officialErr = error.localizedDescription
            }
        }

        // 2. Local estimate from ccusage — cost detail, burn rate, and the
        // meters/percentages used when no token is configured.
        let runner = CCUsageRunner(overridePath: UserDefaults.standard.string(forKey: PrefKey.ccusagePath))
        var block: CCUsage.ActiveBlock?
        var weeklyCost: Double?
        var estimateErr: String?
        var blockSucceeded = false
        do {
            block = try await runner.fetchActiveBlock()
            blockSucceeded = true
        } catch {
            estimateErr = error.localizedDescription
        }
        do {
            weeklyCost = try await runner.fetchWeeklyCost()
        } catch {
            estimateErr = estimateErr ?? error.localizedDescription
        }

        officialWarning = officialErr

        let estimateAvailable = blockSucceeded || weeklyCost != nil
        if official == nil && !estimateAvailable {
            // Keep the stale snapshot visible, surface the error.
            lastError = officialErr ?? estimateErr ?? "No usage data available."
            return
        }

        // Partial estimate failure renders as a footnote under the meters.
        lastError = estimateErr
        snapshot = SnapshotBuilder.build(
            official: official,
            block: block,
            weeklyCostUSD: weeklyCost,
            caps: caps
        )
    }
}
