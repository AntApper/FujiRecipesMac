#!/bin/bash
# Packages the SwiftPM build product into a proper macOS .app bundle,
# complete with the Fujifilm X100VI app icon and bundled resources.
#
# This is a credential-free packaging smoke test by default. Supplying
# SIGNING_IDENTITY turns a Release build into a Developer ID signing candidate;
# notarization remains an external release step.
#
# Usage: ./package_app.sh [debug|release] --version VERSION --build-number NUMBER
set -euo pipefail

CONFIG="release"
VERSION=""
BUILD_NUMBER=""
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

usage() {
  cat <<'EOF'
Usage: package_app.sh [debug|release] --version VERSION --build-number NUMBER

Builds a self-contained app bundle. Release builds contain arm64 and x86_64
slices and are structurally validated, but are only suitable for distribution
after signing with SIGNING_IDENTITY and submitting the resulting archive to
Apple for notarization.

Environment:
  SIGNING_IDENTITY   Developer ID Application identity to use for Release
EOF
}

if [[ $# -gt 0 && "$1" != -* ]]; then
  CONFIG="$1"
  shift
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ "$CONFIG" == "debug" || "$CONFIG" == "release" ]] || { usage >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
  { echo "error: --version must be a numeric marketing version (for example 1.2.3)" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] ||
  { echo "error: --build-number must be numeric" >&2; exit 2; }

cd "$(dirname "$0")"

APP_NAME="Fuji Recipes"
BUNDLE_ID="com.ant.fuji-recipes-mac"

if [[ "$CONFIG" == "release" ]]; then
  ../../scripts/verify-helper-resource.sh --require-universal --minimum-macos 14.0
else
  ../../scripts/verify-helper-resource.sh
fi

echo "▶ Building ($CONFIG)…"
if [[ "$CONFIG" == "release" ]]; then
  # A direct-distribution app must not inherit the current host's architecture.
  swift build -c "$CONFIG" --arch arm64 --arch x86_64
  ARCH_DIR="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"
else
  swift build -c "$CONFIG"
  ARCH_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
fi

BIN="$ARCH_DIR/FujiRecipesMac"
RES_BUNDLE="$ARCH_DIR/FujiRecipesMac_FujiRecipesMac.bundle"
[ -x "$BIN" ] || { echo "✗ binary not found: $BIN"; exit 1; }

APP="build/${APP_NAME}.app"
echo "Assembling ${APP} ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/FujiRecipesMac"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# The helper discovers its libusb runtime through @loader_path, so both must
# remain adjacent in the application's top-level Resources directory.
cp Resources/x100vi_helper "$APP/Contents/Resources/x100vi_helper"
cp Resources/libusb-1.0.0.dylib "$APP/Contents/Resources/libusb-1.0.0.dylib"
cp Resources/x100vi_helper.provenance.json "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/ThirdPartyNotices"
cp Resources/ThirdPartyNotices/libusb-COPYING.txt \
  "$APP/Contents/Resources/ThirdPartyNotices/libusb-COPYING.txt"

# Copy the SwiftPM resource bundle so Bundle.module keeps working inside the .app.
[ -d "$RES_BUNDLE" ] && cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>FujiRecipesMac</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
	<key>CFBundleName</key><string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key><string>${APP_NAME}</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "▶ Signing with Developer ID identity…"
  # Sign nested code before sealing the app bundle. The hardened runtime is a
  # notarization prerequisite, not evidence that notarization has happened.
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    "$APP/Contents/Resources/libusb-1.0.0.dylib"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    "$APP/Contents/Resources/x100vi_helper"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
  echo "▶ Ad-hoc code signing (not distributable)…"
  codesign --force --deep --sign - "$APP"
fi

validation_args=(
  --app "$APP"
  --expected-version "$VERSION"
  --expected-build "$BUILD_NUMBER"
  --minimum-macos 14.0
)
if [[ "$CONFIG" == "release" ]]; then
  validation_args+=(--require-universal)
fi
if [[ -n "$SIGNING_IDENTITY" ]]; then
  validation_args+=(--require-developer-id)
fi
../../scripts/verify-macos-app-bundle.sh "${validation_args[@]}"

# Refresh the icon cache so Finder shows the new icon immediately.
touch "$APP"

echo "✓ Built $APP"
