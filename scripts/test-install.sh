#!/bin/bash
# End-to-end check of install.sh / uninstall.sh / the CLI in a throwaway home directory.
# Never touches the real ~/.glade, ~/.claude-buddy or ~/.claude (HOME and GLADE_HOME are both overridden).
set -euo pipefail
cd "$(dirname "$0")/.."

TH=$(mktemp -d)                       # short path: unix socket paths are limited to ~100 chars
export HOME="$TH" GLADE_HOME="$TH/.glade" GLADE_LEGACY_HOME="$TH/.claude-buddy"
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
for ev in Notification Stop UserPromptSubmit PostToolUse; do
  jq -e --arg ev "$ev" '[.hooks[$ev][].hooks[].command] | any(endswith("/.glade/hook.sh " + $ev))' "$S" >/dev/null || fail "hook $ev missing"
done
ok "four hooks installed"
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
"$GLADE" quit; sleep 1

./uninstall.sh >/dev/null 2>&1 || fail "uninstall.sh exited non-zero"
diff <(jq -S 'del(.hooks.Stop[0])' "$TH/before.json") <(jq -S . "$S") >/dev/null || fail "uninstall did not restore settings"
[ ! -d "$GLADE_HOME" ] || fail "~/.glade not removed"
ok "uninstall restores settings and removes files"
echo "ALL PASSED"
