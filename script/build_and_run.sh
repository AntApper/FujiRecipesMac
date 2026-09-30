#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="com.ant.fuji-recipes-mac.debug"
APP_BUNDLE="$ROOT_DIR/macos/build/Fuji Recipes.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/FujiRecipesMac"
MODE="run"

usage() {
  echo "Usage: $0 [--debug|--logs|--telemetry|--verify]" >&2
}

if [[ $# -gt 1 ]]; then usage; exit 2; fi
if [[ $# -eq 1 ]]; then
  case "$1" in
    --debug|--logs|--telemetry|--verify) MODE="$1" ;;
    *) usage; exit 2 ;;
  esac
fi

if [[ -d "$APP_BUNDLE" ]]; then
  # Request a normal app termination for this development bundle only. If the
  # app is prompting about or completing a write, its termination delegate
  # can veto the request. Never force-kill a camera operation.
  /usr/bin/osascript -e "if application id \"$APP_ID\" is running then tell application id \"$APP_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    if ! running="$(/usr/bin/osascript -e "application id \"$APP_ID\" is running" 2>/dev/null)"; then
      echo "error: could not confirm whether the FujiRecipes debug app is running; refusing to rebuild" >&2
      exit 1
    fi
    [[ "$running" == "false" ]] && break
    sleep 1
  done
  if [[ "$running" != "false" ]]; then
    echo "error: the FujiRecipes debug app did not quit; finish or cancel its active operation, then rerun" >&2
    exit 1
  fi
fi

"$ROOT_DIR/macos/package_app.sh" debug --version 0.0.0 --build-number 1

/usr/bin/open -n "$APP_BUNDLE"

case "$MODE" in
  run) ;;
  --verify)
    sleep 1
    running="$(/usr/bin/osascript -e "application id \"$APP_ID\" is running" 2>/dev/null || echo false)"
    [[ "$running" == "true" ]] || { echo "error: FujiRecipes debug app did not remain running" >&2; exit 1; }
    ;;
  --logs)
    exec /usr/bin/log stream --info --style compact --predicate 'process == "FujiRecipesMac"'
    ;;
  --telemetry)
    exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.ant.fuji-recipes"'
    ;;
  --debug)
    sleep 1
    app_pid="$(/usr/bin/osascript -e "tell application \"System Events\" to get unix id of (first process whose bundle identifier is \"$APP_ID\")")"
    exec lldb -p "$app_pid"
    ;;
esac
