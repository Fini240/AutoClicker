#!/bin/bash
# Builds AutoClicker.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP=build/AutoClicker.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library Sources/AutoClicker.swift -o "$APP/Contents/MacOS/AutoClicker"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>AutoClicker</string>
	<key>CFBundleIdentifier</key><string>local.narf.autoclicker</string>
	<key>CFBundleName</key><string>AutoClicker</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Stable identity keeps the Accessibility grant valid across rebuilds (ad-hoc would re-prompt every build)
if security find-identity -v -p codesigning | grep -q "AutoClicker Dev"; then
	codesign -s "AutoClicker Dev" --force "$APP"
else
	codesign -s - --force "$APP"
fi
echo "Built $APP"
