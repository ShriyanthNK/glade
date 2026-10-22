#!/bin/bash
# End-to-end check of install.sh / uninstall.sh / the CLI in a throwaway home directory.
# Never touches the real ~/.glade, ~/.claude-buddy or ~/.claude (HOME and GLADE_HOME are both overridden).
set -euo pipefail
cd "$(dirname "$0")/.."

REAL_SETTINGS="$(eval echo ~)/.claude/settings.json"   # captured before HOME is overridden
TH=$(mktemp -d)                       # short path: unix socket paths are limited to ~100 chars
export HOME="$TH" GLADE_HOME="$TH/.glade" GLADE_LEGACY_HOME="$TH/.claude-buddy" GLADE_CLAUDE_SETTINGS="$TH/.claude/settings.json"
REAL_SUM_BEFORE=$(shasum "$REAL_SETTINGS" 2>/dev/null || echo none)
cleanup() { "$TH/.glade/bin/glade" quit >/dev/null 2>&1 || true; sleep 0.5; rm -rf "$TH"; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok   $*"; }

mkdir -p "$TH/.claude" "$TH/.claude-buddy/bin"
cat > "$TH/.claude/settings.json" <<JSON
{
  "model": "sonnet",
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "$TH/.claude-buddy/hook.sh Stop", "timeout": 5}]},
      {"hooks": [{"type": "command", "command": "/usr/local/bin/other-hook Stop"}]}
    ],
    "PreToolUse": [{"hooks": [{"type": "command", "command": "/usr/local/bin/audit"}]}]
  }
}
JSON
cp "$TH/.claude/settings.json" "$TH/before.json"
echo '{"chime": true, "waitDelay": 9, "doneDelay": 12, "giveUpAfter": 180, "snoozeUntil": 0}' > "$TH/.claude-buddy/config.json"

./install.sh >/dev/null 2>&1 || fail "install.sh exited non-zero"
S="$TH/.claude/settings.json"
for ev in Notification Stop UserPromptSubmit PostToolUse PermissionRequest; do
  jq -e --arg ev "$ev" '[.hooks[$ev][].hooks[].command] | any(endswith("/.glade/hook.sh " + $ev))' "$S" >/dev/null || fail "hook $ev missing"
done
ok "five hooks installed"
[ "$("$GLADE_HOME/bin/glade" hooks status)" = "installed" ] || fail "hooks status did not report installed"
jq -e '[.hooks.Stop[].hooks[].command] | any(contains("/.claude-buddy/"))' "$S" >/dev/null && fail "old hook still present"
ok "old claude-buddy hook replaced"
jq -e '[.hooks.Stop[].hooks[].command] | any(. == "/usr/local/bin/other-hook Stop")' "$S" >/dev/null || fail "unrelated Stop hook lost"
jq -e '.hooks.PreToolUse and .model == "sonnet"' "$S" >/dev/null || fail "unrelated settings lost"
ok "unrelated hooks and settings preserved"
[ "$(jq .waitDelay "$GLADE_HOME/config.json")" = "9" ] || fail "config not migrated"
[ ! -d "$TH/.claude-buddy" ] || fail "old install dir not removed"
ok "config migrated, old dir removed"
ls "$TH"/.claude/settings.json.glade-backup.* >/dev/null 2>&1 || fail "no settings backup"
ok "settings backup written"

# daemon + CLI + hook against the isolated socket
GLADE="$GLADE_HOME/bin/glade"
"$GLADE" test done | grep -q "buddy sent" || fail "glade test failed"
sleep 1
[ -S "$GLADE_HOME/glade.sock" ] || fail "daemon did not bind $GLADE_HOME/glade.sock"
ok "daemon started on the isolated socket"
echo '{"session_id":"s1","cwd":"/x/proj","message":"hi"}' | "$GLADE_HOME/hook.sh" Notification
"$GLADE" delays 6 8 >/dev/null
[ "$(jq .doneDelay "$GLADE_HOME/config.json")" = "8" ] || fail "delays did not write config"
"$GLADE" snooze 30 >/dev/null
jq -e '.snoozeUntil > 0' "$GLADE_HOME/config.json" >/dev/null || fail "snooze did not write config"
ok "CLI writes the isolated config"
"$GLADE" snapshot "$TH/snap.png" done >/dev/null && [ -s "$TH/snap.png" ] || fail "snapshot failed"
ok "snapshot renders"
[ -s "$GLADE_HOME/Glade.app/Contents/Resources/Looks/night-forest.png" ] || fail "built-in look missing from the app bundle"
"$GLADE" look list | grep -q "night-forest" || fail "glade look list is missing the built-in"
cp "$GLADE_HOME/Glade.app/Contents/Resources/Looks/night-forest.png" "$TH/photo.png"
"$GLADE" look add "$TH/photo.png" --name "Test photo" | grep -q "^added user-" || fail "glade look add failed"
"$GLADE" look list | grep -q "Test photo" || fail "added look not listed"
ID=$("$GLADE" look list | awk '/Test photo/ {print ($1 == "*") ? $2 : $1}')
"$GLADE" look use "$ID" >/dev/null && [ "$(jq -r .lookId "$GLADE_HOME/config.json")" = "$ID" ] || fail "look use did not write config"
"$GLADE" look remove "$ID" >/dev/null
[ "$(jq -r .lookId "$GLADE_HOME/config.json")" = "night-forest" ] || fail "removing the active look did not fall back"
ok "look list / add / use / remove, built-in shipped in the bundle"
"$GLADE" scenery on | grep -q "scenery on" && [ "$(jq .sceneryOn "$GLADE_HOME/config.json")" = "true" ] || fail "scenery on did not write config"
"$GLADE" scenery off >/dev/null && [ "$("$GLADE" scenery status)" = "off" ] || fail "scenery off did not write config"
ok "scenery on / off"
"$GLADE" statusline install | grep -q "installed" || fail "statusline install failed"
[ "$("$GLADE" statusline status)" = "installed" ] || fail "statusline status wrong"
echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":92}}' | "$GLADE_HOME/statusline.sh" | grep -q "HELLOOO" || fail "installed status line script did not render"
"$GLADE" statusline uninstall >/dev/null && [ "$("$GLADE" statusline status)" = "not installed" ] || fail "statusline uninstall failed"
ok "status line install / render / uninstall"
"$GLADE" quit; sleep 1

./uninstall.sh >/dev/null 2>&1 || fail "uninstall.sh exited non-zero"
diff <(jq -S 'del(.hooks.Stop[0])' "$TH/before.json") <(jq -S . "$S") >/dev/null || fail "uninstall did not restore settings"
[ ! -d "$GLADE_HOME" ] || fail "~/.glade not removed"
ok "uninstall restores settings and removes files"
[ "$(shasum "$REAL_SETTINGS" 2>/dev/null || echo none)" = "$REAL_SUM_BEFORE" ] || fail "the real ~/.claude/settings.json changed"
ok "real ~/.claude/settings.json untouched"
echo "ALL PASSED"
