#!/bin/bash
# Removes Glade's hooks from ~/.claude/settings.json and deletes everything it installed.
set -euo pipefail
DEST="$HOME/.glade"
OLD="$HOME/.claude-buddy"
SETTINGS="$HOME/.claude/settings.json"
MARK="/.glade/hook.sh"
OLD_MARK="/.claude-buddy/hook.sh"

[ -x "$DEST/bin/glade" ] && "$DEST/bin/glade" quit 2>/dev/null || true
pkill -x glade 2>/dev/null || true
pkill -x claude-buddy 2>/dev/null || true

if [ -f "$SETTINGS" ] && command -v jq >/dev/null && jq -e --arg mark "$MARK" --arg old "$OLD_MARK" '.. | strings | select(contains($mark) or contains($old))' "$SETTINGS" >/dev/null 2>&1; then
  BACKUP="$SETTINGS.glade-backup.$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
  echo "backup: $BACKUP"
  TMP=$(mktemp)
  jq --arg mark "$MARK" --arg old "$OLD_MARK" '
    def ours: ([.hooks[]?.command // ""] | any(contains($mark) or contains($old)));
    if .hooks then
      .hooks |= (with_entries(.value |= map(select(ours | not))) | with_entries(select(.value | length > 0)))
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
  echo "hooks removed from $SETTINGS"
fi

for l in "$HOME/.local/bin/glade" "$HOME/.local/bin/claude-buddy"; do
  [ -L "$l" ] && rm -f "$l"
done
rm -rf "$DEST" "$OLD"
echo "glade uninstalled."
