#!/bin/bash
# Build BandFix, install it into ~/Applications and launch it.
#
# Signed with a self-signed "BandFix Dev" identity, so Open at Login keeps
# working across rebuilds. Create it once: Keychain Access -> Certificate
# Assistant -> Create a Certificate, name "BandFix Dev", Self Signed Root, type
# Code Signing, then set its Trust for Code Signing to Always Trust. Override
# the name with BANDFIX_SIGN_ID.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/BandFix.app"
SIGN_ID="${BANDFIX_SIGN_ID:-BandFix Dev}"

swiftc -O -o bandfix main.swift
./bandfix --check

pkill -f "BandFix.app/Contents/MacOS/bandfix" 2>/dev/null || true
sleep 1

mkdir -p "$APP/Contents/MacOS"
cp bandfix "$APP/Contents/MacOS/bandfix"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>bandfix</string>
  <key>CFBundleIdentifier</key><string>local.bandfix</string>
  <key>CFBundleName</key><string>BandFix</string>
  <key>CFBundleDisplayName</key><string>BandFix</string>
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
open "$APP"
echo "installed and launched"
