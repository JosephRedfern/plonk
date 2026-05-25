#!/usr/bin/env bash
set -euo pipefail

SCHEME="Plonk"
PROJECT="Plonk.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
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

if [ $# -ne 1 ]; then
    printf "Usage: %s <version>   e.g. %s 1.2.0\n" "$0" "$0" >&2
    exit 1
fi

VERSION="$1"
TAG="v$VERSION"
DMG_VERSIONED="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    fail "Version must look like 1.2 or 1.2.3 (got '$VERSION')"
fi

command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v xcrun >/dev/null      || fail "xcrun not found"
command -v create-dmg >/dev/null || fail "create-dmg not found — install: brew install create-dmg"
command -v gh >/dev/null         || fail "gh not found — install: brew install gh"
command -v git >/dev/null        || fail "git not found"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    fail "notarytool keychain profile '$NOTARY_PROFILE' not found.

Set it up once with:
  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\
    --apple-id <your-apple-id> \\
    --team-id $TEAM_ID \\
    --password <app-specific-password>

App-specific passwords: https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
fi

gh auth status >/dev/null 2>&1 || fail "gh is not authenticated — run: gh auth login"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || fail "Not on main (on '$BRANCH'). Switch to main before releasing."

[ -z "$(git status --porcelain)" ] || fail "Working tree is dirty — commit or stash first."

if git rev-parse "$TAG" >/dev/null 2>&1; then
    fail "Tag $TAG already exists locally."
fi

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    fail "Tag $TAG already exists on origin."
fi

CURRENT_BUILD="$(awk '/CURRENT_PROJECT_VERSION = / { gsub(";","",$3); print $3; exit }' "$PBXPROJ")"
[ -n "$CURRENT_BUILD" ] || fail "Could not read CURRENT_PROJECT_VERSION from $PBXPROJ"
NEW_BUILD=$((CURRENT_BUILD + 1))

info "Version: $VERSION (build $CURRENT_BUILD → $NEW_BUILD)"

revert_pbxproj() {
    warn "Reverting pbxproj changes."
    git checkout -- "$PBXPROJ" 2>/dev/null || true
}
trap revert_pbxproj ERR

info "Updating MARKETING_VERSION and CURRENT_PROJECT_VERSION in $PBXPROJ..."
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

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
    --volname "$APP_NAME $VERSION" \
    --window-size 500 300 \
    --icon-size 96 \
    --icon "$APP_NAME.app" 125 150 \
    --app-drop-link 375 150 \
    "$DMG_VERSIONED" \
    "$APP_PATH"

trap - ERR

info "Committing version bump and tagging $TAG..."
git add "$PBXPROJ"
git commit -m "Release $TAG"
git tag -a "$TAG" -m "Release $TAG"

info "Pushing to origin..."
git push origin main
git push origin "$TAG"

info "Creating GitHub release..."
gh release create "$TAG" "$DMG_VERSIONED" \
    --title "$TAG" \
    --generate-notes

info "Done. Shipped $TAG: $DMG_VERSIONED"
