#!/bin/bash
# Builds Glade.app from the Swift package: scripts/bundle.sh [OUT_DIR]   (default: build/)
# Ad-hoc signed. Release signing and notarization live in scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build}"
APP="$OUT/Glade.app"

# Xcode's swift refuses to run until its license is accepted; the Command Line Tools one does not.
if ! swift --version >/dev/null 2>&1; then
  if [ -x /Library/Developer/CommandLineTools/usr/bin/swift ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  else
    echo "No working Swift toolchain. Run: xcode-select --install" >&2; exit 1
  fi
fi

swift build -c release >&2
BIN="$(swift build -c release --show-bin-path)/glade"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/glade"
mkdir -p "$APP/Contents/Resources"
cp -R Resources/Looks "$APP/Contents/Resources/Looks"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.glade.Glade</string>
  <key>CFBundleName</key><string>Glade</string>
  <key>CFBundleExecutable</key><string>glade</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Glade finds your Terminal windows to put your chosen scene behind them.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
