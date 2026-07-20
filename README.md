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
- ⭕ **Usage ring** — fills with your 5-hour usage; **orange** normally, **red** past 80% (the % text turns red too).
- 👥 **Multiple accounts** — track up to **10** Claude accounts side by side; show or hide each one on the menu bar.
- 🔥 **Pace signal** — whether each window is burning **fast**, **steady**, or **slow**: monochrome flame / equals / tortoise glyphs right in the menu bar (they adapt to light/dark like system items), 🔥/😎/🐢 emoji with an estimated time-to-limit in the panel.
- 🎛️ **Composable menu bar, per window** — each of the 5-hour and weekly windows gets two checkbox sets: **Elements** (Ring · Percent · Glyph) picks what renders, **Visible when pace is** (🐢 = 🔥) hides an account's whole group while its pace is an unchecked state — e.g. 🔥-only turns the bar into an attention-only display that stays silent until something burns.
- 🧷 **Never-empty item** — hide everything and the mascot steps in; hide the mascot too and the ring returns. The menu bar item always stays clickable.
- 🌫️ **Staleness dimming** — if an account hasn't refreshed successfully for ~10 minutes, its whole segment fades so you know the numbers are old.
- 📊 **Both limits at a glance** — 5-hour and weekly meters per account in a click-through panel; optional weekly ring on the bar.
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

Per shown account: `name  ring NN% <pace>  W:MM% <pace>` — every piece optional (see Preferences).

- 🐾 **Clawd** strolls along — pace scales with your usage.
- ⭕ The **ring** and first **%** are the 5-hour window; **`W:`** is the weekly window.
- 🔥 The **pace glyph** (flame / equals / tortoise, monochrome) shows each window's burn pace vs an even burn; hidden while a window is too fresh to judge.
- 🟠 → 🔴 Ring and % turn **red at 80%**, so you notice before you hit the wall.
- 🌫️ A segment **fades** when its data is stale (no successful refresh in ~10 min).
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

**Menu bar**

| Setting | What it does |
| --- | --- |
| **Clawd mascot** | Show or hide Clawd (he still appears if everything else is hidden — the item never goes empty). |
| **Account names** | Label each account's segment with its name. |

**Session (5-hour) on menu bar** · **Weekly (W:) on menu bar** — one section each, with two rows:

| Row | Checkboxes | What it does |
| --- | --- | --- |
| **Elements** | Ring · Percent · Glyph | Which pieces of that window's group render. |
| **Visible when pace is** | 🐢 Slow · = Steady · 🔥 Fast | Filters the **whole group** by current pace — while a window's pace is an unchecked state, that account's group is hidden until the pace changes (unknown pace always shows). |

**Behavior**

| Setting | What it does |
| --- | --- |
| **Refresh every … seconds** | How often to poll — default **60s** (~1 token per account each refresh). |
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

- `Sources/UsageCore/` — the testable data core: fetch + parse rate-limit headers, build snapshots, compute pace, formatting, plus the menu bar composition model (`MenuBarConfig`, `PaceSelection`, never-empty guards, staleness rule, legacy-pref migration).
- `Sources/App/` — the SwiftUI app: `MenuBarExtra`, Clawd mascot + token-stream segment drawing, panel, preferences, per-account store.
- `Tests/UsageCoreTests/` — header-parsing, snapshot, pace, menu-bar-layout, and migration tests (40 tests).

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
