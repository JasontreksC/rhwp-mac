---
kind: guide
status: active
canonical: mydocs/tech/README.md
last_verified: 2026-11-03
---

# tech 문서 지도

`mydocs/tech/`는 **기술 사실, 설계, 결정, 조사 근거**를 보존한다. 이 포크의 방향은
[macOS 네이티브 앱 아키텍처](macos_native_app_architecture.md)가 정한다.

## 앱과 경계

| 문서 | 내용 |
| --- | --- |
| [macos_native_app_architecture.md](macos_native_app_architecture.md) | 구조 결정, 단계별 계획, 저장소 정리 기록, 스파이크 결과 |
| [parser_architecture.md](parser_architecture.md) | 포맷 파서와 공통 `Document` IR의 경계(HWP3 전용 해석은 `parser/hwp3`에서 끝낸다) |
| [edit_action_undo_redo_architecture.md](edit_action_undo_redo_architecture.md) | 편집 액션과 되돌리기 계약. 앱이 되돌리기 스택을 만들 때의 기준 |
| [edited_since_load_flag_design.md](edited_since_load_flag_design.md) | 로드 이후 편집 여부 플래그 |

## 조판·렌더링

| 문서 | 내용 |
| --- | --- |
| [typesetting_architecture.md](typesetting_architecture.md) | 조판 코드의 책임 경계와 변경 지도 |
| [rendering_engine_design.md](rendering_engine_design.md) | 렌더링 엔진 구조 |
| [shared_layout_measurement_engine.md](shared_layout_measurement_engine.md) | 페이지네이터와 렌더러가 같은 측정을 쓰게 하는 설계 |
| [table_layout_rules.md](table_layout_rules.md), [hwp_table_rendering.md](hwp_table_rendering.md) | 표 조판 규칙 |
| [multicolumn_object_flow_backfill.md](multicolumn_object_flow_backfill.md) | 다단에서 개체가 단을 옮길 때의 흐름 |
| [document_ir_lineseg_standard.md](document_ir_lineseg_standard.md) | `LineSeg` 필드 표준 |
| [font_fallback_strategy.md](font_fallback_strategy.md), [pua_oldhangul_mapping_sources.md](pua_oldhangul_mapping_sources.md) | 글꼴 대체와 옛한글 매핑 |
| [large_document_limits.md](large_document_limits.md) | 대형 문서에서 어디까지 되는가 |
| [raw_cache_inventory.md](raw_cache_inventory.md) | 원본 바이트 캐시 필드의 해석 상태(`issue_5890` 시험이 읽는다) |

## 포맷 사양과 정오표

| 문서 | 내용 |
| --- | --- |
| [hwp_spec_errata.md](hwp_spec_errata.md) | HWP 5.0 공개 사양의 정오표 |
| [hwp_ctrl_data.md](hwp_ctrl_data.md), [hwp_form_object_api.md](hwp_form_object_api.md) | `CTRL_DATA`, 양식 개체 |
| [hwp_ole_spec.md](hwp_ole_spec.md), [hwp_chart_spec.md](hwp_chart_spec.md) | OLE 개체와 차트 바이너리 |
| [chart_ole_v1_boundary.md](chart_ole_v1_boundary.md), [hwp_ole_chart_renderer_architecture_decision_1251.md](hwp_ole_chart_renderer_architecture_decision_1251.md) | 차트 OLE의 지원 경계와 렌더러 선택 |
| [emf_spec.md](emf_spec.md), [emf_ir_design.md](emf_ir_design.md) | EMF |
| [hml_format_inventory.md](hml_format_inventory.md) | HML |
| [owpml_conformance_observations.md](owpml_conformance_observations.md), [hwpx_hancom_reference.md](hwpx_hancom_reference.md), [hwpx_dvc_reference.md](hwpx_dvc_reference.md) | HWPX(OWPML) 정합 관찰과 한컴 공식 참조 |
| [hwp_hwpx_ir_differences.md](hwp_hwpx_ir_differences.md), [hwpx_lineseg_validation.md](hwpx_lineseg_validation.md) | HWP와 HWPX의 IR 차이, 비표준 `lineseg` 처리 |
| [text-ir-v2.md](text-ir-v2.md) | 텍스트 IR v2 이행 계약 |

## 저장

| 문서 | 내용 |
| --- | --- |
| [hwp_save_guide.md](hwp_save_guide.md) | HWP 저장 기술 가이드 |
| [hwpx2hwp-01.md](hwpx2hwp-01.md) | HWPX를 HWP로 저장하는 기술 노트 |
| [serialization_passthrough_contract.md](serialization_passthrough_contract.md) | 직렬화 passthrough와 무효화 계약 |
| [task_m100_3604_password_encryption_cpp_review.md](task_m100_3604_password_encryption_cpp_review.md) | 한컴 C++ 암호 저장 표면 조사 |
