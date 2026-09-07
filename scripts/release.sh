#!/usr/bin/env bash
#
# Build, sign, notarize and staple Konpo for distribution outside the App Store.
#
# Why this exists: the project signs ad hoc (CODE_SIGN_IDENTITY = "-"), which
# makes ENABLE_HARDENED_RUNTIME inert — the build log says as much:
#
#     note: Disabling hardened runtime with ad-hoc codesigning.
#
# An ad-hoc signed app that a user downloads is quarantined by Gatekeeper and
# refuses to open with "Konpo is damaged and can't be opened". Notarization is
# what removes that, and it requires a real Developer ID certificate.
#
# Usage:
#   export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   export TEAM_ID="TEAMID"
#   export NOTARY_PROFILE="konpo-notary"
#   ./scripts/release.sh
#
# One-time setup of the notary credentials (stores an app-specific password in
# the keychain so it never appears in this script or your shell history):
#
#   xcrun notarytool store-credentials "konpo-notary" \
#       --apple-id "you@example.com" \
#       --team-id "TEAMID" \
#       --password "app-specific-password"
#
# Create the app-specific password at appleid.apple.com; it is NOT your Apple
# ID password.

set -euo pipefail

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your \"Developer ID Application: ...\" identity}"
: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID}"
: "${NOTARY_PROFILE:=konpo-notary}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/Konpo.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/Konpo.app"
DMG="$BUILD/Konpo.dmg"

echo "==> Cleaning $BUILD"
rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "==> Archiving"
xcodebuild archive \
    -project "$ROOT/Konpo.xcodeproj" \
    -scheme Konpo \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"

echo "==> Exporting"
cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist"

echo "==> Verifying the signature before notarizing"
# --strict catches problems that would otherwise only show up as a notarization
# rejection several minutes later.
codesign --verify --deep --strict --verbose=2 "$APP"
# Confirms the hardened runtime actually took effect this time.
codesign --display --verbose=4 "$APP" 2>&1 | grep -q "runtime" \
    || { echo "ERROR: hardened runtime flag missing from the signature"; exit 1; }

echo "==> Building DMG"
# Notarizing the DMG (rather than a zip) means the thing users download is the
# stapled artifact, so it verifies even offline.
hdiutil create -volname "Konpo" -srcfolder "$APP" -ov -format UDZO "$DMG"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"

echo "==> Submitting for notarization (this usually takes a few minutes)"
xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Final Gatekeeper check"
# What a user's machine will actually do with the downloaded app.
spctl --assess --type execute --verbose=4 "$APP"

echo
echo "Done: $DMG"
