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
        // Single composited image (Clawd + ring) plus the live 5-hour %.
        HStack(spacing: 4) {
            Image(nsImage: store.iconImage ?? ClawdIcon.menuBarImage(percent: nil, phase: 0, height: 20))
            Text(Format.percent(store.snapshot?.fiveHour.percent))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }
}
