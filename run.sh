#!/bin/bash
# One command to run it: build the release app, then launch it into the menu bar.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
open "build/Claude Usage Tracker.app"

echo
echo "✅ Claude Usage Tracker is running — look for Clawd in your menu bar (top-right)."
echo "   First run? Click it → Preferences… → Add account… → paste your 'claude setup-token' → Add & test."
