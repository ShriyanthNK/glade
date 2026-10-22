#!/bin/bash
# The independent verifier for the app. Exits 0 only if everything the project promises still holds.
# Loops call this instead of trusting the implementer's own report. Run: scripts/verify.sh
set -u
cd "$(dirname "$0")/.."
fail=0
step() {
  printf '%-34s' "$1"
  if out=$("${@:2}" 2>&1); then echo "ok"; else echo "FAIL"; echo "$out" | tail -20 | sed 's/^/    /'; fail=1; fi
}
REAL_SUM=$(shasum "$HOME/.claude/settings.json" 2>/dev/null || echo none)
step "swift build" swift build
step "unit tests" swift test
step "install smoke test" scripts/test-install.sh
[ "$(shasum "$HOME/.claude/settings.json" 2>/dev/null || echo none)" = "$REAL_SUM" ] && echo "real settings.json untouched ... ok" || { echo "real settings.json CHANGED ... FAIL"; fail=1; }
[ -e "$HOME/.glade" ] && { echo "stray ~/.glade left behind ... FAIL"; fail=1; }
[ "$fail" = 0 ] && echo "VERIFY PASSED" || echo "VERIFY FAILED"
exit $fail
