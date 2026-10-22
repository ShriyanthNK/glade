#!/bin/bash
# Smoke test of install.sh / uninstall.sh and the running app, in a throwaway home directory.
# Never touches the real ~/.glade, ~/.claude-buddy or ~/.claude (HOME and GLADE_HOME are both overridden).
set -euo pipefail
cd "$(dirname "$0")/.."

REAL_SETTINGS="$(eval echo ~)/.claude/settings.json"   # captured before HOME is overridden
TH=$(mktemp -d)                       # short path: unix socket paths are limited to ~100 chars
export HOME="$TH" GLADE_HOME="$TH/.glade" GLADE_LEGACY_HOME="$TH/.claude-buddy" GLADE_CLAUDE_SETTINGS="$TH/.claude/settings.json"
REAL_SUM_BEFORE=$(shasum "$REAL_SETTINGS" 2>/dev/null || echo none)
# a raw event for the daemon: event, terminal bundle id, flags, json
send() { printf '%s\n\n%s\n{}\n' "$1" "${2:-}" | nc -U "$GLADE_HOME/glade.sock"; }
cleanup() { send Quit >/dev/null 2>&1 || true; sleep 0.5; rm -rf "$TH"; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok   $*"; }

mkdir -p "$TH/.claude" "$TH/.claude-buddy"
echo '{"waitDelay": 9}' > "$TH/.claude-buddy/config.json"
cat > "$TH/.claude/settings.json" <<JSON
{
  "model": "sonnet",
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "/usr/local/bin/other-hook Stop"}]},
      {"hooks": [{"type": "command", "command": "$TH/.claude-buddy/hook.sh Stop"}]}
    ],
    "PreToolUse": [{"hooks": [{"type": "command", "command": "/usr/local/bin/audit"}]}]
  }
}
JSON
S="$TH/.claude/settings.json"
jq 'del(.hooks.Stop[1])' "$S" > "$TH/before.json"

./install.sh >/dev/null 2>&1 || fail "install.sh exited non-zero"
APP="$GLADE_HOME/Glade.app"
[ -x "$APP/Contents/MacOS/glade" ] || fail "app was not installed"
[ ! -d "$TH/.claude-buddy" ] || fail "old install not removed"
[ "$(jq .waitDelay "$GLADE_HOME/config.json")" = "9" ] || fail "config not migrated"
ok "install and migrate"

[ -s "$APP/Contents/Resources/Looks/night-forest.png" ] || fail "built-in look missing from the app bundle"
ls "$APP/Contents/Resources/Fonts/"*.ttf >/dev/null 2>&1 || fail "fonts missing from the app bundle"
ok "bundle has looks and fonts"

(nohup "$APP/Contents/MacOS/glade" >/dev/null 2>&1 &)
for _ in $(seq 1 30); do [ -S "$GLADE_HOME/glade.sock" ] && break; sleep 0.2; done
[ -S "$GLADE_HOME/glade.sock" ] || fail "daemon did not bind $GLADE_HOME/glade.sock"
send Hide >/dev/null || fail "daemon did not accept an event"
ok "app starts and takes events"
send Quit >/dev/null 2>&1; sleep 1

./uninstall.sh >/dev/null 2>&1 || fail "uninstall.sh exited non-zero"
[ ! -d "$GLADE_HOME" ] || fail "~/.glade not removed"
diff <(jq -S . "$TH/before.json") <(jq -S . "$S") >/dev/null || fail "uninstall did not clean settings.json"
ok "uninstall removes files and Glade hooks"
[ "$(shasum "$REAL_SETTINGS" 2>/dev/null || echo none)" = "$REAL_SUM_BEFORE" ] || fail "the real ~/.claude/settings.json changed"
ok "real ~/.claude/settings.json untouched"
echo "ALL PASSED"
