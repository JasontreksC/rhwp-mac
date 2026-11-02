#!/bin/bash
# 0단계 스파이크 빌드/실행 스크립트.
#   사용법: build-and-run.sh <문서.hwp> <쪽번호(0부터)> <출력.png|출력.json>
# Rust 정적 라이브러리는 XCFramework 빌드 스크립트가 공용 target(target/pr-review)을 재사용해 만든다.
set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1) Rust FFI 를 정적 XCFramework 로 묶는다 (이미 빌드되어 있으면 증분 빌드만 수행)
"$SPIKE_DIR/../../scripts/build-xcframework.sh"

# 2) Swift 스파이크 빌드 후 실행
(cd "$SPIKE_DIR" && swift build -c release)
"$SPIKE_DIR/.build/release/paintop-spike" "$@"
