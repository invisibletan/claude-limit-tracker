import SwiftUI
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var store: UsageStore

    @AppStorage(PrefKey.cap5h) private var cap5h = 35.0
    @AppStorage(PrefKey.capWeekly) private var capWeekly = 500.0
    @AppStorage(PrefKey.refreshInterval) private var refreshInterval = 30.0
    @AppStorage(PrefKey.ccusagePath) private var ccusagePath = ""

    @State private var pkce: ClaudeOAuth.PKCE?
    @State private var pastedCode = ""
    @State private var signedIn = TokenStore.loadCredentials() != nil
    @State private var authStatus: String?
    @State private var authStatusIsError = false
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
                Section("Official usage data (recommended)") {
                    if signedIn {
                        HStack {
                            Label("Signed in with Claude", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Test connection") { testConnection() }
                                .disabled(isWorking)
                            Button("Sign out") { signOut() }
                        }
                    } else {
                        Button("Sign in with Claude…") { startSignIn() }
                        if pkce != nil {
                            TextField("Paste the code shown after approving", text: $pastedCode)
                                .textFieldStyle(.roundedBorder)
                            Button("Complete sign-in") { completeSignIn() }
                                .disabled(pastedCode.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                        }
                    }
                    if let authStatus {
                        Text(authStatus)
                            .font(.caption)
                            .foregroundStyle(authStatusIsError ? .red : .green)
                            .textSelection(.enabled)
                    }
                    Text("Signing in opens claude.ai in your browser (same OAuth flow Claude Code uses). Approve, copy the code it shows, and paste it here. Percentages and reset times then come straight from Anthropic — identical to claude.ai Settings → Usage. Credentials live in a chmod-600 file, never the Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Estimate caps (used when signed out)") {
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
                    Text("Percentages in estimate mode are cost ÷ cap — a rough proxy only; sign in above for real numbers.")
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
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func startSignIn() {
        let fresh = ClaudeOAuth.generatePKCE()
        pkce = fresh
        pastedCode = ""
        authStatus = "Browser opened — approve, then paste the code below."
        authStatusIsError = false
        NSWorkspace.shared.open(ClaudeOAuth.authorizeURL(pkce: fresh))
    }

    private func completeSignIn() {
        guard let pkce else { return }
        isWorking = true
        authStatus = "Exchanging code…"
        authStatusIsError = false
        Task {
            defer { isWorking = false }
            do {
                let creds = try await ClaudeOAuth.exchange(pastedCode: pastedCode, pkce: pkce)
                try TokenStore.save(creds)
                signedIn = true
                pastedCode = ""
                self.pkce = nil
                await verifyAndReport(creds: creds)
                await store.refresh()
            } catch {
                authStatus = error.localizedDescription
                authStatusIsError = true
            }
        }
    }

    private func testConnection() {
        guard let creds = TokenStore.loadCredentials() else {
            signedIn = false
            return
        }
        isWorking = true
        authStatus = "Testing…"
        authStatusIsError = false
        Task {
            defer { isWorking = false }
            await verifyAndReport(creds: creds)
        }
    }

    private func verifyAndReport(creds: ClaudeOAuth.Credentials) async {
        do {
            var creds = creds
            if creds.needsRefresh, let refreshToken = creds.refreshToken {
                creds = try await ClaudeOAuth.refresh(refreshToken: refreshToken)
                try? TokenStore.save(creds)
            }
            let usage = try await OfficialAPI.fetch(token: creds.accessToken)
            let summary = usage.windows
                .map { "\($0.label) \(Format.percent($0.utilization))" }
                .joined(separator: ", ")
            authStatus = "Connected — \(summary)."
            authStatusIsError = false
        } catch {
            authStatus = error.localizedDescription
            authStatusIsError = true
        }
    }

    private func signOut() {
        TokenStore.clear()
        signedIn = false
        pkce = nil
        pastedCode = ""
        authStatus = "Signed out — using local estimates."
        authStatusIsError = false
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
