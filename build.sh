#!/bin/bash
# Build BandFix2 and install it into ~/Applications. Does not launch it, because
# launching changes the display and BandFix's correction should be off first.
#
# Signed with the same self-signed "BandFix Dev" identity as BandFix, so Open at
# Login keeps working across rebuilds. Override with BANDFIX_SIGN_ID.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/BandFix2.app"
SIGN_ID="${BANDFIX_SIGN_ID:-BandFix Dev}"

swiftc -O -o bandfix2 main.swift
./bandfix2 --check

pkill -f "BandFix2.app/Contents/MacOS/bandfix2" 2>/dev/null || true

mkdir -p "$APP/Contents/MacOS"
cp bandfix2 "$APP/Contents/MacOS/bandfix2"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>bandfix2</string>
  <key>CFBundleIdentifier</key><string>local.bandfix2</string>
  <key>CFBundleName</key><string>BandFix2</string>
  <key>CFBundleDisplayName</key><string>BandFix2</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "$SIGN_ID" "$APP"
echo "installed to $APP (not launched)"
