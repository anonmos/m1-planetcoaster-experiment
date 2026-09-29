#!/bin/zsh
set -e
ROOT=/Users/tim/Workspace/gptk-steam-emulation
APP="$ROOT/build/WineCaptureProbe.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WineCaptureProbe</string>
<key>CFBundleIdentifier</key><string>com.timgrowney.WineCaptureProbe</string>
<key>CFBundleName</key><string>Wine Window Capture Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSScreenCaptureUsageDescription</key><string>Captures the display to write diagnostic frames for the Wine Steam Remote Play capture test.</string>
</dict></plist>
PLIST
xcrun swiftc -parse-as-library -O -o "$APP/Contents/MacOS/WineCaptureProbe" \
  "$ROOT/tools/steam-capture-probe/WineCaptureProbe.swift" \
  -framework AppKit -framework CoreGraphics -framework CoreMedia -framework CoreVideo -framework ScreenCaptureKit
codesign --force --sign - "$APP"
print "Built $APP"
