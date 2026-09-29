#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
    echo "Usage: $0 [release|debug]" >&2
    exit 1
fi

swift build --configuration "$CONFIGURATION" --product LofiMen
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/build/Lofi Men.app"
STAGING="$ROOT/build/.Lofi Men.staging.app"
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN_DIR/LofiMen" "$STAGING/Contents/MacOS/LofiMen"
cp Configuration/Info.plist "$STAGING/Contents/Info.plist"
ditto "$BIN_DIR/LofiMen_LofiMen.bundle" "$STAGING/Contents/Resources/LofiMen_LofiMen.bundle"

if [[ ! -f "$ROOT/build/AppIcon.icns" || scripts/create-icon.swift -nt "$ROOT/build/AppIcon.icns" ]]; then
    swift scripts/create-icon.swift "$ROOT/build"
    iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$ROOT/build/AppIcon.icns"
fi
cp "$ROOT/build/AppIcon.icns" "$STAGING/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$STAGING"
rm -rf "$APP"
mv "$STAGING" "$APP"
echo "Built $APP ($CONFIGURATION)"
