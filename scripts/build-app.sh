#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
    echo "Usage: $0 [release|debug]" >&2
    exit 1
fi

args=(--configuration "$CONFIGURATION" --product LofiMen --disable-keychain)
if [[ "${LOFITIME_UNIVERSAL:-0}" == 1 ]]; then args+=(--arch arm64 --arch x86_64); fi
swift build "${args[@]}"
BIN_DIR="$(swift build "${args[@]}" --show-bin-path)"
APP="$ROOT/build/Lofitime.app"
STAGING="$ROOT/build/.Lofitime.staging.app"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN_DIR/LofiMen" "$STAGING/Contents/MacOS/LofiMen"
cp Configuration/Info.plist "$STAGING/Contents/Info.plist"
ditto "$BIN_DIR/LofiMen_LofiMen.bundle" "$STAGING/Contents/Resources/LofiMen_LofiMen.bundle"
SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle"
mkdir -p "$STAGING/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$STAGING/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$STAGING/Contents/Resources/Sparkle-LICENSE.txt"

if [[ ! -f "$ROOT/build/AppIcon.icns" || scripts/create-icon.swift -nt "$ROOT/build/AppIcon.icns" ]]; then
    swift scripts/create-icon.swift "$ROOT/build"
    iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$ROOT/build/AppIcon.icns"
fi
cp "$ROOT/build/AppIcon.icns" "$STAGING/Contents/Resources/AppIcon.icns"
bash scripts/sign-app.sh "$STAGING" "${LOFITIME_SIGN_IDENTITY:--}"
rm -rf "$APP"
mv "$STAGING" "$APP"
echo "Built $APP ($CONFIGURATION)"
