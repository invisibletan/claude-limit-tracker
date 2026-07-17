# 🐾 Claude Usage Tracker

> Keep your Claude **5-hour** and **weekly** usage limits one glance away — right in your macOS menu bar.

![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![UI](https://img.shields.io/badge/UI-SwiftUI%20MenuBarExtra-0A84FF)
![Dependencies](https://img.shields.io/badge/dependencies-none-2ea44f)

A tiny, native macOS menu bar app. An animated pixel **Clawd** 🐾 walks across your menu bar, a ring fills up with your current usage, and the live percentage sits right beside it. Track **multiple accounts** at once, and see at a glance whether you're burning through your limit **fast, steady, or slow**. Click for the full breakdown. Built with SwiftUI `MenuBarExtra` — **zero external dependencies.**

<!-- Add a screenshot once you have one:
![Claude Usage Tracker in the menu bar](docs/screenshot.png)
-->

> 🌏 Thai user guide: see **[USER_MANUAL.md](USER_MANUAL.md)**.

---

## ✨ Features

- 🐾 **Animated Clawd mascot** — walks faster the harder you're using Claude.
- ⭕ **Usage ring** — fills with your 5-hour usage; **orange** normally, **red** past 80%.
- 👥 **Multiple accounts** — track up to **10** Claude accounts side by side; show or hide each one on the menu bar.
- 🔥 **Pace signal** — tells you whether you're burning **🔥 fast**, **😎 steady**, or **🐢 slow**, with an estimated time until you hit the limit.
- 📊 **Both limits at a glance** — 5-hour and weekly meters per account in a click-through panel.
- 🎯 **Exact numbers** — the same figures as *claude.ai → Settings → Usage*, not an estimate.
- 🪶 **Featherweight** — one small binary, no dependencies, no background bloat.
- 🔒 **Private by design** — tokens stay on your Mac (a `0600` file, never the Keychain).

---

## 🚀 Quick start

```bash
git clone https://github.com/invisibletan/claude-limit-tracker.git
cd claude-limit-tracker
./run.sh
```

`run.sh` builds the release app and launches it — **Clawd appears in your menu bar** (top-right). That's the whole install.

> 💡 Prefer to do it by hand? `./build.sh`, then `open "build/Claude Usage Tracker.app"`.

---

## 🔑 First-time setup

The usage numbers come from *your* account, so each account connects once:

1. 🖥️ In a terminal, run **`claude setup-token`** *(needs a Claude subscription + Claude Code)*.
2. 📋 Copy the token it prints — it starts with `sk-ant-oat01-…`.
3. 🐾 Click **Clawd** → **Preferences…** → **Accounts** → **Add account…** → give it a name, paste the token, **Add & test**.

The account's real percentages appear right away. Repeat for up to **10** accounts. 🎉

> 🔐 Tokens are per-account — everyone generates their own; you can't share one.

---

## 🧠 How it works

For each account, every refresh fires **one tiny (~1-token) `POST /v1/messages`** call and reads the usage straight from the response headers:

| Header | Meaning |
| --- | --- |
| `anthropic-ratelimit-unified-5h-utilization` | 5-hour usage (`0`–`1`) |
| `anthropic-ratelimit-unified-5h-reset` | when the 5-hour window resets |
| `anthropic-ratelimit-unified-7d-*` | the weekly equivalents |

That's the same data behind *claude.ai → Settings → Usage*. The `user:inference` token from `claude setup-token` is all it needs — **no Keychain, no `user:profile` scope, no browser login.**

The **pace** is derived locally: it compares how much you've used against how far you are into the window (a 5-hour window fills evenly at 20%/hour), so you know if you'll run out early.

> ℹ️ These headers expose only the **5-hour** and **weekly (all-models)** windows. Per-model limits (e.g. a Fable-only weekly) aren't available from this source.

*Technique credit: [Clawdmeter](https://github.com/HermannBjorgvin/Clawdmeter).*

---

## 🖥️ In the menu bar

- 🐾 **Clawd** strolls along — pace scales with your usage.
- ⭕ A **ring** per shown account fills with its 5-hour usage.
- 🟠 → 🔴 Everything turns **red at 80%**, so you notice before you hit the wall.
- 🖱️ **Click** to open the panel: each account's **5-hour** and **weekly** meters, each showing the reset time and the pace — e.g. `resets in 3h · 🔥 fast · ~1h 10m left`.

---

## ⚙️ Preferences

**Accounts (up to 10)**

| Control | What it does |
| --- | --- |
| **Add account…** | Name it, paste the token from `claude setup-token`, then **Add & test** verifies it live before saving. |
| **Name** | Rename any account inline. |
| **Menu bar** | Per-account toggle — show or hide that account's ring on the menu bar. |
| **🗑️** | Remove an account. |

**Behavior**

| Setting | What it does |
| --- | --- |
| **Refresh every … seconds** | How often to poll — default **60s** (~1 token per account each refresh). |
| **Show account names on menu bar** | Label each ring with its account name. |
| **Launch at login** | Start with macOS via `SMAppService`. |

Accounts are stored at `~/Library/Application Support/ClaudeUsageTracker/accounts.json` (`0600`). A legacy single-token file is migrated automatically on first launch.

---

## 🛠️ Development

```bash
swift build      # 🔨 debug compile
swift run        # ▶️  run unbundled (menu bar item appears; launch-at-login off)
./test.sh        # 🧪 unit tests (wraps `swift test` with CLT fixups)
./build.sh       # 📦 release build → build/Claude Usage Tracker.app
```

**Project layout**

- `Sources/UsageCore/` — the testable data core: fetch + parse rate-limit headers, build snapshots, compute pace, formatting.
- `Sources/App/` — the SwiftUI app: `MenuBarExtra`, Clawd mascot + ring drawing, panel, preferences, per-account store.
- `Tests/UsageCoreTests/` — header-parsing, snapshot, and pace tests.

> 🧪 `test.sh` adds flags so `swift-testing` links under **Command Line Tools only** (no full Xcode needed). With full Xcode, plain `swift test` works too.

---

## 📋 Requirements

- 🍎 **macOS 14+**
- 🧰 **Xcode Command Line Tools** (Swift 5.9+) — full Xcode *not* required.
- 🔑 A **Claude subscription + Claude Code** (for `claude setup-token`) to see live data.

---

## 🙏 Credits

- Rate-limit-header technique inspired by **[Clawdmeter](https://github.com/HermannBjorgvin/Clawdmeter)**.
- Clawd 🐾 — your friendly usage companion.

---

## 📄 License

[MIT](LICENSE) © invisibletan
