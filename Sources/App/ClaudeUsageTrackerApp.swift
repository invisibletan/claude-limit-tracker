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
        // The spinning spark (color + speed set by the store) plus the live 5-hour %.
        HStack(spacing: 3) {
            Image(nsImage: store.iconImage ?? ClawdIcon.image(percent: nil, state: .good, phase: 0))
            Text(Format.percent(store.snapshot?.fiveHour.percent))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }
}
