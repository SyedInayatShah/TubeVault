#!/usr/bin/env bash
# Builds TubeVault.app into ./build. Pass --universal for an arm64 + x86_64 build.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
ARCHS=("$(uname -m)")
if [[ "${1:-}" == "--universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  ARCHS=(arm64 x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/TubeVault"

APP=build/TubeVault.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TubeVault"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R extension/chrome "$APP/Contents/Resources/ChromeExtension"

# Safari extension: the same web extension, wrapped in an app extension inside TubeVault.app.
APPEX="$APP/Contents/PlugIns/TubeVault Extension.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
SLICES=()
for arch in "${ARCHS[@]}"; do
  out="$(mktemp -d)/TubeVaultExtension"
  swiftc -O -parse-as-library -application-extension -module-name TubeVaultExtension \
    -target "$arch-apple-macos14.0" -Xlinker -e -Xlinker _NSExtensionMain \
    -framework SafariServices -framework AppKit \
    Sources/SafariExtension/*.swift -o "$out"
  SLICES+=("$out")
done
lipo -create "${SLICES[@]}" -output "$APPEX/Contents/MacOS/TubeVault Extension"
cp Resources/SafariExtension/Info.plist "$APPEX/Contents/Info.plist"
for key in CFBundleShortVersionString CFBundleVersion; do
  plutil -replace "$key" -string "$(plutil -extract "$key" raw Resources/Info.plist)" "$APPEX/Contents/Info.plist"
done
rsync -a --exclude manifest.json extension/chrome/ "$APPEX/Contents/Resources/"
# Safari has no use for Chrome's fixed-ID key.
python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); m.pop("key",None); json.dump(m,open(sys.argv[2],"w"),indent=2,ensure_ascii=False)' \
  extension/chrome/manifest.json "$APPEX/Contents/Resources/manifest.json"

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --entitlements Resources/SafariExtension/Extension.entitlements "$APPEX"
codesign --force --sign - "$APP"
echo "Built $APP"
