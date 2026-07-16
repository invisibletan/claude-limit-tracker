# Claude Usage Tracker

macOS menu bar app showing your Claude **5-hour limit** and **weekly limit** at a glance — an animated Clawd mascot, a usage ring, and the live percentage in the menu bar; the full breakdown on click. Native SwiftUI `MenuBarExtra`, no dependencies.

## Build & run

```bash
./build.sh
open "build/Claude Usage Tracker.app"
```

Requires Xcode command line tools (Swift 5.9+, macOS 14+).

## First-time setup

The exact numbers come from your own account, so each person connects once:

1. In a terminal: `claude setup-token` (needs a Claude subscription + Claude Code)
2. Copy the token it prints (starts with `sk-ant-oat01-`)
3. Menu bar → **Preferences…** → paste into **Token** → **Save & test**

## How it works

Each refresh makes one tiny (1-token) `POST /v1/messages` call and reads your usage straight from the `anthropic-ratelimit-unified-*` response headers — the same 5-hour and weekly numbers as claude.ai → Settings → Usage. The `user:inference` token from `claude setup-token` is all it needs — no Keychain, no `user:profile`, no browser login. The token is stored in `~/Library/Application Support/ClaudeUsageTracker/token` with `0600` permissions; clear it anytime from Preferences.

Note: the rate-limit headers expose only the 5-hour and weekly (all-models) windows — per-model limits (e.g. a Fable-only weekly) are not available from this source.

## Menu bar

- **Clawd** walks faster the harder you're using Claude.
- The **ring** fills with your 5-hour usage: orange normally, red past 80%.
- The panel meters use the same orange/red scheme.

## Preferences

- **Token** — paste from `claude setup-token` (Save & test shows your current percentages)
- **Refresh interval** — default 60 s (each refresh spends ~1 token)
- **Launch at login** — via `SMAppService`

## Development

```bash
swift build          # compile
./test.sh            # unit tests (wraps swift test with CLT fixups)
swift run            # run unbundled (menu bar item appears; launch-at-login disabled)
```
