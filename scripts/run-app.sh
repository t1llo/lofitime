#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if pgrep -x LofiMen >/dev/null; then
    osascript -e 'tell application id "com.lofimen.app" to quit'
    for attempt in {1..50}; do
        if ! pgrep -x LofiMen >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -x LofiMen >/dev/null; then
        echo "Lofitime is still quitting. Try make run again in a moment." >&2
        exit 1
    fi
fi
# Avoid Launch Services trying to reactivate the just-terminated process.
open -n "$ROOT/build/Lofitime.app"
