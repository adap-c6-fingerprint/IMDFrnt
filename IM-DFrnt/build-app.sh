#!/bin/bash
# IM-DFrnt를 릴리즈 빌드하고 더블클릭 가능한 .app 번들로 감싼다.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="IM-DFrnt"
APP_DIR="${1:-$APP_NAME.app}"

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

# Xcode 앱 타깃과 같은 Finder 문서 연결·버전 정보를 사용한다.
cp Configuration/Info.plist "$APP_DIR/Contents/Info.plist"

echo "▸ 임시 서명(ad-hoc)"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || echo "  (서명 생략 — 실행에는 지장 없음)"

if [[ "$APP_DIR" == /* ]]; then
  APP_ABSOLUTE="$APP_DIR"
else
  APP_ABSOLUTE="$PWD/$APP_DIR"
fi
echo "✓ 완료: $APP_ABSOLUTE"
echo "  실행:   open '$APP_DIR'"
echo "  자체점검: $APP_ABSOLUTE/Contents/MacOS/$APP_NAME --selftest"
