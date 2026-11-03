# macos

rhwp-mac 포크의 Swift 네이티브 앱 작업 공간이다. 구조 결정과 단계별 계획은
[macOS 네이티브 앱 아키텍처 결정](../mydocs/tech/macos_native_app_architecture.md)을 따른다.

- `RhwpKit/`: Swift 패키지 하나에 라이브러리 셋과 도구 하나가 들어 있다.
  - `RhwpKit`: Rust 엔진을 Swift 6 동시성 모델로 감싼다(문서 세션 actor, 쪽 크기, 레이어 트리 모델, 오류 타입).
  - `RhwpRender`: 레이어 트리(PaintOp IR)를 CoreGraphics/CoreText로 그리는 렌더러. 엔진을 부르지 않는다.
  - `RhwpViewer`: 뷰어 로직(확대 단계, 쪽 세로 배치, 렌더 배율 정책, 캐시). UI 프레임워크에 의존하지 않는다.
  - `rhwp-render`: 한 쪽을 PNG로 그리는 명령줄 도구.
- `scripts/build-xcframework.sh`: Rust 네이티브 FFI(`bindings/Native`)를 정적 XCFramework(`build/RhwpNative.xcframework`)로
  묶는다. `--smoke`를 주면 Swift로 링크해 FFI 왕복을 실행한다.
- `scripts/test-rhwpkit.sh`: XCFramework를 만든 뒤 패키지의 시험 전체를 돌린다.
- `scripts/rhwp-render.sh <문서> <쪽> <출력.png|출력.json> [--scale N]`: 시각 검증의 입력 PNG를 만든다.
