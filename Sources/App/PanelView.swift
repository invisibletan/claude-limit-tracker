import SwiftUI
import UsageCore

/// The dropdown panel: two limit meters and actions.
struct PanelView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let snapshot = store.snapshot {
                MeterView(title: "5-hour limit", meter: snapshot.fiveHour)
                MeterView(title: "Weekly limit", meter: snapshot.weekly)
                if let error = store.lastError {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
            } else if store.needsToken {
                Text("Add a token in Preferences to see your usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = store.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading usage…").font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()
            actions
        }
        .padding(12)
        .frame(width: 280)
    }

    private var header: some View {
        HStack(alignment: .center) {
            ClawdView(size: 20)
            Text("Claude Usage").font(.headline)
            Spacer()
            if let snapshot = store.snapshot {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Format.updatedAgo(snapshot.updatedAt, now: context.date))
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

    private var barColor: Color { Palette.color(forPercent: meter.percent) }

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

            if !meter.resetText.isEmpty {
                Text(meter.resetText).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
