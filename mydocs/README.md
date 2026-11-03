---
kind: guide
status: active
canonical: mydocs/README.md
last_verified: 2026-11-03
---

# mydocs 문서 지도

이 디렉터리는 rhwp-mac의 기술 문서를 모은다. 포크 이전(업스트림) 시기의 작업 기록, 보고서, PR 증적, 다국어 번역,
에이전트·웹·CLI 매뉴얼은 macOS 앱에 쓰임이 없어 지웠다. 필요하면 git 기록에서 되살린다.

## 시작 순서

1. 저장소 루트의 [README](../README.md)와 [AGENTS.md](../AGENTS.md)를 읽는다(`CLAUDE.md`는 AGENTS.md를 불러온다).
2. 방향과 단계별 계획은 [macOS 네이티브 앱 아키텍처](tech/macos_native_app_architecture.md)다.
3. 엔진을 건드리면 아래 표에서 해당하는 기술 문서만 추가로 읽는다.

## 어디에 무엇이 있나

| 경로 | 내용 |
| --- | --- |
| [tech/](tech/README.md) | 포맷 사양 정리, IR·조판·저장 설계, 결정 기록. **가장 중요한 폴더** |
| [manual/](manual/README.md) | 남긴 매뉴얼: 수식, 글꼴 환경, 시각 검증, OWPML 스키마, 한컴 기준 PDF 만들기 |
| [troubleshootings/](troubleshootings/README.md) | 재현 가능한 증상의 원인과 대응 기록(엔진 결함 중심) |

## 문서 규칙

- 문서 머리의 `kind`(guide·decision·reference…), `status`, `canonical`, `last_verified`는 그 문서의 성격과
  최신 확인일을 알린다. 코드와 문서가 다르면 코드가 맞고 문서를 고친다.
- 결정 문서는 `tech/`에 둔다. 새 결정은 이 포크의 방침(macOS 전용, Rust가 배치하고 Swift가 그림)과 맞는지 먼저
  확인하고, 어긋나는 업스트림 문서는 낡은 것으로 본다.
- 일부 기술 문서는 지운 작업 기록(`mydocs/working`, `mydocs/pr` 등)이나 이슈 번호를 근거로 인용한다. 그 파일은
  없어도 문서의 결론과 사양 설명은 그대로 유효하다.
