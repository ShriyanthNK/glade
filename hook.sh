#!/bin/sh
# claude-buddy hook: forwards a Claude Code hook event to the buddy daemon.
# Returns immediately; all real work happens in a detached background job.
ev="$1"
sock="$HOME/.claude-buddy/buddy.sock"
payload=$(cat | tr -d '\n')
{
  msg=$(printf '%s\n%s\n\n%s\n' "$ev" "${__CFBundleIdentifier:-}" "$payload")
  if ! printf '%s' "$msg" | /usr/bin/nc -U -w 1 "$sock" >/dev/null 2>&1; then
    case "$ev" in
      Notification|Stop)
        /usr/bin/open -g "$HOME/.claude-buddy/ClaudeBuddy.app"
        i=0
        while [ "$i" -lt 25 ]; do
          sleep 0.2
          printf '%s' "$msg" | /usr/bin/nc -U -w 1 "$sock" >/dev/null 2>&1 && break
          i=$((i + 1))
        done ;;
    esac
  fi
} </dev/null >/dev/null 2>&1 &
exit 0
