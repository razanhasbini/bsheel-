#!/bin/bash
# Build, sign and upload the iOS app to App Store Connect.
#
#   scripts/ios_release.sh --version 2.0.2 --build 74
#   scripts/ios_release.sh --version 2.0.2 --build 74 --no-upload   # signs for real, skips upload
#
# Shared by both publish branches, so a TestFlight build and a store build are byte-for-byte
# the same process — the only difference is what happens to the build afterwards.
#
# Signing is automatic and provisioning is created on demand through the API key, so no .p12,
# no .mobileprovision and no .p8 is ever stored in this repository.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_DIR="apps/mobile_app"
BUNDLE_ID="com.questapp.mobileApp"
TEAM_ID="JMDKX9TYX6"
UPLOAD=1
VERSION=""
BUILD=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version)   VERSION="$2"; shift 2 ;;
    --build)     BUILD="$2";   shift 2 ;;
    --no-upload) UPLOAD=0;     shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\033[31merror: %s\033[0m\n" "$1" >&2; exit 1; }

[ -n "$VERSION" ] || fail "--version is required"
[ -n "$BUILD" ]   || fail "--build is required"

mkdir -p build
ARCHIVE="$ROOT/build/Runner.xcarchive"
EXPORT_DIR="$ROOT/build/ipa"

# Credentials come from the environment in CI, and from the Keychain on a Mac. Without this
# fallback a local release builds for fifteen minutes, signs, exports, verifies — and then
# stops at the upload with "ASC_KEY_ID is not set", having done all the expensive work.
if [ -z "${ASC_KEY_ID:-}" ] && security find-generic-password -s BSHEEL-ASC -w >/dev/null 2>&1; then
  eval "$(security find-generic-password -s BSHEEL-ASC -w | python3 -c '
import json, shlex, sys
c = json.load(sys.stdin)
for k, v in (("ASC_KEY_ID", c["keyId"]), ("ASC_ISSUER_ID", c["issuerId"])):
    print(f"export {k}={shlex.quote(v)}")
')"
  mkdir -p ~/private_keys
  KEYFILE="$HOME/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  if [ ! -f "$KEYFILE" ]; then
    security find-generic-password -s BSHEEL-ASC -w \
      | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["p8"])' > "$KEYFILE"
    chmod 600 "$KEYFILE"
  fi
  echo "using the App Store Connect key from the Keychain (BSHEEL-ASC)"
fi

step "Preflight"
# Read the whole output before parsing it. `xcodebuild -version | head -1` closes the pipe on
# the first line, xcodebuild dies of SIGPIPE with an uncaught NSException, and the script exits
# 134 having printed a stack trace instead of a version.
XCODE_VERSION_OUTPUT=$(xcodebuild -version 2>/dev/null || true)
XCODE_VERSION=$(printf '%s\n' "$XCODE_VERSION_OUTPUT" | awk 'NR==1 {print $2}')
MAJOR=${XCODE_VERSION%%.*}
[ -n "$MAJOR" ] || fail "could not read the Xcode version: $XCODE_VERSION_OUTPUT"
[ "$MAJOR" -ge 15 ] || fail "Xcode 15+ required, found $XCODE_VERSION"
echo "Xcode $XCODE_VERSION  team $TEAM_ID"
echo "Shipping $VERSION ($BUILD)"

step "Flutter build"
# --no-codesign because xcodebuild below does the signing, with provisioning it can create.
# This step is what produces Generated.xcconfig and runs pod install.
#
# The dart-defines are NOT optional. They are compiled in, and without them the app builds and
# signs perfectly and is dead on launch: no backend URL, no anon key, no Google client ids.
# Nothing downstream catches it — the .ipa is valid, the upload succeeds, and testers get an
# app that cannot reach the API. They live in one JSON file so this script and CLAUDE.md's
# canonical command cannot drift apart.
#
# --obfuscate is required for release/store builds by the M17 audit (2026-05-17).
DEFINES="$ROOT/$APP_DIR/dart_defines.release.json"
[ -f "$DEFINES" ] || fail "missing $DEFINES — the app would build but could not reach the API"

( cd "$APP_DIR" && flutter build ios --release --no-codesign \
    --build-name="$VERSION" --build-number="$BUILD" \
    --dart-define-from-file="$DEFINES" \
    --obfuscate --split-debug-info=build/app/outputs/app-symbols/release \
  ) 2>&1 | tee build/flutter.log | tail -15

# The symbol map is the only way to read a crash report from an obfuscated build. Keep it
# beside the logs; never ship it inside the app.
if [ -d "$APP_DIR/build/app/outputs/app-symbols/release" ]; then
  mkdir -p build/symbols
  cp -R "$APP_DIR/build/app/outputs/app-symbols/release/." build/symbols/ 2>/dev/null || true
  echo "debug symbols kept in build/symbols — needed to deobfuscate crashes for $VERSION+$BUILD"
fi

step "Archive"
set -o pipefail
# NOTE ON SIGNING (2026-08-30)
#
# This archives with the DEVELOPMENT identity that Flutter's Runner project hardcodes
# (CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"); the export step below re-signs the
# .ipa for distribution, which is what actually reaches Apple. That works.
#
# It has one cost: a fresh CI runner holds no private key, so `-allowProvisioningUpdates`
# creates a NEW development certificate on every run. Twelve runs took the account to Apple's
# cap and every build then failed with "Choose a certificate to revoke".
#
# Forcing `CODE_SIGN_IDENTITY = Apple Distribution` through -xcconfig fixes the leak but
# applies to every CocoaPods target too, and those are automatically signed for development —
# so the archive fails with "AppAuth has conflicting provisioning settings" for each pod.
#
# The durable fix is to stop creating certificates in CI at all: import one distribution
# certificate (.p12) and its provisioning profiles from secrets, and sign manually. See
# docs/PUBLISHING.md.
xcodebuild archive \
  -workspace "$APP_DIR/ios/Runner.xcworkspace" \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  ${ASC_KEY_ID:+-authenticationKeyPath "$HOME/private_keys/AuthKey_${ASC_KEY_ID}.p8"} \
  ${ASC_KEY_ID:+-authenticationKeyID "$ASC_KEY_ID"} \
  ${ASC_ISSUER_ID:+-authenticationKeyIssuerID "$ASC_ISSUER_ID"} \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  2>&1 | tee build/archive.log | grep -E "error:|Signing Identity|\*\* ARCHIVE" || true
grep -q "\*\* ARCHIVE SUCCEEDED \*\*" build/archive.log || fail "archive failed — see build/archive.log"

step "Export the .ipa"
rm -rf "$EXPORT_DIR"
# Written at build time and deleted afterwards: ExportOptions.plist carries the Team ID.
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
plutil -lint build/ExportOptions.plist >/dev/null

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates \
  ${ASC_KEY_ID:+-authenticationKeyPath "$HOME/private_keys/AuthKey_${ASC_KEY_ID}.p8"} \
  ${ASC_KEY_ID:+-authenticationKeyID "$ASC_KEY_ID"} \
  ${ASC_ISSUER_ID:+-authenticationKeyIssuerID "$ASC_ISSUER_ID"} \
  2>&1 | tee build/export.log | grep -E "error:|EXPORT SUCCEEDED" || true

IPA=$(ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1) || true
if [ -z "${IPA:-}" ]; then
  # This failure has one common cause and the raw message names neither it nor the fix.
  if grep -q "Cloud signing permission error" build/export.log 2>/dev/null; then
    fail "the App Store Connect API key cannot create a distribution certificate. Its role must be Admin, not App Manager. See docs/PUBLISHING.md."
  fi
  fail "no .ipa was produced — see build/export.log"
fi

step "Verify before spending an upload"
# Resolve the exact path first. `unzip -p "$IPA" 'Payload/*.app/Info.plist'` looks precise but
# unzip's glob matches `/` too, so it also pulls the Info.plist of every embedded framework and
# app extension and concatenates them — producing a file plutil cannot read, and a run that
# fails claiming the app icon is missing when the icon is fine.
APP_PLIST=$(unzip -Z1 "$IPA" | grep -E '^Payload/[^/]+\.app/Info\.plist$' | head -1)
[ -n "$APP_PLIST" ] || fail "could not find the app's Info.plist inside $IPA"
unzip -p "$IPA" "$APP_PLIST" > build/built-info.plist
plutil -lint build/built-info.plist >/dev/null || fail "the extracted Info.plist is not a valid plist"
BID=$(plutil -extract CFBundleIdentifier raw build/built-info.plist 2>/dev/null || echo "")
VER=$(plutil -extract CFBundleShortVersionString raw build/built-info.plist 2>/dev/null || echo "")
NUM=$(plutil -extract CFBundleVersion raw build/built-info.plist 2>/dev/null || echo "")
# An app may declare its icon at the top level (what actool injects) OR nested under
# CFBundleIcons -> CFBundlePrimaryIcon (the older form). BSHEEL uses the nested form, which is
# why checking only the top level reported a missing icon on a build whose icon is fine — and
# on an app that is already live on the App Store. Accept either.
ICON=$(plutil -extract CFBundleIconName raw build/built-info.plist 2>/dev/null || echo "")
if [ -z "$ICON" ]; then
  ICON=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName" \
           build/built-info.plist 2>/dev/null || echo "")
fi
if [ -z "$ICON" ]; then
  # A build with no icon in either place passes transport and then fails Apple's processing an
  # hour later, silently, by email. Worth stopping for.
  fail "no app icon is declared in the built Info.plist (neither CFBundleIconName nor CFBundleIcons) — App Store Connect would reject this"
fi
[ "$BID" = "$BUNDLE_ID" ] || fail "built '$BID', expected '$BUNDLE_ID'"
[ "$VER" = "$VERSION" ] || fail "built version '$VER', expected '$VERSION'"
[ "$NUM" = "$BUILD" ] || fail "built number '$NUM', expected '$BUILD'"
echo "bundle=$BID  version=$VER  build=$NUM  icon=${ICON:-<absent>}  size=$(du -h "$IPA" | cut -f1)"

if [ "$UPLOAD" -eq 0 ]; then
  step "Done (--no-upload)"
  echo "Signed build is at $IPA"
  exit 0
fi

step "Upload to App Store Connect"
[ -n "${ASC_KEY_ID:-}" ] || fail "ASC_KEY_ID is not set"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tee build/upload.log | tail -20
grep -q "UPLOAD SUCCEEDED" build/upload.log || fail "upload failed — see build/upload.log"

step "Uploaded $VERSION ($BUILD)"
