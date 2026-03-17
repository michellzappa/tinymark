#!/bin/bash
set -euo pipefail

# TinyMark release script
# Builds, signs, optionally notarizes, and publishes to GitHub Releases.
#
# Usage:
#   ./scripts/release.sh v1.0.0              # build + GitHub release (no notarization)
#   ./scripts/release.sh v1.0.0 --notarize   # build + notarize + GitHub release
#
# Prerequisites:
#   - Xcode command line tools
#   - gh CLI (brew install gh), authenticated
#   - For --notarize: Developer ID Application cert + env vars:
#       NOTARIZE_APPLE_ID    (your Apple ID email)
#       NOTARIZE_TEAM_ID     (your team ID, e.g. 992N457T8D)
#       NOTARIZE_PASSWORD    (app-specific password from appleid.apple.com)

VERSION="${1:?Usage: release.sh <version-tag> [--notarize]}"
NOTARIZE=false
[[ "${2:-}" == "--notarize" ]] && NOTARIZE=true

SIGN_IDENTITY="Developer ID Application: CENTAUR LABS OU (992N457T8D)"
TEAM_ID="992N457T8D"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/xcode"
INSTALL_ROOT="/tmp/tinymark-release"
APP_PATH="$INSTALL_ROOT/Applications/TinyMark.app"
ZIP_PATH="/tmp/TinyMark-${VERSION}.zip"

echo "==> Building TinyMark ${VERSION} (signed with Developer ID)..."
rm -rf "$INSTALL_ROOT"
xcodebuild -project "$PROJECT_DIR/TinyMark.xcodeproj" \
    -scheme TinyMark \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--options=runtime" \
    DSTROOT="$INSTALL_ROOT" \
    install 2>&1 | tail -5

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Build failed — $APP_PATH not found"
    exit 1
fi

echo "==> App built at $APP_PATH"

# Verify code signature
echo "==> Verifying signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "    Signature OK"

# Notarize if requested
if $NOTARIZE; then
    echo "==> Creating zip for notarization..."
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "${NOTARIZE_APPLE_ID:?Set NOTARIZE_APPLE_ID}" \
        --team-id "${NOTARIZE_TEAM_ID:?Set NOTARIZE_TEAM_ID}" \
        --password "${NOTARIZE_PASSWORD:?Set NOTARIZE_PASSWORD}" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"

    # Re-zip with stapled ticket
    rm -f "$ZIP_PATH"
fi

echo "==> Creating distribution zip..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo "    $ZIP_PATH ($SIZE)"

# Create GitHub release
echo "==> Publishing GitHub release ${VERSION}..."
gh release create "$VERSION" "$ZIP_PATH" \
    --title "TinyMark ${VERSION}" \
    --notes "$(cat <<EOF
## TinyMark ${VERSION}

### Installation
Download **TinyMark-${VERSION}.zip**, unzip, and drag to /Applications.
EOF
)" \
    --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"

echo ""
echo "==> Done! Release published:"
gh release view "$VERSION" --json url -q .url

# Cleanup
rm -f "$ZIP_PATH"
rm -rf "$INSTALL_ROOT"
