#!/bin/bash
# A throwaway demo of Glade: its own home directory, its own settings file, nothing touches your real
# ~/.glade, ~/.claude-buddy or ~/.claude. Start: scripts/demo.sh start   Stop and clean up: scripts/demo.sh stop
# After it starts, click Hoot's menu-bar icon and choose "Open Glade…".
set -u
cd "$(dirname "$0")/.."
MARK="${TMPDIR:-/tmp}/glade-demo-home"

# a raw event for the daemon: event, terminal bundle id, flags, json
EMPTY="{}"
send() { printf '%s\n\n%s\n%s\n' "$1" "$2" "${3:-$EMPTY}" | nc -U "$GLADE_HOME/glade.sock"; }

stop() {
  if [ -f "$MARK" ]; then
    TH=$(cat "$MARK")
    GLADE_HOME="$TH/.glade" send Quit "" >/dev/null 2>&1
    sleep 1
    pkill -f "$TH" 2>/dev/null
    rm -rf "$TH" "$MARK"
    echo "demo stopped and cleaned up"
  else
    echo "no demo running"
  fi
}

start() {
  [ -f "$MARK" ] && stop
  swift build >/dev/null 2>&1 || { echo "swift build failed"; exit 1; }
  TH=$(mktemp -d); echo "$TH" > "$MARK"
  export GLADE_HOME="$TH/.glade" GLADE_LEGACY_HOME="$TH/old" GLADE_CLAUDE_SETTINGS="$TH/settings.json"
  mkdir -p "$GLADE_HOME"; echo '{}' > "$TH/settings.json"
  (nohup .build/debug/glade >/dev/null 2>&1 &)
  sleep 2
  echo "demo is running; stop it with: scripts/demo.sh stop"
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  *) echo "usage: scripts/demo.sh start|stop"; exit 1 ;;
esac
