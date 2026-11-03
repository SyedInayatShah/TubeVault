#!/usr/bin/env bash
# Builds TubeVault.app into ./build. Pass --universal for an arm64 + x86_64 build.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/TubeVault"

APP=build/TubeVault.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TubeVault"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R extension/chrome "$APP/Contents/Resources/ChromeExtension"

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
