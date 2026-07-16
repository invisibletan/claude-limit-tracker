import Foundation
import SwiftUI
import AppKit
import UsageCore

/// Defaults keys (and their default values) shared between the store and Preferences.
enum PrefKey {
    static let refreshInterval = "refreshIntervalSeconds"
    static let defaultRefreshInterval = 60.0
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var lastError: String?
    /// True when no token is configured yet.
    @Published var needsToken = TokenStore.load() == nil
    @Published var isRefreshing = false
    /// Current frame of the walking menu bar mascot.
    @Published var iconImage: NSImage?

    private var pollTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var walkPhase = 0.0

    init() {
        UserDefaults.standard.register(defaults: [PrefKey.refreshInterval: PrefKey.defaultRefreshInterval])
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

    /// Advances and re-renders Clawd: walk cadence rises with usage, and the ring
    /// shows the 5-hour usage (orange, red past the threshold).
    private func advanceWalk(dt: Double) {
        let activity = snapshot?.activityLevel ?? 0
        let cyclesPerSecond = 0.6 + activity * 2.6   // gentle amble → brisk march
        walkPhase = (walkPhase + cyclesPerSecond * dt).truncatingRemainder(dividingBy: 1)
        iconImage = ClawdIcon.menuBarImage(
            percent: snapshot?.fiveHour.percent,
            phase: walkPhase,
            height: 20
        )
    }

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let token = TokenStore.load() else {
            needsToken = true
            snapshot = nil
            lastError = nil
            return
        }
        needsToken = false
        do {
            let usage = try await RateLimitUsage.fetchUsage(token: token)
            snapshot = SnapshotBuilder.build(from: usage)
            lastError = nil
        } catch {
            // Keep the last snapshot visible; surface the error under it.
            lastError = error.localizedDescription
        }
    }
}
