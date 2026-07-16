# Handoff — Claude Usage Tracker

Session handoff for continuing this project on another machine. Self-contained: everything needed to pick up the work is here.

## What it is

A macOS menu bar app (SwiftUI `MenuBarExtra`, no external dependencies) that shows your Claude **5-hour** and **weekly** usage limits. Menu bar shows an animated pixel "Clawd" mascot + a usage ring + the live 5-hour %. Clicking opens a panel with both meters.

## Current status — DONE and working

- **Token-only, single data source.** Reads exact usage from the `anthropic-ratelimit-unified-*` response headers on a tiny `POST /v1/messages` call (see "Data mechanism"). No ccusage, no estimate mode, no web scraping.
- **Mascot** matched pixel-for-pixel to the reference art (176×120 grid, measured coordinates) — animated walk, speed scales with 5-hour usage.
- **Colors:** ring + panel meters are orange normally, red at ≥80% (no green). Shared in `Palette.swift`.
- Builds clean, **9/9 tests pass**, packaged for distribution (`USER_MANUAL.md`, zip via steps below).

## Repo & how to transfer to another machine

- Location: `~/Desktop/claude-usage-tracker` (git repo, no remote).
- All work is on the **`main`** branch (fast-forward merged from the `worktree-usage-tracker-app` dev worktree). `git log` on `main` has the full history.
- To move it: either `git push` to a new remote (GitHub etc.) and clone on the other machine, **or** zip the folder:
  ```bash
  cd ~/Desktop && zip -r claude-usage-tracker-src.zip claude-usage-tracker \
    -x "claude-usage-tracker/.build/*" -x "claude-usage-tracker/build/*" \
    -x "claude-usage-tracker/.claude/worktrees/*"
  ```
  On the other machine, unzip and `swift build`. (The `.claude/worktrees/` dir is this machine's dev worktree — exclude it; `main` already has all the code.)

## Requirements (other machine)

- macOS 14+ with **Xcode Command Line Tools** (Swift 5.9+). Full Xcode NOT required.
- To see real data at runtime: a Claude subscription + Claude Code CLI (`claude setup-token`).

## Build / test / run

```bash
./build.sh      # release build → build/Claude Usage Tracker.app (ad-hoc signed, LSUIElement)
./test.sh       # unit tests (wraps `swift test`; see note below)
swift build     # debug compile
swift run       # run unbundled (menu bar item appears; Launch-at-login disabled)
open "build/Claude Usage Tracker.app"
```

**test.sh note:** this machine has CLT-only (no full Xcode), so `test.sh` passes extra flags so swift-testing links against `Testing.framework` under CLT and disables the broken Foundation cross-import overlay. On a machine WITH full Xcode, plain `swift test` should work and `test.sh` still falls back to it.

## Data mechanism (the key insight)

The exact Settings→Usage numbers are obtained WITHOUT the Keychain or `user:profile` scope:
- `POST https://api.anthropic.com/v1/messages`, body `{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}` (≈1 token).
- Headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`.
- Read usage from response headers: `anthropic-ratelimit-unified-5h-utilization` (0–1), `-5h-reset` (unix epoch), and the `-7d-` equivalents.
- The `user:inference` token from `claude setup-token` is sufficient. Verified live (HTTP 200).

This is how [Clawdmeter](https://github.com/HermannBjorgvin/Clawdmeter) does it. Implemented in `Sources/UsageCore/RateLimitUsage.swift`.

## Setup flow (per user)

1. `claude setup-token` in a terminal → copy the `sk-ant-oat01-…` token.
2. App → Preferences → paste into **Token** → **Save & test**.
3. Token stored at `~/Library/Application Support/ClaudeUsageTracker/token` (chmod 600, never the Keychain).

Tokens are per-account — each user generates their own; you cannot share one.

## File map

Core (testable, `UsageCore` target):
- `Sources/UsageCore/RateLimitUsage.swift` — `OfficialUsage` struct + `parseHeaders` + `fetchUsage` (the only data source).
- `Sources/UsageCore/SnapshotBuilder.swift` — `build(from: OfficialUsage)` → `UsageSnapshot`.
- `Sources/UsageCore/Models.swift` — `Meter`, `UsageSnapshot`.
- `Sources/UsageCore/Formatting.swift` — `Format.percent/reset/updatedAgo`.

App (`ClaudeUsageTracker` target):
- `Sources/App/ClaudeUsageTrackerApp.swift` — `@main`, `MenuBarExtra` label.
- `Sources/App/UsageStore.swift` — `ObservableObject`: poll loop (refresh) + 15fps animation loop; `PrefKey`.
- `Sources/App/PanelView.swift` — dropdown panel + `MeterView`.
- `Sources/App/PreferencesView.swift` — token + refresh interval + launch-at-login.
- `Sources/App/ClawdIcon.swift` — mascot + ring drawing. **Grid = reference pixels 176×120**; coords are measured directly from the reference sprite (body, two nubs, tall eyes, four legs in two pairs with a wide centre gap). `menuBarImage` composites Clawd + ring into ONE `NSImage` (a `MenuBarExtra` label drops all but the first image, so they must be one image).
- `Sources/App/ClawdView.swift` — static mascot for panel/Preferences headers.
- `Sources/App/TokenStore.swift` — 0600 token file.
- `Sources/App/Palette.swift` — orange/red color source (threshold 80%), used by ring AND panel meters.

Tests: `Tests/UsageCoreTests/{ParsingTests,RateLimitTests}.swift`. Docs: `README.md`, `USER_MANUAL.md` (Thai).

## Decisions / dead ends (so you don't repeat them)

- **Getting exact numbers:** only the rate-limit-header method works. Dead ends tried and abandoned: `/api/oauth/usage` endpoint (403, needs `user:profile` which setup-token lacks); custom OAuth PKCE (claude.ai consent page returns "Invalid request format" — arkose/hcaptcha attestation); embedded WKWebView claude.ai login (Google SSO + claude.ai block embedded views; UA-spoofing to bypass is off-limits). Keychain is banned by this user's corporate policy.
- **Fable / per-model weekly limit is NOT achievable token-only.** The rate-limit headers expose only `5h` + `7d` unified windows (verified twice). The per-model (e.g. Fable) weekly limit appears only on the claude.ai web Settings→Usage page, which needs the `sessionKey` cookie (the abandoned web-session route). If per-model is ever required, that's the only source.
- **Mascot proportions:** don't eyeball — the reference was measured pixel-by-pixel. If given a new reference image, measure it the same way (a small Swift/`sips` script reading the PNG's coral/dark spans) rather than guessing.

## Security note (carry over)

Earlier in the original session a `setup-token` and a claude.ai `sessionKey` cookie were pasted into the chat log (while debugging). They should be **rotated**: log out/in on claude.ai, and generate a fresh `claude setup-token`. Do not reuse those exposed values.

## Possible next steps (not started)

- Notarize/sign for distribution so friends don't need the right-click→Open dance.
- Optional per-model (Fable) support via the claude.ai web session (bigger, needs cookie — weigh against "keep it simple").
- Show a small history/graph of usage over time.
- Handle 429 more gracefully (currently just surfaces the error under the meters).
