#!/usr/bin/env bash
set -euo pipefail

# Build a native-architecture .app for this Mac without Developer ID credentials.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${1:-$REPO_ROOT/dist/local}"
APP_NAME="MousePortal"
BUNDLE_ID="uy.aix.MousePortal"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"

if [[ -e "$APP_PATH" ]]; then
  echo "Already exists: $APP_PATH" >&2
  echo "Pass a different output directory to keep the existing app." >&2
  exit 1
fi

cd "$REPO_ROOT"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"
RESOURCE_BUNDLE="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"
VERSION="$(awk -F'"' '/static let current/ { print $2; exit }' MousePortal/AppVersion.swift)"
BUILD_NUMBER="$(awk -F'"' '/static let build/ { print $2; exit }' MousePortal/AppVersion.swift)"

if [[ ! -d "$RESOURCE_BUNDLE" || -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "Missing resource bundle or app version." >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MousePortal.local.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/$APP_NAME.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
install -m 755 "$BIN_PATH/$APP_NAME" "$STAGED_APP/Contents/MacOS/$APP_NAME"
ditto "$RESOURCE_BUNDLE" "$STAGED_APP/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"

PLIST="$STAGED_APP/Contents/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleDevelopmentRegion -string en "$PLIST"
plutil -insert CFBundleDisplayName -string "$APP_NAME" "$PLIST"
plutil -insert CFBundleExecutable -string "$APP_NAME" "$PLIST"
plutil -insert CFBundleIconFile -string AppIcon "$PLIST"
plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$PLIST"
plutil -insert CFBundleName -string "$APP_NAME" "$PLIST"
plutil -insert CFBundlePackageType -string APPL "$PLIST"
plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
plutil -insert LSMinimumSystemVersion -string 13.0 "$PLIST"
plutil -insert LSApplicationCategoryType -string public.app-category.utilities "$PLIST"
plutil -insert NSHighResolutionCapable -bool YES "$PLIST"
plutil -insert NSSupportsAutomaticGraphicsSwitching -bool YES "$PLIST"
plutil -insert NSHumanReadableCopyright -string '© 2026 AiX.uy' "$PLIST"
plutil -insert MousePortalSourceRevision -string "$(git rev-parse HEAD)" "$PLIST"
plutil -lint "$PLIST"

ICON_SOURCE="$REPO_ROOT/MousePortal/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"
ICONSET="$STAGING_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signing is for local use; no certificate or notarization upload is used.
codesign --force --sign - --options runtime "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
mkdir -p "$OUTPUT_DIR"
ditto "$STAGED_APP" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Created: $APP_PATH"
echo "Move the app to Applications before granting Accessibility permission."
