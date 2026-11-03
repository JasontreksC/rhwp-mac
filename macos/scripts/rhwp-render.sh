#!/bin/bash
# 문서의 한 쪽을 PNG로 그리거나 레이어 트리 JSON 원문을 저장한다. 시각 검증의 입력 PNG를 만드는 도구다.
#
#   사용법: macos/scripts/rhwp-render.sh <문서> <쪽(0부터)> <출력.png|출력.json> [--scale N]
#
# Rust 정적 라이브러리는 XCFramework 빌드 스크립트가 공용 target(target/pr-review)을 재사용해 만든다.
# 이미 빌드되어 있으면 증분 빌드만 수행한다. 0단계 스파이크(build-and-run.sh)를 대체한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE="$SCRIPT_DIR/../RhwpKit"

# 1) Rust FFI 를 정적 XCFramework 로 묶는다.
"$SCRIPT_DIR/build-xcframework.sh" > /dev/null

# 2) 도구를 빌드하고 실행한다. 사용자가 준 상대 경로는 호출 위치 기준이므로 그대로 넘긴다.
swift build -c release --package-path "$PACKAGE" --product rhwp-render > /dev/null
"$PACKAGE/.build/release/rhwp-render" "$@"
