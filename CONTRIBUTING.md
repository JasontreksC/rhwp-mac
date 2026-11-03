# 기여 안내

rhwp-mac은 [rhwp](https://github.com/edwardkim/rhwp)를 포크해 만드는 macOS 전용 네이티브 편집기다. 방향과 범위는
[README](README.md)와 [macOS 네이티브 앱 아키텍처](mydocs/tech/macos_native_app_architecture.md)를 먼저 읽는다.
작업 규칙의 정본은 [AGENTS.md](AGENTS.md)이며, 이 문서는 기여 흐름만 요약한다.

## 무엇을 받는가

- 받는다: macOS 앱(Swift), C ABI, `RhwpKit`, 그리고 앱이 쓰는 엔진 동작(파싱·조판·편집·저장)의 수정.
- 받지 않는다: 웹 편집기, 브라우저·에디터 확장, CLI, 에이전트 도구, WASM 출력처럼 이 포크가 지운 표면의 복구.
  이런 것은 업스트림 [edwardkim/rhwp](https://github.com/edwardkim/rhwp)의 영역이다.
- 엔진의 조판·파싱 결함은 업스트림과 공통이다. 업스트림에서 고쳐지면 이 포크로 가져오는 편이 낫다.

## 작업 흐름

1. 최신 `main`에서 브랜치를 만든다. 이름은 `feat/…`, `fix/…`, `refactor/…`, `chore/…`, `docs/…`, `test/…`.
2. 작업하고 소스에는 주석을 충분히 남긴다(왜 그렇게 했는지와 깨지기 쉬운 전제).
3. 아래 검증을 마친 뒤 PR을 연다.

커밋과 PR은 **한국어**로 쓴다. 커밋 제목은 `type(scope): 제목` 형식이다.

```
fix(layout): 쪽을 넘기는 표의 반복 머리 행이 이미지를 두 번 그리던 문제

원인과 수정 방법을 문단으로 적는다.
```

PR 본문은 **개요 / 변경 내용 / 검증 / 알려진 사항** 순서로 쓴다. 검증에는 실행한 명령, 검증한 커밋 SHA, 결과를
적고 실행하지 않았거나 확인하지 못한 것을 따로 밝힌다.

## 검증

변경 범위에 맞는 것을 실행한다. 명령은 [AGENTS.md의 빌드와 검증](AGENTS.md#빌드와-검증)에 있다.

| 변경 | 실행 |
| --- | --- |
| Rust 소스·시험 | fmt, Clippy(`-D warnings`, 루트와 워크스페이스), 워크스페이스 빌드, 시험 매니페스트·단위 티어 검사, 전체 `cargo test` |
| C ABI(`bindings/Native`) | 위 Rust 묶음 + `macos/scripts/build-xcframework.sh --smoke` |
| `RhwpKit` 등 Swift | `macos/scripts/test-rhwpkit.sh` |
| 조판·렌더링 | 위 + 같은 원본의 한컴 PDF와 쪽 단위 직접 비교([시각 검증](AGENTS.md#시각-검증)) |
| `scripts/` | `node --test scripts/tests/*.test.mjs`, `python3 -m unittest scripts/tests/test_visual_sweep*.py` |

## 시험 추가

- 새 통합 시험은 `tests/cases/`에 원본만 추가한다. 시험 묶음은 `node scripts/rust-test-suite-manifest.mjs --prepare`가
  `tests/generated/`에 파생하며, 이 산출물은 커밋하지 않는다.
- 회귀 시험은 수정 전 코드에서 의도한 원인으로 실패하고 수정 후 통과해야 한다.
- 입력 문서는 `samples/`나 `tests/fixtures/`에 두고, 저작권이 있는 문서나 글꼴은 올리지 않는다.
- 렌더링 회귀 시험이나 기준 파일을 추가하려면 한컴 PDF와의 일치율이 90% 이상이어야 한다.

## 보안

보안 문제는 공개 이슈 대신 저장소 소유자에게 비공개로 알린다.
