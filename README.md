# 🐾 Claude Usage Tracker

> Keep your Claude **5-hour** and **weekly** usage limits one glance away — right in your macOS menu bar.

![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![UI](https://img.shields.io/badge/UI-SwiftUI%20MenuBarExtra-0A84FF)
![Dependencies](https://img.shields.io/badge/dependencies-none-2ea44f)

A tiny, native macOS menu bar app. An animated pixel **Clawd** 🐾 walks across your menu bar, a ring fills up with your current usage, and the live 5-hour percentage sits right beside it. Click for the full breakdown of both limits. Built with SwiftUI `MenuBarExtra` — **zero external dependencies.**

<!-- Add a screenshot once you have one:
![Claude Usage Tracker in the menu bar](docs/screenshot.png)
-->

> 🌏 Thai user guide: see **[USER_MANUAL.md](USER_MANUAL.md)**.

---

## ✨ Features

- 🐾 **Animated Clawd mascot** — walks faster the harder you're using Claude.
- ⭕ **Usage ring** — fills with your 5-hour usage; **orange** normally, **red** past 80%.
- 📊 **Both limits at a glance** — 5-hour and weekly meters in a click-through panel.
- 🎯 **Exact numbers** — the same figures as *claude.ai → Settings → Usage*, not an estimate.
- 🪶 **Featherweight** — one small binary, no dependencies, no background bloat.
- 🔒 **Private by design** — your token stays on your Mac (a `0600` file, never the Keychain).

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

The usage numbers come from *your* account, so each person connects once:

1. 🖥️ In a terminal, run **`claude setup-token`** *(needs a Claude subscription + Claude Code)*.
2. 📋 Copy the token it prints — it starts with `sk-ant-oat01-…`.
3. 🐾 Click **Clawd** in the menu bar → **Preferences…** → paste into **Token** → **Save & test**.

Your real percentages should appear right away. 🎉

> 🔐 Tokens are per-account — everyone generates their own; you can't share one.

---

## 🧠 How it works

Every refresh fires **one tiny (~1-token) `POST /v1/messages`** call and reads your usage straight from the response headers:

| Header | Meaning |
| --- | --- |
| `anthropic-ratelimit-unified-5h-utilization` | 5-hour usage (`0`–`1`) |
| `anthropic-ratelimit-unified-5h-reset` | when the 5-hour window resets |
| `anthropic-ratelimit-unified-7d-*` | the weekly equivalents |

That's the same data behind *claude.ai → Settings → Usage*. The `user:inference` token from `claude setup-token` is all it needs — **no Keychain, no `user:profile` scope, no browser login.**

> ℹ️ These headers expose only the **5-hour** and **weekly (all-models)** windows. Per-model limits (e.g. a Fable-only weekly) aren't available from this source.

*Technique credit: [Clawdmeter](https://github.com/HermannBjorgvin/Clawdmeter).*

---

## 🖥️ In the menu bar

- 🐾 **Clawd** strolls along — pace scales with your 5-hour usage.
- ⭕ The **ring** shows that same 5-hour usage at a glance.
- 🟠 → 🔴 Everything turns **red at 80%**, so you notice before you hit the wall.
- 🖱️ **Click** to drop down the panel with both the 5-hour and weekly meters.

---

## ⚙️ Preferences

| Setting | What it does |
| --- | --- |
| **Token** | Paste from `claude setup-token`; *Save & test* verifies it live. |
| **Refresh interval** | How often to poll — default **60s** (~1 token each). |
| **Launch at login** | Start with macOS via `SMAppService`. |

Your token lives at `~/Library/Application Support/ClaudeUsageTracker/token` (`0600`). Clear it anytime from Preferences.

---

## 🛠️ Development

```bash
swift build      # 🔨 debug compile
swift run        # ▶️  run unbundled (menu bar item appears; launch-at-login off)
./test.sh        # 🧪 unit tests (wraps `swift test` with CLT fixups)
./build.sh       # 📦 release build → build/Claude Usage Tracker.app
```

**Project layout**

- `Sources/UsageCore/` — the testable data core: fetch + parse rate-limit headers, build snapshots, formatting.
- `Sources/App/` — the SwiftUI app: `MenuBarExtra`, the Clawd mascot + ring drawing, panel, preferences, token file.
- `Tests/UsageCoreTests/` — header-parsing and request-building tests.

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
