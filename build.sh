#!/bin/zsh
# SpaceSweep.app을 빌드하고 SpaceSweep.dmg로 묶습니다.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SpaceSweep.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library \
  -target arm64-apple-macos14.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/SpaceSweep"

# 앱 아이콘: Resources/icon_1024.png → AppIcon.icns (없으면 Tools/make_icon.swift로 생성)
[ -f Resources/icon_1024.png ] || { mkdir -p Resources && swift Tools/make_icon.swift Resources/icon_1024.png; }
ICONSET=build/AppIcon.iconset && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>SpaceSweep</string>
  <key>CFBundleDisplayName</key><string>SpaceSweep</string>
  <key>CFBundleIdentifier</key><string>com.junho.spacesweep</string>
  <key>CFBundleExecutable</key><string>SpaceSweep</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Used to ask Finder to move apps that need administrator rights to the Trash.</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
</dict></plist>
EOF

# 언어별 리소스 (Mac 기본 언어에 맞춰 시스템 버튼·권한 안내문도 바뀜)
cp -R Resources/en.lproj Resources/ko.lproj "$APP/Contents/Resources/"

codesign --force --deep --sign - "$APP"

# DMG: 앱 + /Applications 바로가기
STAGE=build/dmg && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname SpaceSweep -srcfolder "$STAGE" -ov -format UDZO build/SpaceSweep.dmg >/dev/null
echo "완료: $(pwd)/build/SpaceSweep.dmg"
