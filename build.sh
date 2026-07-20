#!/bin/bash
# Builds "Claude Usage Tracker.app" into ./build.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Claude Usage Tracker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/ClaudeUsageTracker "$APP/Contents/MacOS/ClaudeUsageTracker"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsageTracker</string>
    <key>CFBundleIdentifier</key>
    <string>dev.nattakit.claude-usage-tracker</string>
    <key>CFBundleName</key>
    <string>Claude Usage Tracker</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage Tracker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS remembers permission grants across rebuilds.
codesign --force --sign - "$APP"

echo "Built: $APP"
echo "Run:   open \"$APP\""
