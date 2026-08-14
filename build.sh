#!/bin/bash
set -e

echo "🔨 正在编译 macOS F50 Monitor 菜单栏程序..."
swift build -c release

APP_DIR="F50 Monitor.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp .build/release/F50Monitor "$MACOS_DIR/F50Monitor"
if [ -f "Sources/F50Monitor/AppIcon.icns" ]; then
    cp Sources/F50Monitor/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
fi
for logo in Sources/F50Monitor/China*Logo.svg Sources/F50Monitor/China*Logo.png; do
    [ -f "$logo" ] || continue
    cp "$logo" "$RESOURCES_DIR/$(basename "$logo")"
done

cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>F50Monitor</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.f50.monitor</string>
    <key>CFBundleName</key>
    <string>F50 Monitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5.0</string>
    <key>CFBundleVersion</key>
    <string>1.5.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

chmod +x "$MACOS_DIR/F50Monitor"
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [ -d "/Applications/$APP_DIR" ]; then
    rm -rf "/Applications/$APP_DIR"
fi
cp -R "$APP_DIR" "/Applications/$APP_DIR"

echo "✅ 构建完成！已自动更新至 /Applications/$APP_DIR"

echo "🔄 正在重启 F50 Monitor..."
killall F50Monitor 2>/dev/null || true
sleep 0.5
open "/Applications/$APP_DIR"

