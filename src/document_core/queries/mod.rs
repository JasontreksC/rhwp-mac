// 문서 읽기 전용 질의 모음.
//
// 이 포크는 macOS 앱이 쓰는 질의만 남긴다. LLM 에이전트용 질의(프롬프트 주입·위협·개인정보 탐지,
// grep·explore·explain, CSV 추출 등)는 앱에 쓰임이 없어 제거했다. git 기록에서 되살릴 수 있다.
mod bookmark_query;
mod cursor_nav;
mod cursor_rect;
pub(crate) mod doc_tree_nav;
// 필드(누름틀) 위치 질의. 표 셀 경로 해석 도우미를 다른 모듈이 함께 쓰므로 공개한다.
/// [#4100] 문서 안 차트 열거와 ①② 슬롯 해석.
pub mod chart_extract;
pub mod field_query;
mod font_decision;
mod form_query;
pub mod hyperlink_geometry;
/// 개요 번호 전용 탐색 메타데이터. 문단 모양의 Outline만 대상으로 한다.
pub mod navigation;
pub mod rendering;
pub(crate) mod search_query;
pub mod table_extract;
