#!/bin/bash
# Removes Glade's hooks from ~/.claude/settings.json and deletes everything it installed.
set -euo pipefail
DEST="${GLADE_HOME:-$HOME/.glade}"
OLD="${GLADE_LEGACY_HOME:-$HOME/.claude-buddy}"

if [ -x "$DEST/bin/glade" ]; then
  "$DEST/bin/glade" hooks uninstall || echo "could not edit settings.json; remove the Glade entries by hand" >&2
  "$DEST/bin/glade" quit 2>/dev/null || true
fi
pkill -x glade 2>/dev/null || true
pkill -x claude-buddy 2>/dev/null || true

for l in "$HOME/.local/bin/glade" "$HOME/.local/bin/claude-buddy"; do
  [ -L "$l" ] && rm -f "$l"
done
rm -rf "$DEST" "$OLD"
echo "glade uninstalled."
