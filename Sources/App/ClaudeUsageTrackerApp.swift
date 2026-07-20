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
        // Everything (Clawd + per-account rings + names + %) is one image.
        Image(nsImage: store.iconImage ?? ClawdIcon.menuBarImage(entries: [], phase: 0, height: 20, config: MenuBarConfig()))
    }
}
