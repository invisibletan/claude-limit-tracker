# Claude Usage Tracker

macOS menu bar app showing your Claude **5-hour limit** and **weekly limit** at a glance — live percentage on the icon, full breakdown (burn rate, projections, reset countdowns) on click.

Implements the [design spec artifact](https://claude.ai/code/artifact/7f43aade-aa63-4e89-845e-5b0e1ee07604): native SwiftUI `MenuBarExtra`, no dependencies.

## Build & run

```bash
./build.sh
open "build/Claude Usage Tracker.app"
```

Requires Xcode command line tools (Swift 5.9+, macOS 14+).

## Data sources

The app merges two sources, best-available wins:

| Source | What it gives | Setup |
| --- | --- | --- |
| **Official Anthropic usage API** (`api.anthropic.com/api/oauth/usage`) | The exact 5-hour / weekly percentages and reset times shown at claude.ai → Settings → Usage | Run `claude setup-token` in a terminal, paste the token into Preferences → "Save & test" |
| **Local estimate** (ccusage over `~/.claude` logs) | Cost, tokens, burn rate, projections; percentages measured against caps you set | Works out of the box if [ccusage](https://github.com/ryoppippi/ccusage) is installed |

With a token configured, percentages/resets come from the official API and cost detail/burn rate from ccusage. Without one, everything is estimated locally — fully offline.

### Why paste a token instead of auto-detecting it?

On macOS, Claude Code stores its OAuth credentials in the Keychain. This app deliberately never touches the Keychain (corporate EDR policy). The token you paste is kept in `~/Library/Application Support/ClaudeUsageTracker/token` with `0600` permissions; clear it anytime from Preferences.

## Preferences

- **OAuth token** — enables official mode (save & test inline)
- **Estimate caps** — 5-hour and weekly USD ceilings used when no token is set (defaults: $35 / $500 — tune to where your plan actually cuts you off)
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
