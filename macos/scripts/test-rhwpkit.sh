#!/bin/bash
# RhwpKit 단위 테스트 실행.
#   사용법: macos/scripts/test-rhwpkit.sh [swift test 인자...]
# RhwpKit 이 의존하는 정적 XCFramework 를 먼저 (증분) 빌드한 뒤 swift test 를 실행한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/build-xcframework.sh"
swift test --package-path "$SCRIPT_DIR/../RhwpKit" "$@"
