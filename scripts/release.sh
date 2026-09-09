#!/usr/bin/env bash
#
# Build, sign, notarize and staple Konpo for distribution outside the App Store.
#
# This is NOT fixing a broken release: Konpo 1.0 already shipped correctly
# signed, notarized and stapled (spctl reports "Notarized Developer ID"). It
# just does from the command line what is currently done by hand through
# Xcode's Organizer, so the steps live in version control and can run in CI.
#
# Note that CODE_SIGN_IDENTITY = "-" in the project only affects ordinary local
# builds; the archive/export path below signs with a real Developer ID, which is
# what actually gets distributed.
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

# Identity and team are detected from the keychain rather than hardcoded, so no
# developer name or team id is committed to a public repo. Override either by
# exporting it if the machine has more than one Developer ID.
if [[ -z "${DEVELOPER_ID:-}" ]]; then
    DEVELOPER_ID="$(security find-identity -v -p codesigning \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
[[ -n "$DEVELOPER_ID" ]] || {
    echo "No 'Developer ID Application' certificate found in the keychain." >&2
    echo "Download one from developer.apple.com → Certificates, or export DEVELOPER_ID." >&2
    exit 1
}

# Team id is the parenthesised suffix of the identity name.
if [[ -z "${TEAM_ID:-}" ]]; then
    TEAM_ID="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<<"$DEVELOPER_ID")"
fi
[[ -n "$TEAM_ID" ]] || { echo "Could not derive TEAM_ID from '$DEVELOPER_ID'; export it." >&2; exit 1; }

: "${NOTARY_PROFILE:=konpo-notary}"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<MSG
No notarytool credentials stored under the profile "$NOTARY_PROFILE".

Signing alone does not get past Gatekeeper — the app has to be notarized by
Apple. Store the credentials once (they go into your keychain, not this repo):

  xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
      --apple-id "<the Apple ID for team $TEAM_ID>" \\
      --team-id "$TEAM_ID" \\
      --password "<app-specific password>"

Create the app-specific password at appleid.apple.com → Sign-In and Security →
App-Specific Passwords. It is not your Apple ID password.
MSG
    exit 1
fi

echo "==> Signing as: $DEVELOPER_ID"
echo "==> Team: $TEAM_ID"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
ARCHIVE="$BUILD/Konpo.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/Konpo.app"

# Version comes from the project so the artifact name can never drift from what
# is actually built. dist/ is where the shipped 1.0 lives; build/ stays scratch.
VERSION="$(xcodebuild -project "$ROOT/Konpo.xcodeproj" -target Konpo \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION =/ { print $2; exit }' | tr -d '[:space:]')"
[[ -n "$VERSION" ]] || { echo "Could not read MARKETING_VERSION from the project" >&2; exit 1; }
DMG="$DIST/Konpo-$VERSION.dmg"

echo "==> Building Konpo $VERSION"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST"

if [[ -e "$DMG" && -z "${OVERWRITE:-}" ]]; then
    echo "$DMG already exists. Bump MARKETING_VERSION, or re-run with OVERWRITE=1." >&2
    exit 1
fi

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

# Confirms the hardened runtime actually took effect this time. Captured into a
# variable rather than piped into `grep -q`: under `set -o pipefail`, grep -q
# exits as soon as it matches, which can SIGPIPE codesign and make the pipeline
# report failure on a signature that is perfectly fine. That race made this step
# fail spuriously the first time it ran.
signature_info="$(codesign --display --verbose=4 "$APP" 2>&1)"
case "$signature_info" in
    *"flags=0x10000(runtime)"*) ;;
    *) echo "ERROR: hardened runtime flag missing from the signature" >&2
       echo "$signature_info" >&2
       exit 1 ;;
esac
case "$signature_info" in
    *"Authority=Developer ID Application"*) ;;
    *) echo "ERROR: not signed with a Developer ID Application certificate" >&2
       exit 1 ;;
esac
echo "    hardened runtime: on, Developer ID: present, timestamped"

echo "==> Building DMG"
# Notarizing the DMG (rather than a zip) means the thing users download is the
# stapled artifact, so it verifies even offline.
# hdiutil intermittently fails with "Resource busy" immediately after the
# export, while Spotlight and LaunchServices still have the freshly written
# bundle open. It succeeds on a retry, so don't fail the whole release for it.
for attempt in 1 2 3; do
    if hdiutil create -volname "Konpo" -srcfolder "$APP" -ov -format UDZO "$DMG"; then
        break
    fi
    [[ $attempt -lt 3 ]] || { echo "hdiutil create failed after 3 attempts" >&2; exit 1; }
    echo "    hdiutil busy, retrying in 5s..."
    sleep 5
done

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
