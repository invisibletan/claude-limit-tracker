import Foundation
import SwiftUI
import AppKit
import UsageCore

/// Defaults keys (and their default values) shared between the store and Preferences.
enum PrefKey {
    static let refreshInterval = "refreshIntervalSeconds"
    static let defaultRefreshInterval = 60.0
    static let showMenuBarNames = "showMenuBarNames"
    static let defaultShowMenuBarNames = true
}

/// Fetched usage for one account.
struct AccountUsage {
    var snapshot: UsageSnapshot?
    var error: String?
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var accounts: [Account] = AccountStore.load()
    @Published var usage: [UUID: AccountUsage] = [:]
    @Published var isRefreshing = false
    /// Current frame of the walking menu bar mascot (+ per-account rings).
    @Published var iconImage: NSImage?

    private var pollTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var walkPhase = 0.0

    var hasAccounts: Bool { !accounts.isEmpty }

    init() {
        UserDefaults.standard.register(defaults: [
            PrefKey.refreshInterval: PrefKey.defaultRefreshInterval,
            PrefKey.showMenuBarNames: PrefKey.defaultShowMenuBarNames,
        ])
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = max(10.0, UserDefaults.standard.double(forKey: PrefKey.refreshInterval))
                try? await Task.sleep(for: .seconds(interval))
            }
        }
        animationTask = Task { [weak self] in
            let frame = 1.0 / 15.0
            while !Task.isCancelled {
                self?.advanceWalk(dt: frame)
                try? await Task.sleep(for: .seconds(frame))
            }
        }
    }

    deinit {
        pollTask?.cancel()
        animationTask?.cancel()
    }

    // MARK: Account management

    func reloadAccounts() {
        accounts = AccountStore.load()
        Task { await refresh() }
    }

    func persistAccounts() {
        try? AccountStore.save(accounts)
    }

    // MARK: Menu bar rendering

    private var menuBarEntries: [(name: String?, percent: Double?)] {
        let visible = accounts.filter(\.showInMenuBar)
        let namesOn = UserDefaults.standard.bool(forKey: PrefKey.showMenuBarNames)
        let showNames = namesOn && visible.count > 1
        return visible.map { account in
            (showNames ? account.name : nil, usage[account.id]?.snapshot?.fiveHour.percent)
        }
    }

    private func advanceWalk(dt: Double) {
        let visiblePercents = accounts.filter(\.showInMenuBar)
            .compactMap { usage[$0.id]?.snapshot?.fiveHour.percent }
        let activity = min(1, max(0, (visiblePercents.max() ?? 0) / 100))
        let cyclesPerSecond = 0.6 + activity * 2.6   // gentle amble → brisk march
        walkPhase = (walkPhase + cyclesPerSecond * dt).truncatingRemainder(dividingBy: 1)
        iconImage = ClawdIcon.menuBarImage(entries: menuBarEntries, phase: walkPhase, height: 20)
    }

    // MARK: Refresh

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let current = accounts
        let results = await withTaskGroup(of: (UUID, AccountUsage).self) { group in
            for account in current {
                group.addTask {
                    do {
                        let usage = try await RateLimitUsage.fetchUsage(token: account.token)
                        return (account.id, AccountUsage(snapshot: SnapshotBuilder.build(from: usage), error: nil))
                    } catch {
                        return (account.id, AccountUsage(snapshot: nil, error: error.localizedDescription))
                    }
                }
            }
            var out: [UUID: AccountUsage] = [:]
            for await (id, result) in group { out[id] = result }
            return out
        }

        // Merge: keep the last good snapshot when a refresh errors.
        var merged = usage
        for account in current {
            guard let fresh = results[account.id] else { continue }
            if fresh.snapshot != nil {
                merged[account.id] = fresh
            } else {
                merged[account.id] = AccountUsage(snapshot: usage[account.id]?.snapshot, error: fresh.error)
            }
        }
        // Drop usage for removed accounts.
        merged = merged.filter { id, _ in current.contains { $0.id == id } }
        usage = merged
    }
}
