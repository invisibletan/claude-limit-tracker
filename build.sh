#!/bin/bash
# Builds "Claude Usage Tracker.app" into ./build.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Claude Usage Tracker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/ClaudeUsageTracker "$APP/Contents/MacOS/ClaudeUsageTracker"

# App icon: generate AppIcon.icns from the shared ClawdSprite (same mascot as the
# menu bar) so Finder / Notification Center / System Settings show a real icon.
swiftc -O make-appicon.swift Sources/App/ClawdSprite.swift -o .build/appicon-gen
.build/appicon-gen "$APP/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.1.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
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
