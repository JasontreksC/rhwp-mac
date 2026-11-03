---
kind: guide
status: active
canonical: mydocs/manual/README.md
last_verified: 2026-11-03
---

# manual 문서 지도

이 포크에 남은 매뉴얼이다. CLI, MCP, 웹 편집기, 브라우저 확장, WASM, GitHub 운영, PR 검토 절차, 에이전트 작업 규약
문서는 대상이 사라져 지웠다. 작업 규칙은 저장소 루트의 [AGENTS.md](../../AGENTS.md)가 정본이다.

| 문서 | 내용 |
| --- | --- |
| [equation_module.md](equation_module.md) | 수식 모듈: 한컴 수식 스크립트의 파싱과 조판 |
| [font_environment.md](font_environment.md) | 조판에 쓰는 글꼴 환경을 명시적으로 지정하는 방법 |
| [font_incident_response.md](font_incident_response.md) | 글꼴 감지·대체 문제가 났을 때의 대응 절차 |
| [mcp_hwp2024Convert_usage.md](mcp_hwp2024Convert_usage.md) | 한컴 오피스로 기준 PDF를 만드는 방법과 인쇄 계약 |
| [owpml_schema_reference.md](owpml_schema_reference.md) | OWPML XML 스키마 자산(`OWPML SCHEMA/`)의 사용법 |
| [verification/](verification/README.md) | 한컴 PDF와 비교하는 시각 검증 문서 |

문서 안의 `cargo run --bin rhwp …`, `rhwp-studio`, WASM 빌드 같은 명령은 이 포크에서 지운 경로다. 원리와 판정 기준만
따르고 명령은 [AGENTS.md](../../AGENTS.md)의 현재 절차로 바꿔 읽는다.
