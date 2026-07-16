import SwiftUI
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var store: UsageStore

    @AppStorage(PrefKey.cap5h) private var cap5h = 35.0
    @AppStorage(PrefKey.capWeekly) private var capWeekly = 500.0
    @AppStorage(PrefKey.refreshInterval) private var refreshInterval = 30.0
    @AppStorage(PrefKey.ccusagePath) private var ccusagePath = ""

    @State private var signedIn = false
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
                    HStack {
                        if signedIn {
                            Label("Signed in to Claude", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Not signed in", systemImage: "person.crop.circle.badge.questionmark")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(signedIn ? "Check now" : "Sign in to Claude…") {
                            signedIn ? checkNow() : showLogin()
                        }
                        .disabled(isWorking)
                        if signedIn {
                            Button("Sign out") { signOut() }
                        }
                    }
                    if let authStatus {
                        Text(authStatus)
                            .font(.caption)
                            .foregroundStyle(authStatusIsError ? .red : .green)
                            .textSelection(.enabled)
                    }
                    Text("Sign in to claude.ai in a window inside this app. The app then reads your live 5-hour and weekly limits straight off Settings → Usage — the exact numbers you see there, per-model included. The session stays in the app's own storage; nothing is copied elsewhere. Click Check now after signing in.")
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
        .onAppear { refreshSignInState() }
    }

    private func showLogin() {
        authStatus = "Sign in in the window, then click Check now."
        authStatusIsError = false
        WebUsageReader.shared.showLogin()
    }

    private func checkNow() {
        isWorking = true
        authStatus = "Reading claude.ai…"
        authStatusIsError = false
        Task {
            defer { isWorking = false }
            switch await WebUsageReader.shared.fetchOfficial() {
            case .windows(let windows):
                signedIn = true
                let summary = windows
                    .map { "\($0.label) \(Format.percent($0.percent))" }
                    .joined(separator: ", ")
                authStatus = "Connected — \(summary)."
                authStatusIsError = false
                await store.refresh()
            case .needsLogin:
                signedIn = false
                authStatus = "Not signed in yet — click Sign in to Claude."
                authStatusIsError = true
            case .unavailable(let message):
                authStatus = message
                authStatusIsError = true
            }
        }
    }

    private func refreshSignInState() {
        Task { signedIn = await WebUsageReader.shared.hasSession() }
    }

    private func signOut() {
        isWorking = true
        Task {
            defer { isWorking = false }
            await WebUsageReader.shared.signOut()
            signedIn = false
            authStatus = "Signed out — using local estimates."
            authStatusIsError = false
            await store.refresh()
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
