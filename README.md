# rhwp-mac

[rhwp](https://github.com/edwardkim/rhwp)를 포크해 만드는 **macOS 전용 Swift 네이티브 HWP 편집기**다.

이 저장소는 업스트림에 맥 호환 기능을 "추가"한 포크가 아니다. 웹 편집기, 브라우저·에디터 확장, CLI, 에이전트 도구,
WASM 출력을 모두 지우고 **macOS 앱이 동작하는 데 필요한 것만 남겼다.** 삭제한 것은 git 기록에서 되살릴 수 있다.

- **엔진은 Rust.** HWP·HWPX·HWP3를 읽고, 조판하고, 편집하고, 저장한다.
- **앱은 Swift.** SwiftUI·AppKit으로 만들고, UI는 macOS 기본 Liquid Glass 시스템 컴포넌트만 쓴다(최소 macOS 26).
- **Rust가 배치하고 Swift가 그린다.** Rust가 쪽마다 레이어 트리(PaintOp IR) JSON을 만들면 Swift가 CoreGraphics·
  CoreText로 그린다. 조판을 Swift에서 다시 계산하지 않는다.

## 현재 상태

| 단계 | 내용 | 상태 |
| --- | --- | --- |
| 0 | 툴체인, 렌더 방식 검증 스파이크 | 완료 |
| 1 | 핸들 기반 C ABI와 XCFramework | 완료 |
| 2 | `RhwpKit` Swift 패키지(actor 세션, 레이어 트리 모델) | 완료 |
| 정리 | 웹·CLI·에이전트 표면·문서 정리 | 완료(죽은 코드 정리는 남음) |
| 3 | 앱 셸(문서 열기, 썸네일 사이드바, 읽기 전용 뷰어) | 완료 |
| 4~10 | 렌더러, 뷰어 기능, 텍스트 편집·IME, 서식, 개체, 저장, macOS 통합 | 예정 |

전체 계획과 위험은 [macOS 네이티브 앱 아키텍처](mydocs/tech/macos_native_app_architecture.md)에 있다. 지금은 HWP·HWPX 문서를 열어
쪽 썸네일과 본문을 읽기만 하는 뷰어다(편집·저장은 이후 단계).

## 구조

```
SwiftUI/AppKit 앱
  └ RhwpKit (Swift 패키지, actor 기반 문서 세션)      macos/RhwpKit
      └ CRhwp (정적 XCFramework, C ABI)             bindings/Native
          └ Rust 엔진 (DocumentCore)                 src/, crates/
```

| 경로 | 내용 |
| --- | --- |
| `src/` | 엔진: 모델, 파서, 직렬화, 편집·질의, 조판, 레이어 트리 |
| `crates/` | OOXML 차트, 비밀번호 암호화 |
| `bindings/Native/` | 앱이 부르는 C ABI. 정본 헤더 `include/rhwp_native.h` |
| `macos/` | RHWP 앱(`App/`), Swift 패키지 `RhwpKit`(엔진 래퍼·렌더러·뷰어 로직), 빌드·시험 스크립트 |
| `samples/`, `pdf/` | 시험 문서와 같은 원본의 한컴 출력 PDF(렌더 충실도 기준) |
| `mydocs/` | 기술 문서. 지도는 [mydocs/README.md](mydocs/README.md) |

## 빌드와 시험

Rust는 Homebrew의 `rustup`을 쓴다(keg-only라 경로를 붙인다). 툴체인은 `rust-toolchain.toml`이 고정한다.

```bash
export PATH=/opt/homebrew/opt/rustup/bin:$PATH
```

엔진 시험:

```bash
CARGO_TARGET_DIR=target/pr-review cargo test --profile release-test --workspace
```

Swift 쪽(Xcode와 Swift 6.2 이상이 필요하다):

```bash
macos/scripts/build-xcframework.sh --smoke   # Rust FFI를 정적 XCFramework로 묶고 Swift로 왕복 실행
macos/scripts/test-rhwpkit.sh                # RhwpKit 단위 시험
macos/scripts/rhwp-render.sh samples/KTX.hwp 0 /tmp/ktx_p0.png   # 한 쪽을 PNG로 그리기
macos/scripts/build-app.sh --run samples/KTX.hwp                 # RHWP 앱을 빌드하고 문서를 연다(XcodeGen 필요)
```

PR 전에 돌리는 전체 검증 묶음(포맷, Clippy, 빌드, 시험 매니페스트)은 [AGENTS.md](AGENTS.md)에 있다.

## 지원하는 것

- 읽기: HWP 5.x, HWPX, HWP3, HML
- 쓰기: HWP, HWPX, HML
- 조판: 문단, 표(쪽 분할 포함), 그림·도형·글상자, 수식, 차트, 각주·미주, 머리말·꼬리말, 다단
- 편집 엔진: 글자·문단 서식, 표 편집, 개체 삽입·이동, 필드·책갈피·하이퍼링크, 찾기·바꾸기. 되돌리기용 스냅샷·역연산 기본 요소는 있고, 되돌리기 스택은 앱이 맡는다.
- 이미지·벡터: BMP, JPEG, PNG, TIFF, PCX, WMF, EMF, EPS, OLE 차트

앱에서 어디까지 보이는지는 위 단계 표를 따른다. 엔진이 지원해도 UI가 아직 없는 기능이 많다.

## 문서

- 작업 지침: [AGENTS.md](AGENTS.md), [CLAUDE.md](CLAUDE.md), [CONTRIBUTING.md](CONTRIBUTING.md)
- 기술 문서: [mydocs/README.md](mydocs/README.md)
- 서드파티 라이선스: [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)

## 고지

본 제품은 한글과컴퓨터의 한글 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

"한글", "한컴", "HWP", "HWPX"는 주식회사 한글과컴퓨터의 등록 상표입니다. 본 프로젝트는 한글과컴퓨터와 제휴, 후원,
승인 관계가 없는 독립적인 오픈소스 프로젝트입니다.

"Hangul", "Hancom", "HWP", and "HWPX" are registered trademarks of Hancom Inc. This project is an independent
open-source project with no affiliation, sponsorship, or endorsement by Hancom Inc.

## 라이선스

[MIT License](LICENSE) — Copyright (c) 2025-2026 Edward Kim. 업스트림 [edwardkim/rhwp](https://github.com/edwardkim/rhwp)의
포크이며 포크의 변경분도 같은 라이선스를 따른다.
