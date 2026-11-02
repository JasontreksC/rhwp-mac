# macos

rhwp-mac 포크의 Swift 네이티브 앱 작업 공간이다. 구조 결정과 단계별 계획은
[macOS 네이티브 앱 아키텍처 결정](../mydocs/tech/macos_native_app_architecture.md)을 따른다.

- `Spikes/PaintOpSpike`: 0단계 스파이크. Rust 레이어 트리를 CoreGraphics/CoreText로 재생해 방식의 타당성을
  검증한다. 제품 코드가 아니며 1~4단계에서 `RhwpKit`과 렌더러로 대체된다.
