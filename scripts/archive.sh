#!/usr/bin/env bash
#
# One command from a clean checkout to an .ipa ready for App Store Connect.
#
#   scripts/archive.sh              archive and export
#   scripts/archive.sh --upload     …and send it to App Store Connect
#   BUILD=1234 scripts/archive.sh   pin the build number instead of stamping one
#
# Ported from ~/Projects/furlough/scripts/archive.sh, without the Screen Time and release-notes
# checks that only Furlough needs.
#
# Uploading needs an App Store Connect API key (App Store Connect > Users and Access >
# Integrations). Export ASC_KEY_ID and ASC_ISSUER_ID, and put the .p8 where altool looks:
# ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8. The key Furlough uses works here too,
# since both apps are on the same team. Keep the .p8 out of this repo.
#
# Signing values come from Config/Local.xcconfig (git-ignored).

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

LOCAL="$ROOT/Config/Local.xcconfig"
[[ -f "$LOCAL" ]] || { echo "No $LOCAL. Copy Config/Local.xcconfig.example and fill it in." >&2; exit 1; }
TEAM="$(awk -F' *= *' '/^DEVELOPMENT_TEAM/{print $2}' "$LOCAL")"
[[ -n "$TEAM" && "$TEAM" != "YOURTEAMID" ]] || { echo "DEVELOPMENT_TEAM is not set in $LOCAL" >&2; exit 1; }

# App Store Connect refuses a second upload that reuses a build number under the same version.
BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"
ARCHIVE="$ROOT/build/Kessik-$BUILD.xcarchive"
EXPORT="$ROOT/build/export"

echo "==> Regenerating the project"
xcodegen generate --spec project.yml --project .

echo "==> Archiving  (version $(grep -m1 'MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '\"'), build $BUILD)"
# -skipPackagePluginValidation is required. Without it SwiftTerm's build plugin fails with
# "Validate plug-in" and no other error (same as kessik phone).
xcodebuild -project SSHTerm.xcodeproj -scheme SSHTerm -configuration Release \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -skipPackagePluginValidation -skipMacroValidation \
  -derivedDataPath build \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive

echo "==> Checking the archive"
APP_DIR="$ARCHIVE/Products/Applications/SSHTerm.app"
[[ -d "$APP_DIR" ]] || { echo "REFUSING TO SHIP: no app at $APP_DIR" >&2; exit 1; }

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Info.plist")"
if [[ "$BUNDLE_ID" == com.example.* ]]; then
    echo "REFUSING TO SHIP: the bundle ID is $BUNDLE_ID, the placeholder from Base.xcconfig." >&2
    echo "Set SSHTERM_BUNDLE_ID in Config/Local.xcconfig." >&2
    exit 1
fi
echo "    bundle ID $BUNDLE_ID"

# App Store Connect rejects an upload whose app uses a required-reason API with no manifest.
if [[ ! -f "$APP_DIR/PrivacyInfo.xcprivacy" ]]; then
    echo "REFUSING TO SHIP: PrivacyInfo.xcprivacy is not in the app bundle." >&2
    echo "It lives at SSHTerm/PrivacyInfo.xcprivacy; check that xcodegen copied it as a resource." >&2
    exit 1
fi
echo "    privacy manifest present"

echo "==> Exporting"
rm -rf "$EXPORT"
OPTIONS="$ROOT/build/ExportOptions.plist"
cp scripts/ExportOptions.plist "$OPTIONS"
plutil -replace teamID -string "$TEAM" "$OPTIONS"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$EXPORT" -allowProvisioningUpdates

IPA="$(ls "$EXPORT"/*.ipa | head -1)"
echo "==> Built $IPA"

if [[ "${1:-}" == "--upload" ]]; then
    : "${ASC_KEY_ID:?set ASC_KEY_ID (see the header of this script)}"
    : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the header of this script)}"
    echo "==> Uploading to App Store Connect"
    xcrun altool --upload-app -f "$IPA" -t ios \
      --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    echo "==> Uploaded build $BUILD. It appears in TestFlight once processing finishes."
else
    echo "    Upload it with:  scripts/archive.sh --upload"
fi
