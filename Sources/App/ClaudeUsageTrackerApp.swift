import SwiftUI
import UsageCore

@main
struct ClaudeUsageTrackerApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(store: store)
        }
    }

    private var menuBarLabel: some View {
        // Clawd on the left, then the usage ring, then the live 5-hour %.
        HStack(spacing: 4) {
            Image(nsImage: store.iconImage ?? ClawdIcon.sprite(phase: 0, height: 20))
            Image(nsImage: ClawdIcon.ring(percent: store.snapshot?.fiveHour.percent, state: ringState, size: 16))
            Text(Format.percent(store.snapshot?.fiveHour.percent))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }

    private var ringState: HealthState {
        let states = [store.snapshot?.fiveHour.state, store.snapshot?.weekly.state].compactMap { $0 }
        if states.contains(.crit) { return .crit }
        if states.contains(.warn) { return .warn }
        return .good
    }
}
