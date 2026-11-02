---
kind: decision
status: active
canonical: mydocs/tech/macos_native_app_architecture.md
last_verified: 2026-11-02
---

# macOS 네이티브 앱 아키텍처 결정과 0단계 스파이크 결과

rhwp-mac 포크가 목표로 하는 "맥 전용 Swift 네이티브 편집기"의 구조 결정과, 그 결정을 뒷받침하는
0단계 스파이크(Rust 레이어 트리를 CoreGraphics/CoreText로 재생) 결과를 기록한다.
이후 단계의 작업 단위와 완료 기준은 [단계별 계획](#단계별-pr-계획)을 따른다.

## 결정

**Rust 엔진을 유지하고, 그 위에 SwiftUI/AppKit 네이티브 앱을 얹는다.**

- 파서·조판·편집 명령·직렬화는 Rust(`DocumentCore`)에 둔다. 약 69.5만 줄이며 한컴 호환 조판 규칙이
  쌓여 있어 Swift로 다시 쓰면 "원본의 핵심 기능 유지"와 충돌한다.
- UI, 문서 수명주기, 페이지 렌더링, 입력(IME), 인쇄/PDF, 시스템 통합은 Swift로 만든다.
- UI는 시스템 컴포넌트(Liquid Glass)만 쓴다. 직접 그리는 영역은 페이지 캔버스뿐이다.
- 최소 지원 OS는 macOS 26이다. (Liquid Glass가 26부터다.)

```
SwiftUI/AppKit 앱
  └ RhwpKit (Swift Package, Swift 6 concurrency, actor 기반 DocumentSession)
      └ CRhwp (XCFramework, 정적 라이브러리)  ← bindings/Native 확장: 핸들 기반 C ABI
          └ Rust 코어 (DocumentCore)
```

## 저장소 정리 방침

이 포크는 업스트림 rhwp에 "맥 호환을 추가"하는 것이 아니다. **macOS 네이티브 앱이 동작하는 데 필요한 것만 남긴다.**
그래서 웹 편집기·브라우저/에디터 확장·Tauri 앱·CI·CLI·에이전트 도구(MCP, 캡슐, RAG, 스킬)·WASM 전용 출력은 지운다.
남기는 것은 엔진(`model`, `parser`, `serializer`, `document_core`, `renderer`, `paint`, `wmf`·`emf`·`eps`, `ole_chart`,
`crates/*`), 앱이 쓰는 C ABI(`bindings/Native`), Swift 앱(`macos/`), 그리고 렌더 충실도 검증의 기준 자료인
`samples`·`pdf`다. 삭제는 git 기록에 남아 되살릴 수 있다.

## 0단계 스파이크

### 질문

Rust가 만드는 레이어 트리(`PageLayerTree`, PaintOp IR) JSON만으로 Swift가 한 쪽을 충실히 그릴 수 있는가?
가능하면 조판을 Swift에서 다시 계산하지 않고 "Rust가 배치, Swift가 그리기" 구조로 갈 수 있다.

### 방법

- `bindings/Native`에 `rhwp_page_layer_tree(path, page)`를 추가했다. 쪽의 레이어 트리 JSON을 돌려준다.
  스파이크용 무상태 표면이며 1단계의 핸들 기반 API로 대체된다.
- `macos/Spikes/PaintOpSpike`가 이 JSON을 읽어 CoreGraphics/CoreText로 PNG에 재생한다.
  지원 op: `pageBackground`, `textRun`, `line`, `rectangle`, `ellipse`, `path`, `image`와 `clipRect` 노드.
- 글자는 Rust가 계산한 `positions`(run 기준 글자별 x 오프셋)와 `placement.runToPage`의 원점·기준선에
  한 글자씩 놓는다. 줄 나눔·자간·장평 폭은 엔진 결과를 그대로 따르고 Swift는 글리프만 그린다.
- 기준은 한컴이 출력한 PDF(`pdf/KTX-2022.pdf`, `samples/*.pdf`; Producer `Hancom PDF 1.3.0.550`)이고,
  두 출력을 같은 96dpi×2 래스터로 맞춘 뒤 `scripts/visual_sweep.py --silhouette-only --png-pair`의
  2px 이웃 관용 내용 실루엣 일치율로 쪽별 비교했다. PDF 래스터화는 Quartz(`CGPDFDocument`)로 흰 배경에 했다.

### 결과

| 문서 | 쪽수(Rust / 한컴 PDF) | 최저 | 중앙값 | 90% 미만 쪽 |
| --- | --- | --- | --- | --- |
| `samples/KTX.hwp` | 27 / 27 | 52.0 | 93.3 | 7쪽 (1, 2, 5, 10, 12, 19, 26) |
| `samples/2022년 국립국어원 업무계획.hwp` | 35 / 35 | 66.2 | 88.6 | 22쪽 |
| `samples/21868765_별표2_보건소_분장사무.hwp` | 4 / 4 | 76.1 | — | 1쪽 (1쪽 76.1, 2~4쪽 97.1~98.9) |

- 쪽수는 세 문서 모두 일치했다. HWPX(`2025 행정업무운영 편람`, `2025년 기부·답례품 … 양식`)도 같은 경로로 그려진다.
- 쪽당 재생 시간은 약 10~90ms(릴리스 빌드, JSON 파싱 제외)다.
- 직접 판독한 3쪽(KTX 1·5쪽, 국립국어원 4쪽)의 덮어 그린 그림에서 선·박스·표 괘선·이미지·로고·
  그라데이션 막대·글줄 위치는 PDF와 겹친다. 차이는 글리프 자형과 굵기로 보인다. 한컴 글꼴(`HY헤드라인M`,
  `휴먼명조` 등)이 맥에 없어 `Apple SD Gothic Neo`/`AppleMyungjo`로 대체되기 때문이라고 추정한다.
  나머지 쪽은 직접 판독하지 않았고, 글꼴을 공급해 점수가 오르는지도 확인하지 않았다(미검증).
- 이 점수들은 **실루엣 보조값**이다. 프로젝트 기준 90%를 넘지 못한 쪽이 있으므로 이 스파이크 결과를
  렌더링 정확도 통과로 주장하지 않는다. 스파이크는 접근의 타당성만 입증한다.

### 발견 사항

1. **그라데이션 각도 규칙이 레이어 트리에 풀려 있지 않다.** `angle`만 실리고 축 방향 규칙은 Rust 정본
   (`src/renderer/mod.rs`의 `linear_gradient_axis`: 방향 = (sin θ, −cos θ), θ=90이면 좌→우)에만 있다.
   처음 위→아래로 가정해 한컴 PDF와 방향이 반대로 나왔고, 정본 규칙으로 고쳤다. 소비자마다 같은 규칙을
   복제하게 되므로 Rust가 축 좌표를 직접 내보내는 방안을 2단계에서 검토한다.
2. **dylib는 macOS 27 dyld가 거부한다.** `librhwp_native_ffi.dylib`를 `dlopen`하면
   `mis-aligned LINKEDIT string pool`로 실패한다. 정적 라이브러리(`.a`)를 Swift 링크 단계에 넣는 방식은
   정상 동작한다. 제품은 정적 XCFramework로 간다(1단계에서 구현). (기존 `bindings/swift`가 이름으로 링크하는
   방식이 이 환경에서 dylib를 고르면 같은 문제가 날 수 있으나 확인하지 않았다.)
3. **Rust 정적 라이브러리의 배포 타깃 경고.** Rust를 기본값으로 빌드하면 `blake3_neon.o`가 macOS 27.2용으로
   만들어져 최소 26.0 링크에서 경고가 난다. 1단계 빌드 스크립트는 `MACOSX_DEPLOYMENT_TARGET=26.0`을 지정하고,
   그 결과 `blake3_neon.o`의 `minos`가 26.0이 되어 경고가 사라진 것을 확인했다.
   **캐시 함정:** Cargo는 이 환경변수가 바뀌어도 `blake3`를 `Fresh`로 보고 이전 객체를 그대로 쓴다.
   그래서 이미 27.2용으로 빌드된 `target/pr-review`에서는 변수를 줘도 경고가 남는다. 새 클론은 영향이 없고,
   기존 캐시에서는 한 패키지만 무효화한다: `cargo clean -p blake3 --release --target-dir target/pr-review`
   (이후 약 3분 재빌드).
4. **미지원 op.** 4개 문서(HWP 2, HWPX 2)에서 고른 11쪽에서 건너뛴 op는 `textDecoration`과 `tabLeader`뿐이었다. SVG 타원호(`arcTo`)는
   직선으로 근사했다. 4단계 구현 범위에 포함한다.
5. **글꼴 공급이 렌더 충실도의 핵심 과제다.** Rust 조판은 글꼴 메트릭 DB로 배치하고 실제 글리프는
   대체 글꼴로 그린다([폰트 fallback 전략](font_fallback_strategy.md)). 따라서 위치는 맞고 자형만 달라진다.
   번들 가능한 글꼴 범위와 대체 규칙은 4단계에서 정한다. 한컴 글꼴 파일은 저장소에 넣지 않는다.

### 재현

```bash
macos/Spikes/PaintOpSpike/build-and-run.sh samples/KTX.hwp 0 /tmp/ktx_p0.png
```

Rust 툴체인(`rust-toolchain.toml`의 1.93.1)이 필요하다. `.json` 확장자를 주면 레이어 트리 원문만 저장한다.
비교용 PDF 래스터화와 실루엣 계산은 위 방법 절의 명령을 따른다.

## 1단계: 핸들 기반 FFI와 XCFramework

0단계의 무상태 함수(`rhwp_page_layer_tree`, 호출마다 재파싱)를 지우고, 열린 문서를 불투명 핸들로 돌려주는
C ABI로 바꿨다. 정본 구현은 `bindings/Native/src/lib.rs`, 정본 헤더는 `bindings/Native/include/rhwp_native.h`다.

| 함수 | 역할 |
| --- | --- |
| `rhwp_document_open(path, &err)` / `rhwp_document_open_bytes(data, len, &err)` | 문서를 열어 핸들을 돌려준다. 실패하면 `NULL`과 오류 JSON(`err`). 성공하면 `*err`는 `NULL` |
| `rhwp_document_page_count(doc)` | 쪽수. 널 핸들·poison된 문서는 -1 |
| `rhwp_document_page_layer_tree(doc, page)` | `{"ok":true,"pageCount":N,"page":P,"layerTree":{...}}` 또는 오류 봉투 |
| `rhwp_document_free(doc)` | 핸들 해제(널 무시) |
| `rhwp_string_free(s)` | 돌려받은 모든 문자열(`err` 포함) 해제 |

- **소유권:** 핸들과 문자열은 호출자 소유이며 각각 한 번만 해제한다. `open_bytes`는 호출 안에서 바이트를 복사한다.
- **동시성:** 핸들은 스레드 안전을 약속하지 않는다. Swift의 actor가 호출을 직렬화해야 한다. 내부 `Mutex`는
  실수로 동시에 호출해도 데이터 경쟁을 막는 안전장치다.
- **panic:** C 쪽으로 풀려나가지 않고 오류 봉투로 바뀐다. 잠금 **바깥**에서 잡기 때문에 `Mutex`가 poison되고,
  이후 호출은 손상됐을 수 있는 문서를 다시 쓰지 않고 오류를 돌려준다(문서를 다시 열어야 한다).
- **헤더:** `cbindgen` 대신 수작업 헤더를 쓰고, `header_declares_exactly_the_exported_symbols` 테스트가
  헤더 선언과 내보낸 `extern "C"` 함수 집합이 같은지 비교한다. 의존성을 늘리지 않으면서 어긋남만 막는 선택이며,
  함수가 늘어 수작업이 부담되면 `cbindgen`을 재검토한다. 선언 하나를 지워 이 테스트가 실패하는 것을 확인했다.
- **Swift 쪽 형태:** 불투명 구조체 `RhwpDocument *`는 Swift에서 `OpaquePointer`로 들어온다. 2단계의 `RhwpKit`은
  이를 `final class`/`actor`로 감싸 `deinit`에서 `rhwp_document_free`를 부른다.

`macos/scripts/build-xcframework.sh [--smoke]`가 정적 라이브러리를 `macos/build/RhwpNative.xcframework`로
묶는다(Apple Silicon 슬라이스 하나, `MACOSX_DEPLOYMENT_TARGET=26.0`). 모듈은 `CRhwp`이며 `--smoke`는 이
XCFramework를 Swift로 링크해 열기·쪽수·레이어 트리·범위 밖 오류·바이트 열기·널 처리를 실제로 실행한다
(`macos/scripts/ffi_smoke.swift`). 스파이크도 이제 이 XCFramework를 SwiftPM `binaryTarget`으로 소비하며,
0단계와 같은 샘플 쪽을 픽셀 단위로 동일하게 그린다.

범위 밖(후속 단계): 암호 걸린 문서(`from_bytes_with_password`)·편집·저장 API, Intel/유니버설 슬라이스(10단계).

## 2단계: RhwpKit Swift 패키지

`macos/RhwpKit`(Swift 6.2, macOS 26, Swift 6 언어 모드)이 1단계 XCFramework(`binaryTarget` `CRhwp`)를 감싼다.
테스트는 `macos/scripts/test-rhwpkit.sh`(XCFramework를 증분 빌드한 뒤 `swift test`)로 실행한다.

**공개 API**

| 타입 | 역할 |
| --- | --- |
| `RhwpDocumentSession` (actor) | `open(contentsOf:)`, `open(data:)`, `pageCount()`, `layerTree(page:)`, `layerTreeJSON(page:)` |
| `PageLayerTree` / `LayerNode` / `GroupKind` | 한 쪽의 레이어 트리 Decodable 모델 |
| `PaintOp` 및 `TextRunOp`, `RectangleOp`, `ImageOp` 등 | 그리기 명령. 모르는 op는 `.unsupported(type:)`로 보존 |
| `RhwpError` | `openFailed`, `pageOutOfRange`, `documentUnavailable`, `native`, `malformedResponse` |

**설계 결정**

- **문서마다 전용 직렬 큐 위의 actor.** 모든 네이티브 호출이 한 스레드에서 일어나고 협력 스레드 풀을 막지 않는다.
  파싱도 같은 큐에서 한다. `dispatchPrecondition(.onQueue)`로 실행자 연결이 빠지면 즉시 멈추게 했다.
  Rust 쪽이 스레드를 옮겨도 결과가 같음을 1단계에서 보장했으므로 이 구조가 그 계약에 기대는 것은 아니다.
- **핸들 수명은 Swift 참조 수명에 묶는다.** `NativeDocumentHandle`이 마지막 참조가 사라질 때 `rhwp_document_free`를 부른다.
- **파일은 Swift에서 읽어 `open_bytes`로 넘긴다.** 샌드박스·파일 코디네이션과 맞고, 읽기 실패를 Swift 오류로 보고한다.
- **구분이 필요한 오류만 전용 케이스로 만든다.** 범위 밖 쪽은 Swift에서 먼저 검사해 `pageOutOfRange`로 돌려주고,
  엔진 메시지(사람이 읽는 문장)는 문자열로 분기하지 않고 `.native`로 전달한다.
- **스키마가 바뀌면 크게 실패한다.** 주 버전·좌표계(`page-top-left-y-down`)·단위(`px`)가 다르면 잘못 그리는 대신
  디코딩이 `malformedResponse`로 실패한다. 반대로 열거형의 모르는 값(`StrokeDash` 등)은 안전한 기본값으로 낮춘다.
- **글자 위치 계약을 모델에 문서화했다.** `TextRunOp.positions[i]`는 run 원점에서 i번째 유니코드 스칼라의 시작 x이고
  개수는 스칼라 수 + 1이다. 렌더러는 줄 나눔·자간을 다시 계산하지 않는다. `displayText`가 있으면 그것을 그린다.
- **그라데이션 축 규칙은 `Gradient.linearAxis(in:)`에 한 번만 구현했다.** 0단계에서 방향을 잘못 가정했던 규칙이다.

**검증**

- 18건의 Swift Testing 단위 테스트가 통과한다. 기대값은 한컴 PDF(KTX 27쪽, 보건소 4쪽)와 A4 규격(793.70×1122.52px)처럼
  엔진과 독립인 값으로 정했다. 모든 쪽에서 op 종류별 개수를 원본 JSON을 `JSONSerialization`으로 따로 센 값과 대조한다.
- 일부러 결함을 넣어 테스트가 실패하는지 확인했다: leaf의 마지막 op 누락, `positions` 마지막 값 누락, 그라데이션 y 부호 반전,
  좌표계 검사 제거. 모두 검출됐고 원본은 복원했다.
- 임시 스윕(커밋하지 않음): 6MB 이하 샘플 문서 364개의 앞 4쪽씩 847쪽을 디코딩해 실패 0건이었다.
  열기에 실패한 3건은 모두 암호 문서(`*password-123456*`)이며 `openFailed`로 돌아온다(암호 입력 API는 후속 단계).

**샘플에서 관찰된 op 종류와 모델 상태**

| 상태 | op |
| --- | --- |
| 모델링·실데이터 확인 | `pageBackground`, `textRun`, `line`, `rectangle`, `ellipse`(`hwp3-curve.hwp`), `path`(`KTX.hwp` 2쪽), `image` |
| 보존만 함(`.unsupported`) — 4단계 렌더러 범위 | `textDecoration`, `tabLeader`, `charOverlap`, `equation`, `footnoteMarker`, `formObject`, `glyphOutline`, `rawSvg` |

**알려진 사항**

- 일부 문서를 열 때 엔진이 `LAYOUT_OVERFLOW: ...`를 stderr에 찍는다(진단 출력). API로는 끌 수 없으며 필요하면 Rust 쪽 변경이 필요하다.
- 디코딩은 actor의 전용 큐에서 동기로 한다. 디버그 빌드에서 약 80쪽을 파싱·디코딩하는 데 0.5초라 지금은 문제 없지만,
  큰 쪽(base64 그림)의 디코딩을 큐 밖으로 옮길지는 4단계에서 릴리스 빌드로 측정해 정한다.
- 미검증: 릴리스 빌드 성능, Xcode 앱 프로젝트에서의 패키지 소비, 이미지 `crop`·`fillMode`의 의미(필드만 모델링).

## 단계별 PR 계획

| 단계 | 브랜치 | 내용 | 완료 기준 |
| --- | --- | --- | --- |
| 0 | `chore/macos-toolchain-spike` | 툴체인, FFI 스파이크, 렌더 방식 검증, 이 문서 | 샘플이 Swift로 그려지고 방식이 확정됨 (이 문서) |
| 1 | `feat/native-ffi-handle` | 핸들 기반 C ABI(열기·쪽수·쪽 렌더·닫기), C 헤더와 일치 테스트, XCFramework 스크립트 | Rust 테스트와 Swift FFI 왕복 스모크 통과 |
| 2 | `feat/rhwpkit-package` | `RhwpKit`(Sendable 모델, actor 세션, 오류 타입), 레이어 트리 Decodable 모델 | 샘플 열기·디코딩 단위 테스트 통과 |
| 3 | `feat/app-shell` | Xcode 프로젝트, `DocumentGroup`, HWP/HWPX 열기, 쪽 썸네일 사이드바, 읽기 전용 뷰어 | 문서가 열리고 스크롤됨 |
| 4 | `feat/page-renderer` | 타일링 렌더러, 글꼴 공급, 미지원 op 보강 | 샘플 세트의 쪽별 일치율이 자동 측정됨 |
| 5 | `feat/viewer-features` | 찾기, 이동, 개요, 책갈피, 하이퍼링크, 다크 모드 | 뷰어 기능 패리티 |
| 6 | `feat/text-editing` | 캐럿·선택, IME, 입력·삭제, 실행 취소, 클립보드 | 한글 조합 입력과 저장 후 재열기 확인 |
| 7 | `feat/formatting-inspector` | 글자·문단 모양, 스타일, 쪽 설정(인스펙터·시트) | 서식 변경이 렌더에 반영 |
| 8 | `feat/objects-editing` | 표, 그림, 도형, 수식, 차트 편집 | 개체 삽입·이동·크기 조절 |
| 9 | `feat/save-export` | HWP/HWPX 저장, PDF, 텍스트·마크다운, 인쇄 | 라운드트립 검증 |
| 10 | `feat/mac-integration` | Quick Look, Spotlight, App Intents, 서비스, 샌드박스, 서명·공증, 현지화 | 배포 가능한 빌드 |

## 위험과 미해결

- **한글 IME**: 가장 어려운 부분이다. 6단계 첫 작업으로 스파이크한다.
- **렌더 충실도**: 위 결과대로 글꼴이 지배적이다. 4단계에서 글꼴 공급 방안을 정하고 90% 기준을 재측정한다.
- **편집 후 증분 렌더**: 스파이크는 쪽마다 문서를 다시 파싱했다. 핸들 기반 API에서 편집 후 쪽 단위
  무효화와 레이어 트리 캐시를 쓰는 경로(`wasm_api`가 이미 사용 중)를 따라야 한다.
- **Rust 조판 변경**: 조판을 건드리게 되면 저장소의 Visual Sweep·90% 게이트가 그대로 적용된다.
  이 포크의 Swift 작업은 가능한 한 Rust 조판 코드를 수정하지 않는다.
- **라이선스**: 번들 글꼴과 한컴 글꼴 취급은 10단계 이전에 확인한다.
