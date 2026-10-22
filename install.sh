#!/bin/bash
# Builds Glade, installs it to ~/.glade, and merges hooks into ~/.claude/settings.json.
# Also migrates an existing claude-buddy install (config copied, old hooks replaced, old app removed).
set -euo pipefail
cd "$(dirname "$0")"

DEST="$HOME/.glade"
APP="$DEST/Glade.app"
OLD="$HOME/.claude-buddy"
SETTINGS="$HOME/.claude/settings.json"
MARK="/.glade/hook.sh"
OLD_MARK="/.claude-buddy/hook.sh"

command -v jq >/dev/null || { echo "jq is required (brew install jq)"; exit 1; }

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
cp scripts/hook.sh "$DEST/hook.sh" && chmod +x "$DEST/hook.sh"
ln -sf "$APP/Contents/MacOS/glade" "$DEST/bin/glade"
ln -sf "$APP/Contents/MacOS/glade" "$HOME/.local/bin/glade"
# old scripts that call `claude-buddy` keep working
ln -sf "$APP/Contents/MacOS/glade" "$HOME/.local/bin/claude-buddy"

echo "==> merging hooks into $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || { echo "$SETTINGS is not valid JSON; fix it first"; exit 1; }
BACKUP="$SETTINGS.glade-backup.$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"
echo "    backup: $BACKUP"
TMP=$(mktemp)
jq --arg h "$DEST/hook.sh" --arg mark "$MARK" --arg old "$OLD_MARK" '
  def ours: ([.hooks[]?.command // ""] | any(contains($mark) or contains($old)));
  def add($ev): .hooks[$ev] = (((.hooks[$ev] // []) | map(select(ours | not)))
                 + [{hooks: [{type: "command", command: ($h + " " + $ev), timeout: 5}]}]);
  .hooks //= {}
  | add("Notification") | add("Stop") | add("UserPromptSubmit") | add("PostToolUse")
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"

# old install is fully replaced now: hooks swapped above, config copied, app stopped
if [ -d "$OLD" ]; then
  rm -rf "$OLD"
  echo "==> removed old install at $OLD"
fi

echo
echo "Installed. Try it:  $DEST/bin/glade test"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "(add ~/.local/bin to PATH to use plain 'glade')" ;; esac
echo "Restart running Claude Code sessions so they pick up the hooks."
