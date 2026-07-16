# Claude Usage Tracker

macOS menu bar app showing your Claude **5-hour limit** and **weekly limit** at a glance — live percentage on the icon, full breakdown (burn rate, projections, reset countdowns) on click.

Implements the [design spec artifact](https://claude.ai/code/artifact/7f43aade-aa63-4e89-845e-5b0e1ee07604): native SwiftUI `MenuBarExtra`, no dependencies.

## Build & run

```bash
./build.sh
open "build/Claude Usage Tracker.app"
```

Requires Xcode command line tools (Swift 5.9+, macOS 14+).

## How it works

The app reads your local usage with [ccusage](https://github.com/ryoppippi/ccusage) (over the `~/.claude` logs Claude already writes) and shows it as a share of caps you set — with live cost, burn rate, projections, and reset countdowns. Fully offline, no credentials.

### Why an estimate, not the exact numbers?

The precise figures on claude.ai → Settings → Usage come from an Anthropic account API that is gated to Claude Code and claude.ai only — third-party apps can't read it. (`claude setup-token` yields a `user:inference`-scoped token that the usage endpoint rejects with 403; the properly-scoped token lives in the Keychain, which this app deliberately never touches per corporate EDR policy.) So the tracker estimates: it divides ccusage's cost by a cap you calibrate.

**Calibrate once:** open Preferences and set each cap so the reading roughly matches your real usage page (defaults target a Max 20× plan: 5-hour $35, weekly $9,000). For the exact numbers any time, use **Open claude.ai usage page** in the menu — it opens Settings → Usage in your browser, where the figures are authoritative.

## Preferences

- **Estimate caps** — 5-hour and weekly USD ceilings the percentages are measured against (defaults $35 / $9,000; tune to match your usage page)
- **Refresh interval** — default 30 s
- **ccusage path** — auto-detected (Homebrew, bun, npm); override if installed elsewhere
- **Launch at login** — via `SMAppService`

## States

| Color | Meaning |
| --- | --- |
| green | healthy — under 60% |
| amber | watch — 60–85% |
| red | critical — over 85% |

The menu bar ring shows the 5-hour percentage; its color tracks the worse of the two limits.

## Development

```bash
swift build          # compile
./test.sh            # parsing/formatting/merge unit tests (wraps swift test with CLT fixups)
swift run            # run unbundled (menu bar item appears; launch-at-login disabled)
```
