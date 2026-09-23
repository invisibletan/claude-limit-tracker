import SwiftUI
import UsageCore

@main
struct ClaudeUsageTrackerApp: App {
    @StateObject private var store = UsageStore()

    // NOTE: `body` must never read per-frame (15fps) published state — doing
    // so re-evaluates this whole Scene (MenuBarExtra + Settings) every frame
    // and leaks Observation tracking (see MenuBarIconModel.swift). `store.iconModel`
    // is a stable `let` reference, not `@Published`, so passing it down here
    // is safe; only `MenuBarLabel`'s own view body observes its per-frame image.
    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuBarLabel(iconModel: store.iconModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(store: store)
        }
    }
}

/// The menu bar label, observing ONLY the per-frame icon model — everything
/// (Clawd + per-account rings + names + %) is one composited image.
private struct MenuBarLabel: View {
    @ObservedObject var iconModel: MenuBarIconModel

    var body: some View {
        Image(nsImage: iconModel.image ?? ClawdIcon.menuBarImage(entries: [], phase: 0, height: 20, config: MenuBarConfig()))
    }
}
