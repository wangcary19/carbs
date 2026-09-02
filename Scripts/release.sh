#!/bin/bash
# Builds, signs, notarizes, and packages Carbs.app for public distribution.
#
# Why: apps downloaded from the internet carry the quarantine flag. Gatekeeper
# only lets them open without warnings when they are (a) signed with a
# "Developer ID Application" certificate and (b) notarized by Apple, with the
# notarization ticket stapled to the app. Ad-hoc signing (bundle.sh) always
# triggers the "unidentified developer" warning on other machines.
#
# One-time setup (requires Apple Developer Program, $99/yr):
#   1. Xcode → Settings → Accounts → add your Apple ID → Manage Certificates →
#      create "Developer ID Application" AND "Developer ID Installer" certs.
#   2. Store notarization credentials once:
#        xcrun notarytool store-credentials "carbs-notary" \
#          --apple-id "you@example.com" --team-id "ABCDE12345" \
#          --password "<app-specific password from appleid.apple.com>"
#      (or use --key / --key-id / --issuer with an App Store Connect API key)
#
# Usage:  Scripts/release.sh            # app + zip + pkg (whatever certs exist)
#         NOTARY_PROFILE=other ./Scripts/release.sh
#
# Output: Carbs.app, Carbs.zip (notarized+stapled), carbs-installer.pkg (notarized+stapled)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Carbs.app"
ZIP="Carbs.zip"
PKG="carbs-installer.pkg"
PROFILE="${NOTARY_PROFILE:-carbs-notary}"
BUNDLE_ID="app.carbs.menubar"

# --- locate signing identities -------------------------------------------
ID_APP="${DEVELOPER_ID_APPLICATION:-$(security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
ID_INST="${DEVELOPER_ID_INSTALLER:-$(security find-identity -v 2>/dev/null |
    sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' | head -1)}"

echo "▸ Developer ID Application: ${ID_APP:-NOT FOUND (will ad-hoc sign — Gatekeeper will warn!)}"
echo "▸ Developer ID Installer:   ${ID_INST:-NOT FOUND (pkg will be unsigned)}"

# --- build & bundle --------------------------------------------------------
swift build -c release
rm -rf "$APP" "$ZIP" "$PKG"
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

# --- sign the app ----------------------------------------------------------
if [ -n "$ID_APP" ]; then
    # --options runtime = hardened runtime (required for notarization)
    codesign --force --options runtime --timestamp --sign "$ID_APP" "$APP"
else
    codesign --force --sign - "$APP" >/dev/null
fi
codesign --verify --deep --strict "$APP" && echo "✓ signature valid"

# --- notarize the app (via zip upload) -------------------------------------
notarize() { # $1 = file to submit
    echo "▸ notarizing $1 (profile: $PROFILE)…"
    xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait
}

STAPLED=0
if [ -n "$ID_APP" ] && xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    ditto -c -k --keepParent "$APP" "$ZIP"
    if notarize "$ZIP"; then
        xcrun stapler staple "$APP"
        rm -f "$ZIP"
        ditto -c -k --keepParent "$APP" "$ZIP" # re-zip WITH the stapled ticket
        STAPLED=1
        echo "✓ $ZIP is signed + notarized + stapled — opens clean on any Mac"
    else
        echo "✗ notarization failed — see: xcrun notarytool log <id> --keychain-profile $PROFILE"
        exit 1
    fi
else
    echo "⚠ skipping notarization (no Developer ID or no '$PROFILE' notary profile)"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi

# --- .pkg installer ---------------------------------------------------------
# For a drag-install menu-bar app the zip is enough; the pkg exists for folks
# who prefer an installer wizard (double-click → installs into /Applications).
if [ -n "$ID_INST" ]; then
    pkgbuild --component "$APP" \
        --install-location /Applications \
        --identifier "$BUNDLE_ID" \
        --version 0.2.0 \
        --sign "$ID_INST" \
        "$PKG"
    if [ "$STAPLED" = "1" ]; then
        if notarize "$PKG"; then
            xcrun stapler staple "$PKG"
            echo "✓ $PKG is signed + notarized + stapled"
        else
            echo "✗ pkg notarization failed"
            exit 1
        fi
    else
        echo "⚠ pkg signed but not notarized (no notary profile)"
    fi
else
    echo "⚠ no Developer ID Installer cert — building UNSIGNED pkg (Gatekeeper will warn)"
    pkgbuild --component "$APP" \
        --install-location /Applications \
        --identifier "$BUNDLE_ID" \
        --version 0.2.0 \
        "$PKG"
fi

echo
echo "Done. Distribute ONE of:"
echo "  $ZIP   → users unzip and drag to /Applications (typical for menu-bar apps)"
[ -f "$PKG" ] && echo "  $PKG → double-click installer wizard into /Applications"
echo "Verify Gatekeeper on another machine with:  spctl -a -vv Carbs.app"
