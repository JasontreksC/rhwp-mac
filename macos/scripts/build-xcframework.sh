#!/bin/bash
# Rust 네이티브 FFI(bindings/Native)를 정적 XCFramework 로 묶는다.
#
#   사용법: macos/scripts/build-xcframework.sh [--smoke]
#   산출물: macos/build/RhwpNative.xcframework
#
# --smoke 를 주면 만든 XCFramework 를 Swift 로 링크해 FFI 왕복(열기·쪽수·레이어 트리·오류·해제)을
# 실제로 실행해 본다. 헤더 선언, 모듈맵, 링크, 소유권 규칙이 Swift 쪽에서 맞는지 확인하는 용도다.
#
# 정적 라이브러리를 쓰는 이유: macOS 27 의 dyld 는 Rust 가 만든 dylib 를 `mis-aligned LINKEDIT
# string pool` 로 거부한다(mydocs/tech/macos_native_app_architecture.md 의 0단계 발견 사항 2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$REPO_ROOT/macos/build"
XCFRAMEWORK="$BUILD_DIR/RhwpNative.xcframework"
HEADERS_STAGE="$BUILD_DIR/headers"

# Liquid Glass 때문에 앱의 최소 OS 가 26 이다. Rust 의 C 빌드 스크립트(blake3 등)가 더 높은 OS 용
# 객체를 만들어 링크 경고가 나지 않도록 **C 컴파일러 플래그로만** 같은 값을 준다.
#
# `MACOSX_DEPLOYMENT_TARGET=26.0` 을 cargo 전체에 걸면 안 된다. 그 값은 rustc 가 만드는 proc-macro
# dylib(strum_macros, snafu_derive 등)의 최소 OS 도 26 으로 바꾸는데, macOS 27 의 dyld 는 이 dylib 를
# `mis-aligned LINKEDIT string pool` 로 거부해 컴파일러가 "can't find crate" 로 실패한다.
# (캐시에 옛 dylib 가 남아 있는 동안은 드러나지 않다가, 캐시가 갱신될 때 터진다.)
# cc 크레이트는 `CFLAGS_<target>` 을 읽고 값이 바뀌면 빌드 스크립트를 다시 돌린다.
export CFLAGS_aarch64_apple_darwin="-mmacosx-version-min=26.0"
# rustup 은 keg-only 로 설치되어 PATH 에 없다.
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"

# 현재는 Apple Silicon 슬라이스 하나만 만든다. 개발 환경 호스트 빌드를 그대로 쓰므로
# 공용 target(target/pr-review)의 캐시를 재사용한다. Intel/유니버설은 배포 단계(10단계)에서 다룬다.
if [ "$(uname -m)" != "arm64" ]; then
    echo "오류: 이 스크립트는 Apple Silicon 호스트에서만 동작한다 (uname -m = $(uname -m))" >&2
    exit 1
fi

echo "==> Rust 정적 라이브러리 빌드"
(cd "$REPO_ROOT" && cargo build --locked --release -p rhwp-native-ffi --target-dir target/pr-review)
STATIC_LIB="$REPO_ROOT/target/pr-review/release/librhwp_native_ffi.a"

echo "==> 헤더와 모듈맵 준비"
# BUILD_DIR 아래의 산출물만 지운다. ${VAR:?} 는 변수가 비어 있으면 rm 이 실행되기 전에 중단시킨다.
rm -rf "${HEADERS_STAGE:?}" "${XCFRAMEWORK:?}"
mkdir -p "$HEADERS_STAGE"
cp "$REPO_ROOT/bindings/Native/include/rhwp_native.h" "$HEADERS_STAGE/"
cat > "$HEADERS_STAGE/module.modulemap" <<'MODULEMAP'
module CRhwp {
  header "rhwp_native.h"
  link "rhwp_native_ffi"
  export *
}
MODULEMAP

echo "==> XCFramework 생성"
xcodebuild -create-xcframework \
    -library "$STATIC_LIB" \
    -headers "$HEADERS_STAGE" \
    -output "$XCFRAMEWORK"
echo "생성됨: $XCFRAMEWORK"

if [ "${1:-}" = "--smoke" ]; then
    echo "==> Swift 왕복 스모크"
    SLICE="$XCFRAMEWORK/macos-arm64"
    SMOKE_BIN="$BUILD_DIR/ffi_smoke"
    # 이 SDK 의 swiftc 로 XCFramework 슬라이스를 직접 링크한다.
    xcrun swiftc -O -target arm64-apple-macos26.0 \
        "$SCRIPT_DIR/ffi_smoke.swift" \
        -I "$SLICE/Headers" -L "$SLICE" \
        -o "$SMOKE_BIN"
    "$SMOKE_BIN" "$REPO_ROOT/samples/KTX.hwp"
fi
