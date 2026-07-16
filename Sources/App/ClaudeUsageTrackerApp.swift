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
        let meter = store.snapshot?.fiveHour
        // Icon color tracks the worse of the two limits so a hot week
        // still shows even when the current session is quiet.
        let state = worstState
        return HStack(spacing: 3) {
            Image(nsImage: StatusIcon.ring(percent: meter?.percent, state: state))
            Text(Format.percent(meter?.percent))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }

    private var worstState: HealthState {
        let states = [store.snapshot?.fiveHour.state, store.snapshot?.weekly.state].compactMap { $0 }
        if states.contains(.crit) { return .crit }
        if states.contains(.warn) { return .warn }
        return .good
    }
}
