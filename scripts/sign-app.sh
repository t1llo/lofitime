#!/bin/bash
set -euo pipefail
app="${1:?Usage: sign-app.sh APP [IDENTITY]}"
identity="${2:--}"
args=(--force --sign "$identity")
if [[ "$identity" != - ]]; then args+=(--options runtime --timestamp); fi
framework="$app/Contents/Frameworks/Sparkle.framework"
for nested in XPCServices/Downloader.xpc XPCServices/Installer.xpc Autoupdate Updater.app; do
    codesign "${args[@]}" "$framework/Versions/B/$nested"
done
codesign "${args[@]}" "$framework"
codesign "${args[@]}" "$app"
codesign --verify --deep --strict "$app"
