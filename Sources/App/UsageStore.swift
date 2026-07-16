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
    /// Non-fatal: official API failed but the estimate fallback still rendered.
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
        UserDefaults.standard.register(defaults: [
            PrefKey.cap5h: 35.0,
            PrefKey.capWeekly: 500.0,
            PrefKey.refreshInterval: 30.0,
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

        // 1. Exact numbers from claude.ai via the in-app web session.
        var webWindows: [WebWindow]?
        var officialErr: String?
        switch await WebUsageReader.shared.fetchOfficial() {
        case .windows(let windows):
            webWindows = windows
        case .needsLogin:
            officialErr = "Sign in from Preferences for exact numbers."
        case .unavailable:
            // Silent: fall back to estimates without nagging.
            break
        }

        // 2. Local estimate — cost detail + burn rate, and the sole source when signed out.
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
        if webWindows == nil && !estimateAvailable {
            // Both sources failed — keep the stale snapshot visible, surface the error.
            lastError = officialErr ?? estimateErr ?? "No usage data available."
            return
        }

        // Partial estimate failure renders as a footnote under the meters.
        lastError = estimateErr
        if let webWindows {
            snapshot = SnapshotBuilder.buildFromWeb(
                windows: webWindows,
                block: block,
                weeklyCostUSD: weeklyCost
            )
        } else {
            snapshot = SnapshotBuilder.build(
                official: nil,
                block: block,
                weeklyCostUSD: weeklyCost,
                caps: caps
            )
        }
    }
}
