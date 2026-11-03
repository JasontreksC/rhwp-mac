# macos

rhwp-mac 포크의 Swift 네이티브 앱 작업 공간이다. 구조 결정과 단계별 계획은
[macOS 네이티브 앱 아키텍처 결정](../mydocs/tech/macos_native_app_architecture.md)을 따른다.

- `App/`: RHWP 앱(SwiftUI). `project.yml`(XcodeGen)에서 프로젝트를 만든다. 화면만 두고 로직은 패키지에 둔다.
- `RhwpKit/`: Swift 패키지 하나에 라이브러리 셋과 도구 하나가 들어 있다.
  - `RhwpKit`: Rust 엔진을 Swift 6 동시성 모델로 감싼다(문서 세션 actor, 쪽 크기, 레이어 트리 모델, 오류 타입).
  - `RhwpRender`: 레이어 트리(PaintOp IR)를 CoreGraphics/CoreText로 그리는 렌더러. 쪽 전체(`render`) 또는 비트맵의 한 영역(`renderTile`, `TileGrid`)을 그린다. 엔진을 부르지 않는다.
  - `RhwpViewer`: 뷰어 로직과 모델(확대 단계, 쪽 세로 배치, 렌더 배율 정책, 타일 계획, 레이어 트리·타일 캐시, 핀치 상태, 확대 앵커, 문서 열기). UI 프레임워크에 의존하지 않는다.
  - `rhwp-render`: 한 쪽·전체 쪽을 PNG로 그리거나(`--all`, `--pages`, `--json`) 한컴 PDF를 같은 배율의 PNG로 래스터하고(`--pdf`) 쪽마다 엔진·디코딩·렌더 시간을 재는(`--bench`, 릴리스 빌드로) 명령줄 도구.
- `scripts/build-xcframework.sh`: Rust 네이티브 FFI(`bindings/Native`)를 정적 XCFramework(`build/RhwpNative.xcframework`)로
  묶는다. `--smoke`를 주면 Swift로 링크해 FFI 왕복을 실행한다.
- `scripts/test-rhwpkit.sh`: XCFramework를 만든 뒤 패키지의 시험 전체를 돌린다.
- `scripts/rhwp-render.sh <문서> <쪽> <출력.png|출력.json> [--scale N]`: 시각 검증의 입력 PNG를 만든다.
- `scripts/fidelity-sweep.py --discover --pages 1-6`: 샘플 문서와 한컴 PDF 쌍의 쪽별 실루엣 일치율을 자동으로 잰다(결과는 `output/fidelity/`).
- `scripts/build-app.sh [--run <문서>]`: XCFramework → XcodeGen → xcodebuild(임시 서명, Debug)로 앱을 빌드한다. `--run`을 주면 그 문서를 연다.
