#!/bin/bash
# A throwaway demo of Glade: its own home directory, its own settings file, nothing touches your real
# ~/.glade, ~/.claude-buddy or ~/.claude. Start: scripts/demo.sh start   Stop and clean up: scripts/demo.sh stop
set -u
cd "$(dirname "$0")/.."
MARK="${TMPDIR:-/tmp}/glade-demo-home"

stop() {
  if [ -f "$MARK" ]; then
    TH=$(cat "$MARK")
    GLADE_HOME="$TH/.glade" .build/debug/glade quit >/dev/null 2>&1
    sleep 1
    # close only the Terminal windows that use the Glade profile
    osascript -e 'tell application "Terminal" to repeat with w in (windows whose name of current settings of selected tab is "Glade")
      close w
    end repeat' >/dev/null 2>&1 || true
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
  echo '{}' > "$TH/settings.json"
  G=.build/debug/glade
  # two sample photo looks, if macOS's built-in wallpapers are around
  T="/System/Library/Desktop Pictures/.thumbnails"
  [ -f "$T/Big Sur Coastline.heic" ] && $G look add "$T/Big Sur Coastline.heic" --name "Red coast" >/dev/null
  [ -f "$T/Catalina Sunset.heic" ] && $G look add "$T/Catalina Sunset.heic" --name "Island sunset" --calm 0.3 >/dev/null
  (nohup $G >/dev/null 2>&1 &)
  sleep 1.5
  $G open home
  sleep 2
  # a Terminal window in the Glade profile, with the scene behind it
  $G terminal open >/dev/null 2>&1; $G scenery on >/dev/null
  sleep 3
  # Hoot's pop-up, getting more impatient, then done
  $G test;                 sleep 5
  $G test --age 70;        sleep 5
  $G test --age 130;       sleep 5
  $G test done;            sleep 6
  $G hide
  echo "demo is running; stop it with: scripts/demo.sh stop"
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  *) echo "usage: scripts/demo.sh start|stop"; exit 1 ;;
esac
