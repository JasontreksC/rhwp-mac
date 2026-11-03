# rhwp-mac 작업 지침

이 파일은 이 저장소에서 일하는 사람과 에이전트가 따르는 단일 지침이다. `CLAUDE.md`는 이 파일을 불러오고
Claude Code에 해당하는 보충만 적는다. 더 구체적인 문서가 있으면 그 문서를 따른다.

## 프로젝트

rhwp-mac은 [rhwp](https://github.com/edwardkim/rhwp)를 포크해 **macOS 전용 Swift 네이티브 HWP 편집기**로 다시 만드는
저장소다. 업스트림에 맥 호환을 "추가"하는 것이 아니라 **macOS 앱이 동작하는 데 필요한 것만 남긴다.**

- 엔진(Rust): HWP·HWPX·HWP3 파싱, 조판, 편집, 저장. 문서 하나를 `DocumentCore`가 소유한다.
- 앱(Swift): SwiftUI·AppKit. UI는 macOS 기본 Liquid Glass 시스템 컴포넌트만 쓴다(최소 macOS 26).
- 경계: "Rust가 배치하고 Swift가 그린다". Rust가 쪽마다 레이어 트리(PaintOp IR) JSON을 만들면 Swift가
  CoreGraphics·CoreText로 그린다. Swift에서 조판을 다시 계산하지 않는다.
- 결정과 단계별 계획: [macOS 네이티브 앱 아키텍처](mydocs/tech/macos_native_app_architecture.md)

```
SwiftUI/AppKit 앱                                    macos/App (화면만)
  └ RhwpViewer·RhwpRender (뷰어 로직·렌더러)           macos/RhwpKit
  └ RhwpKit (Swift 패키지, actor 기반 문서 세션)      macos/RhwpKit
      └ CRhwp (정적 XCFramework, C ABI)             bindings/Native → macos/scripts/build-xcframework.sh
          └ Rust 엔진 (DocumentCore)                 src/, crates/
```

## 저장소 지도

| 경로 | 내용 |
| --- | --- |
| `src/` | 엔진: `model`, `parser`, `serializer`, `document_core`(편집·질의), `renderer`(조판), `paint`(레이어 트리), `document_api`(`HwpDocument` 파사드), `wmf`·`emf`·`eps`, `ole_chart` |
| `crates/` | `rhwp-ooxml-chart`, `rhwp-password-crypto` |
| `bindings/Native/` | 앱이 부르는 C ABI(`rhwp-native-ffi`). 정본 헤더 `include/rhwp_native.h` |
| `macos/` | Swift 작업 공간: 앱(`App/`), 패키지 `RhwpKit`(`RhwpRender`, `RhwpViewer` 포함), 빌드·테스트 스크립트 |
| `samples/`, `pdf/` | 시험 문서와 같은 원본의 **한컴 출력 PDF**(렌더 충실도의 기준) |
| `template/`, `saved/`, `ttfs/`, `assets/` | 빈 문서 틀, 저장 왕복 기준 파일, 재배포 가능한 글꼴, 글꼴 규칙 데이터·로고 |
| `tests/` | 통합 시험. 새 시험은 `tests/cases/`에만 둔다 |
| `scripts/` | 시험 묶음 정책(`rust-test-*`, `rust-unit-test-tiers`)과 `visual_sweep.py` |
| `mydocs/` | 기술 문서. 지도는 [mydocs/README.md](mydocs/README.md) |

## 작업 절차

- 작업 한 단위는 **브랜치 → 작업 → PR**이다. 브랜치는 최신 `main`에서 만들고 이름은 `feat/…`, `fix/…`,
  `refactor/…`, `chore/…`, `docs/…`, `test/…` 형식을 쓴다.
- 커밋과 PR 메시지는 **한국어**로 쓴다. 커밋은 `type(scope): 제목` 형식(Conventional Commits)을 따르고, 본문에는
  무엇을 왜 바꿨는지 적는다. 에이전트가 만든 커밋 끝에는 환경이 정한 `Co-Authored-By` 줄을 붙인다.
- PR 본문은 **개요 / 변경 내용 / 검증 / 알려진 사항** 순서로 쓴다. 검증에는 실제로 실행한 명령과 결과, 실행하지
  않았거나 확인하지 못한 항목을 구분해 적는다. 통과하지 못한 것을 숨기지 않는다.
- **소스를 고칠 때는 주석을 충분히 남긴다.** 코드가 하는 일보다 그렇게 한 이유와 깨지기 쉬운 전제를 적는다.
- push, PR 생성·병합, 외부 서비스 게시는 사용자가 맡긴 범위 안에서만 한다. 사용자나 다른 도구가 만든 변경을
  되돌리거나 지우지 않는다.
- 구현 전에 관련 기존 시험과 [mydocs 지도](mydocs/README.md)의 기술 문서를 확인한다.

## 빌드와 검증

Homebrew의 `rustup`은 keg-only라 명령마다 경로를 붙인다. 툴체인은 `rust-toolchain.toml`(1.93.1)이 고정한다.

```bash
export PATH=/opt/homebrew/opt/rustup/bin:$PATH
```

**공용 target 디렉터리.** 로컬 Rust 빌드와 시험은 `target/pr-review`를 쓰고 이슈별 `target/<이름>`을 새로 만들지
않는다. 공유 캐시이므로 임의로 지우거나 초기화하지 않는다.

**Rust 변경 검증 묶음.** Rust 소스나 시험을 바꾼 모든 PR은 push 전에 아래를 순서대로 모두 통과시킨다. 기준
SHA는 `git fetch origin main` 뒤의 `origin/main`이다.

```bash
base="$(git rev-parse origin/main)"
node scripts/rust-test-suite-manifest.mjs --prepare
cargo fmt --all -- --check
cargo clippy --locked --target-dir target/pr-review -- -D warnings
cargo build --locked --workspace --target-dir target/pr-review
cargo clippy --locked --workspace --all-targets --target-dir target/pr-review -- -D warnings
node scripts/rust-test-suite-manifest.mjs --check --base-ref "$base"
node scripts/rust-unit-test-tiers.mjs --check --base-ref "$base"   # src 의 #[cfg(test)] 를 바꿨을 때
cargo test --locked --profile release-test --workspace --no-fail-fast --target-dir target/pr-review
```

- 새 통합 시험은 `tests/cases/`에 원본만 추가한다. `--prepare`가 만드는 `tests/generated/`는 git이 무시하며
  커밋하지 않는다.
- 이 저장소에는 CI가 없다. 위 결과는 로컬 실행이므로 PR 본문에 검증한 커밋 SHA와 함께 적는다. 검증 뒤에 코드를
  바꿨다면 이전 결과를 쓰지 않고 다시 실행한다.
- 스크립트 시험: `node --test scripts/tests/*.test.mjs`,
  `python3 -m unittest scripts/tests/test_visual_sweep.py scripts/tests/test_visual_sweep_font_exception.py`

**Swift·FFI 변경 검증.**

```bash
macos/scripts/build-xcframework.sh --smoke   # Rust FFI → 정적 XCFramework → Swift 로 링크해 왕복 실행
macos/scripts/test-rhwpkit.sh                # Swift 패키지 단위 시험(RhwpKit, RhwpRender, RhwpViewer)
macos/scripts/build-app.sh                   # 앱 빌드(XcodeGen 필요). 앱을 바꿨다면 경고 없이 빌드되는지 본다
```

C ABI(`bindings/Native`)를 바꾸면 헤더와 실제 내보낸 심볼이 같은지 확인하는 단위 시험이 함께 돈다. 열린
문서는 불투명 핸들이고, Rust가 돌려준 문자열은 반드시 `rhwp_string_free`로 해제한다.

## 시각 검증

렌더링·조판을 바꾸면 같은 원본의 **한컴 PDF**와 실제 출력을 같은 쪽에서 직접 비교한다. 페이지 수, 텍스트 추출,
해시, 자동 점수만으로 통과를 선언하지 않는다.

- 기준: `samples/`·`pdf/`의 한컴 출력 PDF. 쪽 이미지는 Quartz 등으로 흰 배경에 래스터한다.
- 도구: `scripts/visual_sweep.py`(`--silhouette-only --png-pair`)로 2px 이웃 관용 내용 실루엣 일치율을 낸다.
  Swift 렌더러가 만든 PNG는 `macos/scripts/rhwp-render.sh <문서> <쪽> <출력.png>`로 얻는다.
- 샘플 전체의 쪽별 일치율은 `macos/scripts/fidelity-sweep.py --discover --pages 1-6`가 자동으로 잰다(문서·한컴 PDF 쌍 589개, 약 2.5분).
  렌더러를 바꾸면 전후 수치를 같은 명령으로 비교해 PR에 적고, 나빠진 쪽은 원인을 가려 적는다(평균만으로 통과를 선언하지 않는다).
- 일치율이 어느 쪽이든 **90% 미만**이거나 측정할 수 없으면 새 회귀 시험이나 기준 파일(golden)을 추가하지 않고
  출력을 먼저 개선한다. 정확히 90%는 통과다. 전체 쪽수가 한컴 PDF와 다르면 점수와 무관하게 원인을 찾는다.
- 한컴 글꼴은 이 Mac에 없고 번들하지 않는다. 글꼴은 대체 표(`macos/RhwpKit/Sources/RhwpRender/FontSubstitution.swift`)로 푸는데,
  후보를 바꿔도 ±0.1점이라 글꼴은 남은 차이의 지렛대가 아니다. 글꼴 때문인 차이와 배치 결함을 구분해 적는다. 표 괘선·문단 시작·그림 경계가 어긋나면 글꼴과 무관한 배치
  결함이다.
- 기준 PDF를 새로 만들어야 하면 [한컴 변환 사용법](mydocs/manual/mcp_hwp2024Convert_usage.md)과
  [시각 검증 지도](mydocs/manual/verification/README.md)를 본다. 이 절차에 쓰인 CLI·WASM 경로는 이 포크에서
  지웠으므로, 도구 이름이 낡았으면 원리만 따른다.

## 조판·렌더링 수정 원칙

엔진의 조판을 고칠 때 아래를 지킨다. 기대값은 구현 결과가 아니라 **사양, 유효한 한컴 출력, 독립적인 기존 계약**에서
정한다.

**근거와 범위**
- 수정 전에 위반된 조판 규칙, 독립 근거, 원인 계층과 반례를 짧게 정리한다.
- 특정 문서 ID·수치·우연한 속성 조합으로 화면을 맞추는 예외를 넣지 않는다. 새 분기는 조판 규칙상 필요한 조건과
  적용되면 안 되는 사례를 설명할 수 있어야 한다. 잘못된 좌표를 clamp하거나 출력을 숨겨 겹침만 없애는 것은
  원인 해결이 아니다.

**측정과 배치는 같은 결과를 쓴다**
- 측정과 실제 배치는 같은 줄 구성·메트릭 결과를 소비한다. 각 단계가 줄 소속을 따로 추측하지 않는다.
- `treat_as_char`는 글줄 흐름에 참여한다는 속성이지 "문단의 모든 표가 한 줄에 있다"는 뜻이 아니다. 유효한 저장
  `LineSeg`를 쓰는 경로는 줄 소속·위치를 보존하고, 재조판 경로는 텍스트와 개체의 순서·개행·가용 너비·바깥 여백으로
  줄 소속을 정한다.
- 줄 높이는 그 줄 요소들의 기준선 정렬과 여백을 포함한 점유 영역이다. 같은 줄의 표 높이를 합산하거나 선언 높이의
  최댓값만으로 정하지 않는다.

**좌표·높이를 바꿀 때는 소비 지점까지 따라간다**
- 값 하나를 골라 `생산 → 측정의 소비 → 배치의 소비 → 최종 원점·높이를 바꾸는 분기`를 코드 위치로 추적한다. 같은
  helper를 불러도 그 뒤에 별도 앵커 선택·덮어쓰기·clamp가 있으면 결과가 공유된 것이 아니다.
- 글자가 보이는지, 줄이 공간을 점유하는지, 개체가 흐름을 전진시키는지는 서로 다른 상태다. 빈 문자열이나 공백만
  있는 문단도 유효한 줄 상자를 가질 수 있다. 한 상태를 다른 상태의 대용으로 쓰는 조건이 있으면 두 상태가 갈리는
  입력을 먼저 시험한다.

**분할·이어받기(pagination, rowspan, clipping, continuation)**
- 공통 helper의 이름이나 반환형만으로 공통 결과라고 판정하지 않는다. 일반·특수 분기마다 `시작·끝 컷과 소유 유닛 →
  요구 높이 → 누적 예약 높이 → 예산 실패 시 컷·이월 → 실제 배치`를 코드 위치로 대조한다.
- 이미 소비한 내용과 물리 공간을 구분한다. 내용 컷으로 표현되지 않는 빈 밴드, 패딩, 행 간격을 어디서 계상하는지
  확인한다. 앞 조각의 끝과 다음 조각의 시작에서 유닛 누락·중복, 표 외곽·뒤 문단, 불필요한 빈 쪽이 없어야 한다.

**저장된 조판 정보(LineSeg·폭·캐시)**
- 수용 조건을 바꾸기 전에 입력이 실제 저장본인지 수동으로 만든 합성 입력인지 확인한다. 수동 메타데이터만으로 수용
  조건을 완화하지 않는다. 저장 정보 재사용과 편집 뒤 재조판은 각각의 계약으로 검증한다.

**증거와 기준값**
- 합성 입력의 계약 시험과 정상 한컴 문서·출력 증거를 구분한다. 자료가 없는 사례는 "미검증"으로 남긴다.
- 시험 통과를 목적으로 baseline·golden·허용치를 완화하지 않는다. 바꿔야 하면 전후 값, 독립 기준 출력, 의도한
  변화의 근거를 따로 제시한다. 원인을 모르는 증가분을 기준값 갱신으로 숨기지 않는다.
- 결함 검출을 주장하는 회귀 시험은 수정 전 코드에서 의도한 원인으로 실패하고 수정 후 통과해야 한다. 빌드 실패는
  결함 재현으로 세지 않는다. fixture가 없을 때 조용히 `return`하거나 실행 대상이 0건인 결과를 증거로 삼지 않는다.
- 위치·모양은 절대 픽셀이나 전체 SVG 해시로 고정하지 않는다. 셀 내부 포함, 앞뒤 순서, 겹침 같은 관계를 검사하고
  실제 모양은 한컴 PDF와의 시각 비교로 확인한다.

## 파서·저장·모델

- `null`, 빈 문자열, 0, 참조 번호를 구별한다. 길이는 바이트와 UTF-16 코드 유닛을 혼동하지 않는다. 재귀 깊이와
  자원 한도를 두고, 저장 뒤 다시 열었을 때 값이 보존되는지(round-trip) 확인한다.
- 한 번만 처리할 데이터는 실제 소유 범위에서 한 번 처리한다. 내부 반복문마다 초기화하지 않는다.
- 모든 포맷 파서는 공통 `Document` IR을 돌려준다. HWP3 전용 해석은 `src/parser/hwp3/`에서 끝내고 렌더러·레이아웃·
  문서 코어에 HWP3 전용 분기를 추가하지 않는다([파서 아키텍처](mydocs/tech/parser_architecture.md)).
- 차트가 OLE 컨테이너에 있어도 편집 가능한 `c:chartSpace`가 있으면 일반 OOXML 차트 경로로 그린다. 미리보기는
  값·레이블의 정본이 아니다([차트 OLE 경계](mydocs/tech/chart_ole_v1_boundary.md)).

## 완료 보고

- 구현 주장마다 `적용·비적용 경로 → 독립 기대값 → 실제 검사 항목 → 수정 전후 관측값`을 연결한다. 증거가 없는
  경로는 미검증으로 남긴다.
- 검증한 커밋 SHA, 실행한 명령과 결과, 실행하지 않은 항목을 구분한다. 부분 해결이면 이슈 전체를 닫지 않는다.
- 로컬 검증 완료와 병합 승인은 다른 일이다. 사용자의 승인이 있기 전에 병합하지 않는다.
