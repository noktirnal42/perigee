#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-run}"
pkill -x Perigee >/dev/null 2>&1 || true
xcodebuild -project Perigee.xcodeproj -scheme Perigee_macOS -configuration Debug -derivedDataPath .build-app CODE_SIGNING_ALLOWED=NO build
app="$PWD/.build-app/Build/Products/Debug/Perigee.app"
case "$mode" in
  run) open -n "$app" ;;
  --verify) open -n "$app"; sleep 1; pgrep -x Perigee >/dev/null ;;
  --debug) lldb "$app/Contents/MacOS/Perigee" ;;
  --logs) open -n "$app"; log stream --info --style compact --predicate 'process == "Perigee"' ;;
  --telemetry) open -n "$app"; log stream --info --style compact --predicate 'subsystem == "com.perigee.companion"' ;;
  *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
