#!/bin/bash
# Builds claude-buddy, installs it to ~/.claude-buddy, and merges hooks into ~/.claude/settings.json.
set -euo pipefail
cd "$(dirname "$0")"

DEST="$HOME/.claude-buddy"
APP="$DEST/ClaudeBuddy.app"
SETTINGS="$HOME/.claude/settings.json"
MARK="/.claude-buddy/hook.sh"

command -v jq >/dev/null || { echo "jq is required (brew install jq)"; exit 1; }

# Xcode's swiftc refuses to run until its license is accepted; the Command Line Tools one does not.
if ! swiftc --version >/dev/null 2>&1; then
  if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  else
    echo "No working Swift toolchain. Run: xcode-select --install"; exit 1
  fi
fi

echo "==> building"
mkdir -p build
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" Sources/*.swift -o build/claude-buddy

echo "==> installing app to $APP"
[ -S "$DEST/buddy.sock" ] && build/claude-buddy quit 2>/dev/null || true
pkill -x claude-buddy 2>/dev/null || true
sleep 0.3
mkdir -p "$APP/Contents/MacOS" "$DEST/bin"
cp build/claude-buddy "$APP/Contents/MacOS/claude-buddy"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.claude-buddy.app</string>
  <key>CFBundleName</key><string>ClaudeBuddy</string>
  <key>CFBundleExecutable</key><string>claude-buddy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
cp hook.sh "$DEST/hook.sh" && chmod +x "$DEST/hook.sh"
ln -sf "$APP/Contents/MacOS/claude-buddy" "$DEST/bin/claude-buddy"
mkdir -p "$HOME/.local/bin" && ln -sf "$APP/Contents/MacOS/claude-buddy" "$HOME/.local/bin/claude-buddy"

echo "==> merging hooks into $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || { echo "$SETTINGS is not valid JSON; fix it first"; exit 1; }
BACKUP="$SETTINGS.claude-buddy-backup.$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"
echo "    backup: $BACKUP"
TMP=$(mktemp)
jq --arg h "$DEST/hook.sh" --arg mark "$MARK" '
  def ours: ([.hooks[]?.command // ""] | any(contains($mark)));
  def add($ev): .hooks[$ev] = (((.hooks[$ev] // []) | map(select(ours | not)))
                 + [{hooks: [{type: "command", command: ($h + " " + $ev), timeout: 5}]}]);
  .hooks //= {}
  | add("Notification") | add("Stop") | add("UserPromptSubmit") | add("PostToolUse")
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"

echo
echo "Installed. Try it:  $DEST/bin/claude-buddy test"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "(add ~/.local/bin to PATH to use plain 'claude-buddy')" ;; esac
echo "Restart running Claude Code sessions so they pick up the hooks."
