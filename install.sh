#!/bin/bash
# Builds Glade, installs it to ~/.glade, and adds its hooks to ~/.claude/settings.json.
# Also migrates an existing claude-buddy install (config copied, old hooks replaced, old app removed).
set -euo pipefail
cd "$(dirname "$0")"

DEST="${GLADE_HOME:-$HOME/.glade}"
APP="$DEST/Glade.app"
OLD="${GLADE_LEGACY_HOME:-$HOME/.claude-buddy}"

echo "==> building"
BUILT="$(scripts/bundle.sh build)"

echo "==> stopping any running copy"
[ -x "$APP/Contents/MacOS/glade" ] && "$APP/Contents/MacOS/glade" quit 2>/dev/null || true
[ -x "$OLD/bin/claude-buddy" ] && "$OLD/bin/claude-buddy" quit 2>/dev/null || true
pkill -x glade 2>/dev/null || true
pkill -x claude-buddy 2>/dev/null || true
sleep 0.3

echo "==> installing app to $APP"
mkdir -p "$DEST/bin" "$HOME/.local/bin"
if [ -f "$OLD/config.json" ] && [ ! -f "$DEST/config.json" ]; then
  cp "$OLD/config.json" "$DEST/config.json"
  echo "    migrated settings from $OLD"
fi
rm -rf "$APP"
cp -R "$BUILT" "$APP"
ln -sf "$APP/Contents/MacOS/glade" "$DEST/bin/glade"
ln -sf "$APP/Contents/MacOS/glade" "$HOME/.local/bin/glade"
# old scripts that call `claude-buddy` keep working
ln -sf "$APP/Contents/MacOS/glade" "$HOME/.local/bin/claude-buddy"

echo "==> adding hooks (this also replaces any claude-buddy hooks)"
"$DEST/bin/glade" hooks install

# the old install is fully replaced now: hooks swapped, config copied, app stopped
if [ -d "$OLD" ]; then
  rm -rf "$OLD"
  echo "==> removed old install at $OLD"
fi

echo
echo "Installed. Try it:  $DEST/bin/glade test      Settings:  $DEST/bin/glade settings"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "(add ~/.local/bin to PATH to use plain 'glade')" ;; esac
echo "Restart running Claude Code sessions so they pick up the hooks."
