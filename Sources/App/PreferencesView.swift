import SwiftUI
import ServiceManagement
import UsageCore

struct PreferencesView: View {
    @ObservedObject var store: UsageStore

    @AppStorage(PrefKey.refreshInterval) private var refreshInterval = PrefKey.defaultRefreshInterval
    @AppStorage(PrefKey.showMenuBarNames) private var showMenuBarNames = PrefKey.defaultShowMenuBarNames

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    // Add-account form
    @State private var showAddForm = false
    @State private var newName = ""
    @State private var newToken = ""
    @State private var addStatus: String?
    @State private var addStatusIsError = false
    @State private var isTesting = false

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
                Section("Accounts (\(store.accounts.count)/\(AccountStore.maxAccounts))") {
                    ForEach($store.accounts) { $account in
                        HStack(spacing: 8) {
                            TextField("Name", text: $account.name)
                                .onChange(of: account.name) { _, _ in store.persistAccounts() }
                            Toggle("Menu bar", isOn: $account.showInMenuBar)
                                .toggleStyle(.checkbox)
                                .onChange(of: account.showInMenuBar) { _, _ in store.persistAccounts() }
                            Button(role: .destructive) { remove(account) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    if showAddForm {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Account name", text: $newName)
                            SecureField("Token", text: $newToken, prompt: Text("paste from `claude setup-token`"))
                            HStack {
                                Button("Add & test") { addAndTest() }
                                    .disabled(isTesting || newToken.trimmingCharacters(in: .whitespaces).isEmpty)
                                Button("Cancel") { resetAddForm() }
                                if let addStatus {
                                    Text(addStatus).font(.caption)
                                        .foregroundStyle(addStatusIsError ? .red : .green)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    } else {
                        Button("Add account…") {
                            newName = "Account \(store.accounts.count + 1)"
                            showAddForm = true
                        }
                        .disabled(store.accounts.count >= AccountStore.maxAccounts)
                    }

                    Text("Run `claude setup-token` in a terminal and paste the result. Each account reads its own exact 5-hour and weekly limits from Anthropic's rate-limit headers. Tokens are per-account, stored in a chmod-600 file, never the Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Behavior") {
                    HStack {
                        Text("Refresh every")
                        TextField("", value: $refreshInterval, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Text("seconds")
                        Spacer()
                    }
                    Toggle("Show account names on menu bar", isOn: $showMenuBarNames)
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
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

    private func remove(_ account: Account) {
        store.accounts.removeAll { $0.id == account.id }
        store.persistAccounts()
        store.usage[account.id] = nil
    }

    private func addAndTest() {
        let name = newName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Account \(store.accounts.count + 1)" : newName
        let token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isTesting = true
        addStatus = "Testing…"
        addStatusIsError = false
        Task {
            defer { isTesting = false }
            do {
                let usage = try await RateLimitUsage.fetchUsage(token: token)
                store.accounts.append(Account(name: name, token: token, showInMenuBar: true))
                store.persistAccounts()
                await store.refresh()
                let summary = usage.windows.map { "\($0.label) \(Format.percent($0.utilization))" }
                    .joined(separator: ", ")
                addStatus = "Added — \(summary)."
                resetAddForm(keepStatus: true)
            } catch {
                addStatus = error.localizedDescription
                addStatusIsError = true
            }
        }
    }

    private func resetAddForm(keepStatus: Bool = false) {
        showAddForm = false
        newName = ""
        newToken = ""
        if !keepStatus { addStatus = nil }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "Launch at login needs the bundled app (build.sh): \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
