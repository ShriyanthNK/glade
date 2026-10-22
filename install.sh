#!/bin/bash
# Builds Glade and installs the app to ~/.glade. Open it from the menu bar and turn on the Claude Code hooks
# on the "Claude Code" page. Also migrates an existing claude-buddy install (config copied, old app removed).
set -euo pipefail
cd "$(dirname "$0")"

DEST="${GLADE_HOME:-$HOME/.glade}"
APP="$DEST/Glade.app"
OLD="${GLADE_LEGACY_HOME:-$HOME/.claude-buddy}"

echo "==> building"
BUILT="$(scripts/bundle.sh build)"

echo "==> stopping any running copy"
pkill -x glade 2>/dev/null || true
pkill -x claude-buddy 2>/dev/null || true
sleep 0.3

echo "==> installing app to $APP"
mkdir -p "$DEST"
if [ -f "$OLD/config.json" ] && [ ! -f "$DEST/config.json" ]; then
  cp "$OLD/config.json" "$DEST/config.json"
  echo "    migrated settings from $OLD"
fi
rm -rf "$APP"
cp -R "$BUILT" "$APP"

if [ -d "$OLD" ]; then
  rm -rf "$OLD"
  echo "==> removed old install at $OLD"
fi

if [ -z "${GLADE_HOME:-}" ]; then open -g "$APP"; fi
echo
echo "Installed. Glade is in your menu bar: open it and install the hooks on the Claude Code page."
echo "Restart running Claude Code sessions afterwards so they pick up the hooks."
