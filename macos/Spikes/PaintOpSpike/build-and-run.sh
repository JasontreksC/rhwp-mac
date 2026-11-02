#!/bin/bash
# 0단계 스파이크 빌드/실행 스크립트.
#   사용법: build-and-run.sh <문서.hwp> <쪽번호(0부터)> <출력.png>
# Rust 정적 라이브러리는 프로젝트 규칙대로 공용 target(target/pr-review)을 재사용한다.
set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SPIKE_DIR/../../.." && pwd)"
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"

# 1) Rust FFI 정적 라이브러리 빌드 (이미 빌드되어 있으면 증분 빌드만 수행)
(cd "$REPO_ROOT" && cargo build --locked --release -p rhwp-native-ffi --target-dir target/pr-review)

# 2) 정적 라이브러리(.a)만 링크되도록 dylib 은 임시 디렉터리로 분리해 -L 로 넘긴다.
LIB_DIR="$SPIKE_DIR/.build/rustlib"
mkdir -p "$LIB_DIR"
cp "$REPO_ROOT/target/pr-review/release/librhwp_native_ffi.a" "$LIB_DIR/"

# 3) Swift 스파이크 빌드 후 실행
(cd "$SPIKE_DIR" && swift build -c release -Xlinker -L"$LIB_DIR")
"$SPIKE_DIR/.build/release/paintop-spike" "$@"
