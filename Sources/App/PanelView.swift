import SwiftUI
import UsageCore

/// The dropdown panel: each account's two limit meters, plus actions.
struct PanelView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if store.accounts.isEmpty {
                Text("Add an account in Preferences to see your usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Divider() }
                    accountSection(account)
                }
            }

            Divider()
            actions
        }
        .padding(12)
        .frame(width: 300)
    }

    @ViewBuilder
    private func accountSection(_ account: Account) -> some View {
        let entry = store.usage[account.id]
        VStack(alignment: .leading, spacing: 6) {
            if store.accounts.count > 1 {
                HStack(spacing: 5) {
                    if account.showInMenuBar {
                        Circle().fill(Color.secondary).frame(width: 5, height: 5)
                    }
                    Text(account.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let snapshot = entry?.snapshot {
                MeterView(title: "5-hour limit", meter: snapshot.fiveHour)
                MeterView(title: "Weekly limit", meter: snapshot.weekly)
                if let fable = snapshot.fableWeekly {
                    MeterView(title: "Current week (Fable)", meter: fable)
                }
            } else if let error = entry?.error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            ClawdView(size: 20)
            Text("Claude Usage").font(.headline)
            Spacer()
            if let updated = store.usage.values.compactMap({ $0.snapshot?.updatedAt }).max() {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Format.updatedAgo(updated, now: context.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            ActionRow(title: "Open claude.ai usage page") {
                NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
            }
            ActionRow(title: store.isRefreshing ? "Refreshing…" : "Refresh now") {
                Task { await store.refresh() }
            }
            ActionRow(title: "Preferences…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            ActionRow(title: "Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct ActionRow: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(hovering ? Color.secondary.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct MeterView: View {
    let title: String
    let meter: Meter

    private var barColor: Color { Palette.color(pace: meter.pace?.state, percent: meter.percent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout.weight(.semibold))
                Spacer()
                Text(Format.percent(meter.percent))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(barColor)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * ((meter.percent ?? 0) / 100))
                }
            }
            .frame(height: 7)

            if let subtitle {
                subtitle.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// "resets in 3h · 🔥 fast · ~1h 10m left" — the pace emoji is a separate
    /// Text run nudged up so it sits on the text baseline (emoji render low).
    private var subtitle: Text? {
        guard let pace = meter.pace else {
            return meter.resetText.isEmpty ? nil : Text(meter.resetText)
        }
        let emoji = Text(Format.paceEmoji(pace)).baselineOffset(2)
        let label = Text(" " + Format.paceLabel(pace))
        if meter.resetText.isEmpty {
            return emoji + label
        }
        return Text(meter.resetText + " · ") + emoji + label
    }
}
