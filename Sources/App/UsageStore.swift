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
    static let showMenuBarWeekly = "showMenuBarWeekly"
    static let defaultShowMenuBarWeekly = true
    /// Legacy picker key — read once for migration, no longer written.
    static let legacyPaceDisplay = "menuBarPaceDisplay"
    static let showMenuBarMascot = "showMenuBarMascot"
    static let defaultShowMenuBarMascot = true
    static let showMenuBarRing = "showMenuBarRing"
    static let defaultShowMenuBarRing = true
    static let showMenuBarPercent = "showMenuBarPercent"
    static let defaultShowMenuBarPercent = true
    static let showMenuBarWeeklyRing = "showMenuBarWeeklyRing"
    static let defaultShowMenuBarWeeklyRing = false
    static let sessionGlyph = "showMenuBarSessionGlyph"
    static let weeklyGlyph = "showMenuBarWeeklyGlyph"
    static let sessionPaceSlow = "showMenuBarSessionPaceSlow"
    static let sessionPaceSteady = "showMenuBarSessionPaceSteady"
    static let sessionPaceFast = "showMenuBarSessionPaceFast"
    static let weeklyPaceSlow = "showMenuBarWeeklyPaceSlow"
    static let weeklyPaceSteady = "showMenuBarWeeklyPaceSteady"
    static let weeklyPaceFast = "showMenuBarWeeklyPaceFast"
    static let fableRing = "showMenuBarFableRing"
    static let fablePercent = "showMenuBarFablePercent"
    static let fableGlyph = "showMenuBarFableGlyph"
    static let fablePaceSlow = "showMenuBarFablePaceSlow"
    static let fablePaceSteady = "showMenuBarFablePaceSteady"
    static let fablePaceFast = "showMenuBarFablePaceFast"
    static let notifyPaceFast = "notifyPaceFast"
    static let defaultNotifyPaceFast = true
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

    /// Last-seen pace state per account per window, for Fast-crossing alerts.
    /// An account is absent until its first successful refresh (which seeds it
    /// silently); only later transitions notify.
    private var paceMemory: [UUID: WindowPaceStates] = [:]
    private let notifier = PaceNotifier()

    var hasAccounts: Bool { !accounts.isEmpty }

    init() {
        let defaults = UserDefaults.standard
        // One-time migration: the retired pace picker value becomes per-state
        // checkboxes (+ the ring-color toggle) the first time this build runs.
        if defaults.object(forKey: PrefKey.sessionPaceFast) == nil,
           let legacy = defaults.string(forKey: PrefKey.legacyPaceDisplay) {
            let migrated = PaceDisplay.migrateLegacy(rawValue: legacy)
            for (key, value) in [
                PrefKey.sessionPaceSlow: migrated.selection.slow,
                PrefKey.sessionPaceSteady: migrated.selection.steady,
                PrefKey.sessionPaceFast: migrated.selection.fast,
                PrefKey.weeklyPaceSlow: migrated.selection.slow,
                PrefKey.weeklyPaceSteady: migrated.selection.steady,
                PrefKey.weeklyPaceFast: migrated.selection.fast,
                PrefKey.sessionGlyph: migrated.glyphs,
                PrefKey.weeklyGlyph: migrated.glyphs,
            ] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.register(defaults: [
            PrefKey.refreshInterval: PrefKey.defaultRefreshInterval,
            PrefKey.showMenuBarNames: PrefKey.defaultShowMenuBarNames,
            PrefKey.showMenuBarWeekly: PrefKey.defaultShowMenuBarWeekly,
            PrefKey.showMenuBarMascot: PrefKey.defaultShowMenuBarMascot,
            PrefKey.showMenuBarRing: PrefKey.defaultShowMenuBarRing,
            PrefKey.showMenuBarPercent: PrefKey.defaultShowMenuBarPercent,
            PrefKey.showMenuBarWeeklyRing: PrefKey.defaultShowMenuBarWeeklyRing,
            PrefKey.sessionGlyph: true,
            PrefKey.weeklyGlyph: true,
            PrefKey.sessionPaceSlow: true,
            PrefKey.sessionPaceSteady: true,
            PrefKey.sessionPaceFast: true,
            PrefKey.weeklyPaceSlow: true,
            PrefKey.weeklyPaceSteady: true,
            PrefKey.weeklyPaceFast: true,
            PrefKey.fableRing: false,
            PrefKey.fablePercent: true,
            PrefKey.fableGlyph: true,
            PrefKey.fablePaceSlow: true,
            PrefKey.fablePaceSteady: true,
            PrefKey.fablePaceFast: true,
            PrefKey.notifyPaceFast: PrefKey.defaultNotifyPaceFast,
        ])
        if defaults.bool(forKey: PrefKey.notifyPaceFast) {
            notifier.requestAuthorization()
        }
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

    /// Ask macOS for notification permission — called when the user turns the
    /// Fast-pace alert on in Preferences (and once at launch if already on).
    func requestNotificationAuthorization() {
        notifier.requestAuthorization()
    }

    // MARK: Menu bar rendering

    private var menuBarEntries: [MenuBarEntry] {
        let visible = accounts.filter(\.showInMenuBar)
        let namesOn = UserDefaults.standard.bool(forKey: PrefKey.showMenuBarNames)
        let showNames = namesOn && visible.count > 1
        let interval = max(10.0, UserDefaults.standard.double(forKey: PrefKey.refreshInterval))
        return visible.map { account in
            let snapshot = usage[account.id]?.snapshot
            return MenuBarEntry(
                name: showNames ? account.name : nil,
                snapshot: snapshot,
                isStale: Staleness.isStale(lastSuccess: snapshot?.updatedAt, refreshInterval: interval)
            )
        }
    }

    private var menuBarConfig: MenuBarConfig {
        let defaults = UserDefaults.standard
        var config = MenuBarConfig()
        config.showMascot = defaults.bool(forKey: PrefKey.showMenuBarMascot)
        config.sessionRing = defaults.bool(forKey: PrefKey.showMenuBarRing)
        config.sessionPercent = defaults.bool(forKey: PrefKey.showMenuBarPercent)
        config.sessionGlyph = defaults.bool(forKey: PrefKey.sessionGlyph)
        config.sessionPace = PaceSelection(
            slow: defaults.bool(forKey: PrefKey.sessionPaceSlow),
            steady: defaults.bool(forKey: PrefKey.sessionPaceSteady),
            fast: defaults.bool(forKey: PrefKey.sessionPaceFast)
        )
        config.weeklyRing = defaults.bool(forKey: PrefKey.showMenuBarWeeklyRing)
        config.weeklyPercent = defaults.bool(forKey: PrefKey.showMenuBarWeekly)
        config.weeklyGlyph = defaults.bool(forKey: PrefKey.weeklyGlyph)
        config.weeklyPace = PaceSelection(
            slow: defaults.bool(forKey: PrefKey.weeklyPaceSlow),
            steady: defaults.bool(forKey: PrefKey.weeklyPaceSteady),
            fast: defaults.bool(forKey: PrefKey.weeklyPaceFast)
        )
        config.fableRing = defaults.bool(forKey: PrefKey.fableRing)
        config.fablePercent = defaults.bool(forKey: PrefKey.fablePercent)
        config.fableGlyph = defaults.bool(forKey: PrefKey.fableGlyph)
        config.fablePace = PaceSelection(
            slow: defaults.bool(forKey: PrefKey.fablePaceSlow),
            steady: defaults.bool(forKey: PrefKey.fablePaceSteady),
            fast: defaults.bool(forKey: PrefKey.fablePaceFast)
        )
        return config
    }

    private func advanceWalk(dt: Double) {
        let visiblePercents = accounts.filter(\.showInMenuBar)
            .compactMap { usage[$0.id]?.snapshot?.fiveHour.percent }
        let activity = min(1, max(0, (visiblePercents.max() ?? 0) / 100))
        let cyclesPerSecond = 0.6 + activity * 2.6   // gentle amble → brisk march
        walkPhase = (walkPhase + cyclesPerSecond * dt).truncatingRemainder(dividingBy: 1)
        iconImage = ClawdIcon.menuBarImage(entries: menuBarEntries, phase: walkPhase, height: 20, config: menuBarConfig)
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

        detectPaceCrossings(results: results, accounts: current)
    }

    // MARK: Fast-pace notifications

    /// Fire a notification whenever a freshly-fetched window crosses the Fast
    /// boundary (either way). Errored refreshes carry no new pace, so they're
    /// skipped — memory (and thus the baseline) only moves on real data.
    private func detectPaceCrossings(results: [UUID: AccountUsage], accounts current: [Account]) {
        let enabled = UserDefaults.standard.bool(forKey: PrefKey.notifyPaceFast)
        let showName = current.count > 1
        for account in current {
            guard let snapshot = results[account.id]?.snapshot else { continue }
            let next = WindowPaceStates(
                session: snapshot.fiveHour.pace?.state,
                weekly: snapshot.weekly.pace?.state,
                fable: snapshot.fableWeekly?.pace?.state
            )
            // `crossings` returns nothing when there is no prior baseline, so the
            // first refresh seeds silently — pre-existing Fast windows never fire.
            if enabled {
                let name = showName ? account.name : nil
                for crossing in PaceAlerts.crossings(from: paceMemory[account.id], to: next) {
                    notifier.notify(crossing.alert, accountName: name,
                                    window: label(crossing.window), percent: percent(crossing.window, in: snapshot))
                }
            }
            paceMemory[account.id] = next
        }
        // Forget removed accounts so a re-add starts from a clean baseline.
        paceMemory = paceMemory.filter { id, _ in current.contains { $0.id == id } }
    }

    private func label(_ window: PaceWindow) -> PaceWindowLabel {
        switch window {
        case .session: return .session
        case .weekly: return .weekly
        case .fable: return .fable
        }
    }

    private func percent(_ window: PaceWindow, in snapshot: UsageSnapshot) -> Double? {
        switch window {
        case .session: return snapshot.fiveHour.percent
        case .weekly: return snapshot.weekly.percent
        case .fable: return snapshot.fableWeekly?.percent
        }
    }
}
