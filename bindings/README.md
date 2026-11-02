# bindings

macOS 앱이 Rust 엔진을 부르는 C ABI다.

- `Native/`: `rhwp-native-ffi` 크레이트. 열린 문서를 불투명 핸들로 돌려주는 C ABI를 정적 라이브러리로 내보낸다.
  정본 헤더는 `Native/include/rhwp_native.h`이며, 선언과 실제 내보낸 심볼이 같은지 단위 테스트가 확인한다.
- Swift 쪽 소비는 `macos/RhwpKit`이 맡는다. `macos/scripts/build-xcframework.sh`가 이 크레이트를
  정적 XCFramework로 묶는다.

다른 언어용 바인딩(C#, 옛 Swift 패키지)은 이 포크의 목표가 아니어서 제거했다.
