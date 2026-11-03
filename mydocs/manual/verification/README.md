---
kind: guide
status: active
canonical: mydocs/manual/verification/README.md
last_verified: 2026-07-30
---

# 시각 검증 문서 지도

`mydocs/manual/verification/`은 한컴 출력 PDF와 이쪽 출력을 비교하는 시각 검증 문서다. 최종 판정 권위는 한컴
편집기와 기준 PDF에 있으며, 자동 도구는 후보 검출과 무회귀 확인을 보조한다.

> **이 포크의 현재 상태.** 이 문서들은 업스트림에서 가져왔다. 문서가 소개하는 `rhwp export-svg` CLI, WASM 내보내기,
> `rhwp-studio`, `tools/` 하네스, PR 검토 절차는 지웠다. 지금 쓸 수 있는 도구는 `scripts/visual_sweep.py`의 PNG 비교
> (`--silhouette-only --png-pair`)이고, 렌더 PNG는 Swift 렌더러(스파이크)로 만든다. 판정 기준(2px 이웃 관용 실루엣
> 일치율, 90% 게이트, 쪽수 비교)은 [AGENTS.md](../../../AGENTS.md#시각-검증)를 따른다.

| 목적 | 문서 |
| --- | --- |
| 시각 검증을 언제 어떻게 적용하고 증적을 남기는가 | [시각 검증 거버넌스](visual_verification_governance.md) |
| PDF와 이미지의 overlay·drift 후보 탐색, 실루엣 일치율 | [visual sweep 가이드](visual_sweep_guide.md) |
| 한컴 PDF 줄 baseline 대조 | [한글 PDF baseline](hangul_pdf_baseline.md) |
| 한컴 페이지 충실도 오라클 | [한글 페이지 충실도 오라클](hangul_page_oracle.md) |
| 한컴 버전 간 페이지네이션 차이로 정답지 버전 판단 | [한글 버전별 페이지네이션 대조](hangul_version_oracle.md) |
