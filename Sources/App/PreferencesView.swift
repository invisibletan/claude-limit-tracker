import SwiftUI
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var store: UsageStore

    @AppStorage(PrefKey.refreshInterval) private var refreshInterval = PrefKey.defaultRefreshInterval

    @State private var tokenInput = TokenStore.load() ?? ""
    @State private var tokenStatus: String?
    @State private var tokenStatusIsError = false
    @State private var isWorking = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ClawdView(size: 26)
                Text("Claude Usage Tracker").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Form {
                Section("Connect") {
                    SecureField("Token", text: $tokenInput, prompt: Text("paste from `claude setup-token`"))
                    HStack {
                        Button("Save & test") { saveAndTest() }
                            .disabled(isWorking)
                        Button("Clear") { clearToken() }
                        if let tokenStatus {
                            Text(tokenStatus)
                                .font(.caption)
                                .foregroundStyle(tokenStatusIsError ? .red : .green)
                                .textSelection(.enabled)
                        }
                    }
                    Text("Run `claude setup-token` in a terminal and paste the result here. The app reads your exact 5-hour and weekly limits from Anthropic's rate-limit headers — the same numbers as claude.ai Settings → Usage. Each refresh makes one tiny (1-token) API call. Stored in a chmod-600 file, never the Keychain.")
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
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func saveAndTest() {
        do {
            try TokenStore.save(tokenInput)
        } catch {
            tokenStatus = "Could not save: \(error.localizedDescription)"
            tokenStatusIsError = true
            return
        }
        guard let token = TokenStore.load() else {
            tokenStatus = "Token cleared."
            tokenStatusIsError = false
            return
        }
        isWorking = true
        tokenStatus = "Testing…"
        tokenStatusIsError = false
        Task {
            defer { isWorking = false }
            do {
                let usage = try await RateLimitUsage.fetchUsage(token: token)
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

    private func clearToken() {
        tokenInput = ""
        TokenStore.clear()
        tokenStatus = "Token cleared."
        tokenStatusIsError = false
        Task { await store.refresh() }
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
