#!/bin/bash
# IM-DFrnt를 릴리즈 빌드하고 더블클릭 가능한 .app 번들로 감싼다.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="IM-DFrnt"
BUNDLE_ID="com.imdfrnt.prototype"
APP_DIR="$APP_NAME.app"

# xcode-select가 CommandLineTools를 가리켜도 동작하도록 Xcode 툴체인을 직접 지정한다.
XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
if [ -d "$XCODE_DEV" ]; then
  export DEVELOPER_DIR="$XCODE_DEV"
  SWIFT="$XCODE_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
else
  SWIFT="$(command -v swift)"
fi

echo "▸ 릴리즈 빌드"
"$SWIFT" build -c release

echo "▸ 번들 구성"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/IMDFrnt" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Sample/sample-floorplan.svg" "$APP_DIR/Contents/Resources/" 2>/dev/null || true

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Drawing</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSItemContentTypes</key><array><string>public.svg-image</string><string>public.png</string><string>public.jpeg</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "▸ 임시 서명(ad-hoc)"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || echo "  (서명 생략 — 실행에는 지장 없음)"

echo "✓ 완료: $(pwd)/$APP_DIR"
echo "  실행:   open '$APP_DIR'"
echo "  자체점검: ./$APP_DIR/Contents/MacOS/$APP_NAME --selftest"
