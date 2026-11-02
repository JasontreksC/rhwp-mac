# macos

rhwp-mac 포크의 Swift 네이티브 앱 작업 공간이다. 구조 결정과 단계별 계획은
[macOS 네이티브 앱 아키텍처 결정](../mydocs/tech/macos_native_app_architecture.md)을 따른다.

- `Spikes/PaintOpSpike`: 0단계 스파이크. Rust 레이어 트리를 CoreGraphics/CoreText로 재생해 방식의 타당성을
  검증한다. 제품 코드가 아니며 1~4단계에서 `RhwpKit`과 렌더러로 대체된다.
- `scripts/build-xcframework.sh`: Rust 네이티브 FFI(`bindings/Native`)를 정적 XCFramework(`build/RhwpNative.xcframework`)로
  묶는다. `--smoke`를 주면 Swift로 링크해 FFI 왕복을 실행한다.
- `RhwpKit`: Rust 엔진을 Swift 6 동시성 모델로 감싼 패키지(문서 세션 actor, 레이어 트리 모델, 오류 타입).
  `scripts/test-rhwpkit.sh`로 테스트한다.
