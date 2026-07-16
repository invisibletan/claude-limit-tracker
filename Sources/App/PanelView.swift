import SwiftUI
import UsageCore

/// The dropdown panel: two limit meters, burn rate, actions.
struct PanelView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let snapshot = store.snapshot {
                MeterView(title: "5-hour limit", meter: snapshot.fiveHour)
                MeterView(title: "Weekly limit", meter: snapshot.weekly)

                if let burn = snapshot.burnRateText {
                    Divider()
                    HStack {
                        Text("Burn rate")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(burn)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }

                sourceFootnote(snapshot)
            } else if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading usage…").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let warning = store.officialWarning {
                Text("Official API: \(warning)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if store.snapshot != nil, let error = store.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Divider()
            actions
        }
        .padding(12)
        .frame(width: 280)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
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

    private func sourceFootnote(_ snapshot: UsageSnapshot) -> some View {
        Text(snapshot.source == .officialAPI
             ? "Official Anthropic usage data"
             : "Estimated from local logs vs. your caps")
            .font(.caption2)
            .foregroundStyle(.tertiary)
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

    private var barColor: Color {
        switch meter.state {
        case .good: return Color(red: 0.25, green: 0.62, blue: 0.36)
        case .warn: return Color(red: 0.85, green: 0.58, blue: 0.13)
        case .crit: return Color(red: 0.82, green: 0.28, blue: 0.23)
        }
    }

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

            HStack(spacing: 4) {
                if !meter.detail.isEmpty {
                    Text(meter.detail)
                }
                if !meter.detail.isEmpty && !meter.resetText.isEmpty {
                    Text("·")
                }
                if !meter.resetText.isEmpty {
                    Text(meter.resetText).fontWeight(.medium)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
