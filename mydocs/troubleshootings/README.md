---
kind: guide
status: active
canonical: mydocs/troubleshootings/README.md
last_verified: 2026-11-03
---

# 트러블슈팅 문서 지도

재현 가능한 증상에 대해 확정된 원인, 적용 가능한 대응, 검증 방법을 보존한다. 새 작업에서는 관련 증상이 있는지
먼저 확인하되, 문서의 코드 위치와 시험은 현재 `main`에서 다시 검증한다. 해결책의 폐기를 뜻하는 것은 아니지만
적용 전에 현재 코드와 대조가 필요하다.

웹 편집기, 브라우저 확장, CI, 에이전트 도구에 관한 기록은 대상이 사라져 지웠다. 남은 것은 엔진의 파싱·조판·저장
결함과 그 원인 분석이다. 문서가 인용하는 이슈·작업 기록 파일은 지웠을 수 있다.

## 문서 목록

- [`samples/2010-01-06.hwp` 자동 보정(reflow) 후 빈 페이지 4 삽입](2010_01_06_auto_fix_blank_page.md)
- [`samples/2010-01-06.hwp` 페이지 1 각주 1) 줄 간격 좁음](2010_01_06_footnote_line_spacing.md)
- [BinData ID 매핑 오류 — 배경 이미지 잘못 연결](bin_data_id_index_mapping.md)
- [이슈 초안: BMP 임베딩 HWP 문서가 SVG에서 렌더링되지 않음](bmp_svg_render.md)
- [#1858 발현 2 조사 — vert=쪽 valign=Bottom 하단 블록 세로 오프셋 (36389312)](bottom_anchor_declared_vs_rendered_height.md)
- [셀 padding 이 cell.height 를 초과하는 비정상 IR 처리](cell_padding_exceeds_cell_height.md)
- [셀 분할 시 중첩 표 (atomic) 가시성 결정](cell_split_nested_table_visibility.md)
- [셀 나누기 후 저장 시 파일 손상](cell_split_save_corruption.md)
- [HWP 5.0 단 정의(cold) 너비/간격 비례값 인코딩](column_def_proportional_widths.md)
- [지연 셀 편집의 캐시·페이지네이션 정합성 진단](deferred_cell_edit_cache_coherence.md)
- [Task #1860 — 분할 예산 계측·근본원인 (Stage 1)](deferred_rowbreak_table_split_budget.md)
- [한컴 PDF 출력의 환경 의존성 — 정답지로 사용 불가](hancom_pdf_environment_dependency.md)
- [HWP3 내장 OLE 참조명을 외부 파일로 오분류 — 테스트가 오분류를 제도화한 사례](hwp3_ole_reference_name_misclassification.md)
- [누름틀(ClickHere) 안내문이 한컴에서 바인딩 안 됨 — command 포맷 어긋남 (Task #1434)](hwp_clickhere_guide_command_format.md)
- [표 셀 렌더링의 암묵지 — 한컴 `letter_spacing` 보정, narrow glyph 역진, 자연폭 가드](hwp_letter_spacing_compensation.md)
- [HWPX to HWP Hancom Compatibility Rules](hwpx2hwp-rule.md)
- [HWPX to HWP SHAPE_COMPONENT rendering matrix precision](hwpx2hwp_shape_rendering_matrix_precision.md)
- [HWPX 수식 저장 — EQEDIT spec errata + Stage 4-pivot oracle (Task #1061)](hwpx_equation_save_eqedit_spec_errata.md)
- [HWPX 각주 저장 — 5 라운드 정답지 oracle 방법론 (Task #1058)](hwpx_footnote_save_5round_oracle_method.md)
- [HWPX LINE_SEG reflow 함정](hwpx_lineseg_reflow_trap.md)
- [HWPX serializer — newNum 슬롯이 텍스트 뒤가 아니라 앞으로 방출 (Task #1407)](hwpx_newnum_slot_after_text.md)
- [Issue #1772 조사 보고서 — HWPX/HWP5 파스 경로별 saved-vpos 신뢰 차이의 근본 원인](hwpx_table_out_margin_common_margin_sync.md)
- [#1637 근본원인 조사 — HWPX roundtrip IR-invisible 페이지네이션 변동](hwpx_visibility_and_flow_with_text_serialization.md)
- [그림 crop scale 룰 — HWP 표준 75 HU/px](image_crop_scale_rule.md)
- [Issue #352 원인 확정 보고서](issue_352_root_cause.md)
- [줄간격 변경 시 LineSeg 동기화 문제](line_spacing_lineseg_sync.md)
- [Issue #1785 조사 보고서 — cell.apply_inner_margin 파스 불일치의 근본 원인](microgrid_cell_margin_roundtrip.md)
- [한 문단 내 다중 TAC 표 페이지네이션 오류](multi_tac_table_pagination.md)
- [편집 용지 영역 계산 오류 (페이지 여백)](page_margin_area_calculation.md)
- [문단 들여쓰기/내어쓰기 모델 및 표 x 위치 수정](paragraph_indent_and_table_x_position.md)
- [그림 저장 시 한컴 호환성 문제](picture_save_hancom_compatibility.md)
- [raw_data 를 문 clone 뮤테이션 — 화면엔 보이고 저장엔 사라지는 3중 구조 (PR #2416/#2421)](raw_data_stale_clone_on_mutation.md)
- [표 제목행 반복 시 이미지 중복 렌더링 문제](repeat_header_image_duplication.md)
- [도형 채우기 투명도(alpha) 미처리 문제](shape_fill_transparency.md)
- [Square wrap 그림 하단 보정의 double advance 함정](square_wrap_pic_bottom_double_advance.md)
- [트러블슈팅: 탭+TAC 수식 겹침 문제 (#142, #159)](tab_tac_overlap_142_159.md)
- [표 붙여넣기 후 저장 파일 손상 분석](table_paste_file_corruption.md)
- [표 페이지 분할 렌더링 및 셀 내 렌더링 수정](table_reflow_and_cell_rendering.md)
- [빈 문단 + TAC Picture 이중 emit 회귀](tac_picture_double_emit.md)
- [TAC 표의 ParaShape align 반영 누락](tac_table_para_align.md)
- [#178 첫 시도 실패 — HWPX→HWP 강제 저장으로 사용자 경험 개선 시도](task178_hwpx_to_hwp_first_attempt_failure.md)
- [#178 두 번째 시도 — 한컴 호환 실패](task178_second_attempt_hancom_rejection.md)
- [트러블슈팅: HWP 확장 제어 문자 바이트 구조](task_56_hwp_control_char_bytes.md)
- [타스크 70 미완료 상태 완료 처리 — 트러블슈팅](task_70_page_number_false_completion.md)
- [트러블슈팅: 표 앞 텍스트가 표 아래에 렌더링되는 문제](task_75_table_text_vertical_offset.md)
- [트러블슈팅: 이미지 배치 로직 불일치로 인한 회귀 반복](task_76_image_layout_unification.md)
- [트러블슈팅: 그룹(객체 묶음) 자식 도형 좌표 변환 오류](task_96_group_child_matrix_composition_order.md)
- [그룹 자식 TextBox 세로 정렬 미적용 문제](task_96_group_child_textbox_vertical_align.md)
- [Task #103 (#157) 1차 시도 폐기 — 포스트모템](task_m100_103_attempt1_postmortem.md)
- [목차 리더 도트 + 페이지번호 right tab 정렬](toc_leader_right_tab_alignment.md)
- [Typeset fit 누적 drift + 단독 항목 페이지 — 트러블슈팅 (Task #359)](typeset_fit_accumulation_drift.md)
- [typeset / layout drift 분석 — Task #331 revert 회고](typeset_layout_drift_analysis.md)
- [TypesetEngine page_num NewNumber 적용 + PartialTable fit 안전마진 — 트러블슈팅 (Task #361)](typeset_page_num_newumber_application.md)
- [TypesetEngine PartialTable + Square wrap 처리 누락 — 트러블슈팅 (Task #362)](typeset_partial_table_wrap_around.md)
