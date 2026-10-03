#!/usr/bin/env bash
# Builds EarMix.app into ./build.noindex. Pass --install to copy it into /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="EarMix"
MIN_MACOS="14.0"
# The .noindex suffix keeps Spotlight from listing this copy next to the installed app.
BUILD_DIR="build.noindex"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
SOURCES=(Sources/EarMix/*.swift)

mkdir -p "$BUILD_DIR"

# Compile each architecture with swiftc, then merge into one universal binary.
for arch in arm64 x86_64; do
    xcrun swiftc -O -parse-as-library \
        -target "${arch}-apple-macos${MIN_MACOS}" \
        -o "$BUILD_DIR/${APP_NAME}-${arch}" \
        "${SOURCES[@]}"
done

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
lipo -create -output "$APP_DIR/Contents/MacOS/$APP_NAME" \
    "$BUILD_DIR/${APP_NAME}-arm64" "$BUILD_DIR/${APP_NAME}-x86_64"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

# Ad-hoc signature so macOS runs it locally without a developer account.
codesign --force --sign - "$APP_DIR"

echo "Built $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP_DIR" /Applications/
    echo "Installed to /Applications/${APP_NAME}.app"
    open "/Applications/${APP_NAME}.app"
fi
