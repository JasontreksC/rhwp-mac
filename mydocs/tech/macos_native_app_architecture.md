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
   정상 동작한다. 제품은 정적 XCFramework로 간다. (기존 `bindings/swift`가 이름으로 링크하는 방식이 이
   환경에서 dylib를 고르면 같은 문제가 날 수 있으나 확인하지 않았다.)
3. **Rust 정적 라이브러리의 배포 타깃 경고.** Rust를 기본값으로 빌드하면 `blake3_neon.o`가 macOS 27.2용으로
   만들어져 최소 26.0 링크에서 경고가 난다. 1단계 빌드 스크립트는 `MACOSX_DEPLOYMENT_TARGET=26.0`을 지정한다.
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

## 단계별 PR 계획

| 단계 | 브랜치 | 내용 | 완료 기준 |
| --- | --- | --- | --- |
| 0 | `chore/macos-toolchain-spike` | 툴체인, FFI 스파이크, 렌더 방식 검증, 이 문서 | 샘플이 Swift로 그려지고 방식이 확정됨 (이 문서) |
| 1 | `feat/native-ffi-handle` | 핸들 기반 C ABI(열기·쪽수·쪽 렌더·닫기), cbindgen 헤더, XCFramework 스크립트 | Rust 테스트와 FFI 왕복 테스트 통과 |
| 2 | `feat/rhwpkit-package` | `RhwpKit`(Sendable 모델, actor 세션, 오류 타입), 레이어 트리 Codable 모델 | 샘플 열기·렌더 단위 테스트 통과 |
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
