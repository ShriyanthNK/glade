#!/bin/bash
# Removes Glade's hooks from ~/.claude/settings.json (backup first) and deletes everything it installed.
# The Uninstall button on the app's About page does the same, and also restores a replaced status line.
set -euo pipefail
DEST="${GLADE_HOME:-$HOME/.glade}"
OLD="${GLADE_LEGACY_HOME:-$HOME/.claude-buddy}"
S="${GLADE_CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

pkill -x glade 2>/dev/null || true
pkill -x claude-buddy 2>/dev/null || true

if [ -f "$S" ] && grep -q -E "/\.glade/hook\.sh|/\.claude-buddy/hook\.sh" "$S"; then
  cp "$S" "$S.glade-backup"
  jq '(.hooks // {}) |= with_entries(.value |= (map(.hooks |= map(select((.command // "") | test("/\\.(glade|claude-buddy)/hook\\.sh") | not))) | map(select(.hooks | length > 0))))
      | if (.hooks | length) == 0 then del(.hooks) else . end
      | if ((.statusLine.command // "") | test("/\\.glade/")) then del(.statusLine) else . end' "$S.glade-backup" > "$S"
  echo "hooks removed (backup: $S.glade-backup)"
fi

for l in "$HOME/.local/bin/glade" "$HOME/.local/bin/claude-buddy"; do
  [ -L "$l" ] && rm -f "$l"
done
rm -rf "$DEST" "$OLD"
echo "glade uninstalled."
