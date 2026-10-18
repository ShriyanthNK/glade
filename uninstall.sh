#!/bin/bash
# Removes claude-buddy hooks from ~/.claude/settings.json and deletes everything it installed.
set -euo pipefail
DEST="$HOME/.claude-buddy"
SETTINGS="$HOME/.claude/settings.json"
MARK="/.claude-buddy/hook.sh"

[ -x "$DEST/bin/claude-buddy" ] && "$DEST/bin/claude-buddy" quit 2>/dev/null || true
pkill -x claude-buddy 2>/dev/null || true

if [ -f "$SETTINGS" ] && command -v jq >/dev/null && jq -e --arg mark "$MARK" '.. | strings | select(contains($mark))' "$SETTINGS" >/dev/null 2>&1; then
  BACKUP="$SETTINGS.claude-buddy-backup.$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
  echo "backup: $BACKUP"
  TMP=$(mktemp)
  jq --arg mark "$MARK" '
    def ours: ([.hooks[]?.command // ""] | any(contains($mark)));
    if .hooks then
      .hooks |= (with_entries(.value |= map(select(ours | not))) | with_entries(select(.value | length > 0)))
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
  echo "hooks removed from $SETTINGS"
fi

[ -L "$HOME/.local/bin/claude-buddy" ] && rm -f "$HOME/.local/bin/claude-buddy"
rm -rf "$DEST"
echo "claude-buddy uninstalled."
