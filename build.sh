#!/bin/bash
set -e

cd "$(dirname "$0")"

choose_branch() {
    local current_branch selected_branch choice index
    local branches=()

    while IFS= read -r branch; do
        branches+=("$branch")
    done < <(git for-each-ref --format='%(refname:short)' refs/heads)

    current_branch="$(git branch --show-current)"

    if [ "${#branches[@]}" -le 1 ] || [ ! -t 0 ]; then
        echo "🌿 构建分支：${current_branch:-HEAD}"
        return
    fi

    echo "🌿 请选择要构建的本地分支："
    for index in "${!branches[@]}"; do
        if [ "${branches[$index]}" = "$current_branch" ]; then
            printf "  %d) %s（当前）\n" "$((index + 1))" "${branches[$index]}"
        else
            printf "  %d) %s\n" "$((index + 1))" "${branches[$index]}"
        fi
    done

    while true; do
        read -r -p "请输入序号（直接回车使用当前分支）：" choice
        if [ -z "$choice" ]; then
            selected_branch="$current_branch"
            break
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#branches[@]}" ]; then
            selected_branch="${branches[$((choice - 1))]}"
            break
        fi
        echo "⚠️  无效序号，请重新输入。"
    done

    if [ "$selected_branch" != "$current_branch" ]; then
        if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
            echo "❌ 当前工作区有未提交改动，无法安全切换分支。请先提交或使用 git stash。" >&2
            exit 1
        fi
        git switch "$selected_branch"
    fi

    echo "✅ 已选择分支：$selected_branch"
}

choose_branch

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
    <string>2.3.1</string>
    <key>CFBundleVersion</key>
    <string>2.3.1b1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
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
