#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
APP="$PWD/dist/Grove.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Notices"
cp "$BIN_DIR/Grove" "$APP/Contents/MacOS/Grove"
cp LICENSE "$APP/Contents/Resources/LICENSE"
find "$APP/Contents/Resources/Notices" -type f -exec chmod u+w {} +
cp Notices/* "$APP/Contents/Resources/Notices/"
cp scripts/grove "$APP/Contents/Resources/grove"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Grove</string>
<key>CFBundleIdentifier</key><string>local.grove.workspace</string>
<key>CFBundleName</key><string>Grove</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>local.grove.workspace</string><key>CFBundleURLSchemes</key><array><string>grove</string></array></dict></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
