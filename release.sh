#!/usr/bin/env bash
set -euo pipefail

SCHEME="Plonk"
PROJECT="Plonk.xcodeproj"
APP_NAME="Plonk"
TEAM_ID="V2CW6Y3N5J"
NOTARY_PROFILE="${PLONK_NOTARY_PROFILE:-plonk-notary}"

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

info() { printf "%s→%s %s\n" "$GREEN" "$NC" "$1"; }
warn() { printf "%s!%s %s\n" "$YELLOW" "$NC" "$1"; }
fail() { printf "%s✗%s %s\n" "$RED" "$NC" "$1" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v xcrun >/dev/null      || fail "xcrun not found"
command -v create-dmg >/dev/null || fail "create-dmg not found — install: brew install create-dmg"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    fail "notarytool keychain profile '$NOTARY_PROFILE' not found.

Set it up once with:
  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\
    --apple-id <your-apple-id> \\
    --team-id $TEAM_ID \\
    --password <app-specific-password>

App-specific passwords: https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

info "Archiving $SCHEME..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS"

[ -d "$ARCHIVE_PATH" ] || fail "Archive failed"

info "Exporting signed .app..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "ExportOptions.plist"

[ -d "$APP_PATH" ] || fail "Export failed — no .app at $APP_PATH"

info "Zipping for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

info "Submitting to Apple notary service (this can take a few minutes)..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

info "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

info "Building DMG..."
create-dmg \
    --volname "$APP_NAME" \
    --window-size 500 300 \
    --icon-size 96 \
    --icon "$APP_NAME.app" 125 150 \
    --app-drop-link 375 150 \
    "$DMG_PATH" \
    "$APP_PATH"

info "Done. Ship it: $DMG_PATH"
