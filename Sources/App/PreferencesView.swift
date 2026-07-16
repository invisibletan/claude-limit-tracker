import SwiftUI
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var store: UsageStore

    @AppStorage(PrefKey.cap5h) private var cap5h = 35.0
    @AppStorage(PrefKey.capWeekly) private var capWeekly = 500.0
    @AppStorage(PrefKey.refreshInterval) private var refreshInterval = 30.0
    @AppStorage(PrefKey.ccusagePath) private var ccusagePath = ""

    @State private var tokenInput = TokenStore.load() ?? ""
    @State private var tokenStatus: String?
    @State private var tokenStatusIsError = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Official usage data (recommended)") {
                SecureField("OAuth token", text: $tokenInput, prompt: Text("paste token from `claude setup-token`"))
                HStack {
                    Button("Save & test") { saveAndTestToken() }
                    Button("Clear") {
                        tokenInput = ""
                        TokenStore.clear()
                        tokenStatus = "Token cleared — using local estimates."
                        tokenStatusIsError = false
                        Task { await store.refresh() }
                    }
                    if let tokenStatus {
                        Text(tokenStatus)
                            .font(.caption)
                            .foregroundStyle(tokenStatusIsError ? .red : .green)
                    }
                }
                Text("With a token, percentages and reset times come straight from Anthropic — the same numbers as claude.ai Settings → Usage. Run `claude setup-token` in a terminal and paste the result. Stored in a chmod-600 file, never the Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Estimate caps (used without a token)") {
                HStack {
                    Text("5-hour cap")
                    TextField("USD", value: $cap5h, format: .number)
                        .frame(width: 90)
                    Text("USD")
                }
                HStack {
                    Text("Weekly cap")
                    TextField("USD", value: $capWeekly, format: .number)
                        .frame(width: 90)
                    Text("USD")
                }
                Text("Percentages in estimate mode are cost ÷ cap. Tune these to where your plan actually cuts you off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                HStack {
                    Text("Refresh every")
                    TextField("seconds", value: $refreshInterval, format: .number)
                        .frame(width: 70)
                    Text("seconds")
                }
                TextField("ccusage path (blank = auto-detect)", text: $ccusagePath)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func saveAndTestToken() {
        do {
            try TokenStore.save(tokenInput)
        } catch {
            tokenStatus = "Could not save: \(error.localizedDescription)"
            tokenStatusIsError = true
            return
        }
        guard let token = TokenStore.load() else {
            tokenStatus = "Token cleared — using local estimates."
            tokenStatusIsError = false
            return
        }
        tokenStatus = "Testing…"
        tokenStatusIsError = false
        Task {
            do {
                let usage = try await OfficialAPI.fetch(token: token)
                let summary = usage.windows
                    .map { "\($0.label) \(Format.percent($0.utilization))" }
                    .joined(separator: ", ")
                tokenStatus = "Connected — \(summary)."
                tokenStatusIsError = false
                await store.refresh()
            } catch {
                tokenStatus = error.localizedDescription
                tokenStatusIsError = true
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Launch at login needs the bundled app (build.sh): \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
