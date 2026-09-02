#!/bin/bash
# Builds carbs and packages it as Carbs.app (menu-bar-only, no dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="Carbs.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/carbs" "$APP/Contents/MacOS/carbs"

cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>carbs</string>
    <key>CFBundleDisplayName</key><string>carbs</string>
    <key>CFBundleIdentifier</key><string>app.carbs.menubar</string>
    <key>CFBundleExecutable</key><string>carbs</string>
    <key>CFBundleVersion</key><string>0.2.0</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocationWhenInUseUsageDescription</key><string>carbs uses your location once to pick the right electricity grid zone for carbon intensity. Location is never stored or shared.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP — run with: open $APP"
