#!/bin/bash
# RHWP 앱을 빌드한다(임시 서명, Debug).
#
#   사용법: macos/scripts/build-app.sh [--run <문서>]
#   산출물: macos/build/DerivedData/Build/Products/Debug/RHWP.app
#
# 1) Rust FFI 를 정적 XCFramework 로 묶고, 2) XcodeGen 으로 프로젝트를 만든 뒤, 3) xcodebuild 로 빌드한다.
# `--run <문서>` 를 주면 빌드 뒤 그 문서를 앱으로 연다. XcodeGen 은 `brew install xcodegen` 으로 설치한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/../App"
DERIVED="$SCRIPT_DIR/../build/DerivedData"

command -v xcodegen > /dev/null || { echo "오류: xcodegen 이 없습니다. brew install xcodegen" >&2; exit 1; }

"$SCRIPT_DIR/build-xcframework.sh" > /dev/null
(cd "$APP_DIR" && xcodegen generate --spec project.yml --quiet)
xcodebuild -project "$APP_DIR/RHWP.xcodeproj" -scheme RHWP -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" build | tail -n 3

APP="$DERIVED/Build/Products/Debug/RHWP.app"
echo "앱: $APP"

if [ "${1:-}" = "--run" ]; then
    [ -n "${2:-}" ] || { echo "사용법: build-app.sh --run <문서>" >&2; exit 1; }
    open -a "$APP" "$2"
fi
