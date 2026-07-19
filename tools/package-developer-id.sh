#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ROOT="${SOURCE_ROOT:-$REPO_ROOT}"

APP_NAME="${APP_NAME:-MousePortal}"
BUNDLE_ID="${BUNDLE_ID:-uy.aix.MousePortal}"
CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist/developer-id}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$REPO_ROOT/Distribution/DeveloperID.entitlements}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mouseportal-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
ARCHS="${ARCHS:-arm64 x86_64}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.developer-id.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

if [[ -z "$APP_SIGN_IDENTITY" ]]; then
  echo "APP_SIGN_IDENTITY is required, for example: Developer ID Application: Name (TEAMID)" >&2
  exit 1
fi

cd "$SOURCE_ROOT"

VERSION="$(awk -F'"' '/static let current/ { print $2; exit }' "$SOURCE_ROOT/MousePortal/AppVersion.swift")"
BUILD_NUMBER="$(awk -F'"' '/static let build/ { print $2; exit }' "$SOURCE_ROOT/MousePortal/AppVersion.swift")"

if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "Could not read version from $SOURCE_ROOT/MousePortal/AppVersion.swift" >&2
  exit 1
fi

read -r -a BUILD_ARCHS <<< "$ARCHS"
if [[ "${#BUILD_ARCHS[@]}" -eq 0 ]]; then
  echo "ARCHS must contain at least one architecture" >&2
  exit 1
fi

BUILD_ARGS=(-c "$CONFIGURATION")
for arch in "${BUILD_ARCHS[@]}"; do
  BUILD_ARGS+=(--arch "$arch")
done

swift build "${BUILD_ARGS[@]}"
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

APP_PATH="$STAGING_DIR/$APP_NAME.app"
DMG_ROOT="$STAGING_DIR/dmg-root"
RW_DMG="$STAGING_DIR/$APP_NAME-$VERSION-rw.dmg"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
RESOURCE_BUNDLE="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"
ICON_SOURCE="$SOURCE_ROOT/MousePortal/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

install -m 755 "$BIN_PATH/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
BINARY_ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
for arch in "${BUILD_ARCHS[@]}"; do
  if [[ " $BINARY_ARCHS " != *" $arch "* ]]; then
    echo "Built binary is missing required architecture '$arch': $BINARY_ARCHS" >&2
    exit 1
  fi
done
echo "Built $APP_NAME for architectures: $BINARY_ARCHS"

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi

cp -R "$RESOURCE_BUNDLE" "$APP_PATH/Contents/Resources/"

RESOURCE_BUNDLE_DEST="$APP_PATH/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
RESOURCE_BUNDLE_PLIST="$RESOURCE_BUNDLE_DEST/Info.plist"
if [[ -f "$RESOURCE_BUNDLE_PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.resources" "$RESOURCE_BUNDLE_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID.resources" "$RESOURCE_BUNDLE_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $(basename "$RESOURCE_BUNDLE" .bundle)" "$RESOURCE_BUNDLE_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleName string $(basename "$RESOURCE_BUNDLE" .bundle)" "$RESOURCE_BUNDLE_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundlePackageType BNDL" "$RESOURCE_BUNDLE_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string BNDL" "$RESOURCE_BUNDLE_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$RESOURCE_BUNDLE_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$RESOURCE_BUNDLE_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$RESOURCE_BUNDLE_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$RESOURCE_BUNDLE_PLIST"
  plutil -lint "$RESOURCE_BUNDLE_PLIST" >/dev/null
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHumanReadableCopyright</key>
  <string>© 2026 AiX.uy</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
</dict>
</plist>
PLIST

plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null

if [[ -f "$ICON_SOURCE" ]]; then
  ICONSET="$STAGING_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET"

  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

xattr -cr "$APP_PATH"

codesign --force \
  --timestamp \
  --options runtime \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$APP_SIGN_IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$DMG_ROOT"
ditto "$APP_PATH" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_ROOT" \
  -fs HFS+ \
  -format UDRW \
  "$RW_DMG" >/dev/null

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

codesign --force --timestamp --sign "$APP_SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "Created:"
echo "  $DMG_PATH"
echo "  $DMG_PATH.sha256"
