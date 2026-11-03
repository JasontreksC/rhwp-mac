//! 칸 마지막 줄 뒤 줄간격은 행 높이를 채우지 않는다 — 공백만 있는 마지막 문단도 같다.
//!
//! `samples/KTX.hwp` 2쪽 목차는 글자처럼 취급된(TAC) 행 단위 쪽나눔(RowBreak) 5×3 표이고, 목차 줄 27개를 한
//! 칸(r4, 세로 가운데 정렬)에 담는다. 그 칸의 마지막 문단은 공백 한 글자(`" "`)다. 측정은 이 마지막 줄의
//! 뒤 줄간격(1120HU = 14.9px)을 행 높이에 더하는 예외를 두었고(종전 `include_trailing_ls`), 그러면 행이 내용보다
//! 14.9px 커져 가운데 정렬이 목차 전체를 7.5px 아래로 민다.
//!
//! 독립 근거(한컴 저장값, 구현 결과가 아니다):
//!
//! ```text
//!   표 저장 높이                 70418HU
//!   머리 행(r0 c1 병합 4964 + r3 592)  5556HU
//!   r4 칸 마지막 문단 p26        vpos 63180 + lh 1400 = 64580HU (뒤 줄간격 1120HU 는 안 넣는다)
//!   칸 여백(위 141 + 아래 141)      282HU
//!   5556 + 64580 + 282 = 70418   ← 저장 높이와 정확히 같다. 뒤 줄간격을 넣으면 71538 이 되어 어긋난다.
//! ```
//!
//! 한컴 PDF(`pdf/KTX-2022.pdf` 2쪽)는 첫 목차 줄 `Ⅰ. 사업 개요`의 글자 아래 끝이 193.4px 인데 예외가 있을 때 우리는 201px
//! (+7.5)이었고 없앤 뒤에는 같은 줄이 0.9px 이내로 한컴과 같다. 목차 줄 전체가 같은 만큼 어긋났다(`추진일정` +6.5, `문의처` +6.5).
//!
//! 위치를 절대 픽셀로 고정하지 않고 관계로 검사한다: 칸 안 첫 줄은 칸 윗면 + 칸 여백 + 저장 vpos(0) 근처에 놓여야 하고
//! (가운데 정렬 오프셋이 따로 붙지 않는다), 마지막 줄은 표 안에 들어야 한다.

use std::fs;
use std::path::Path;

use rhwp::document_api::HwpDocument;
use rhwp::renderer::render_tree::{RenderNode, RenderNodeType};

const SAMPLE: &str = "samples/KTX.hwp";
/// 목차가 있는 쪽(0부터).
const TOC_PAGE: u32 = 1;
const FIRST_ENTRY: &str = "사업 개요";
const LAST_ENTRY: &str = "세부지침";

fn find_run(node: &RenderNode, needle: &str) -> Option<(f64, f64)> {
    if let RenderNodeType::TextRun(run) = &node.node_type {
        if run.text.contains(needle) {
            return Some((node.bbox.y, node.bbox.y + node.bbox.height));
        }
    }
    node.children
        .iter()
        .find_map(|child| find_run(child, needle))
}

fn find_table_with_text(node: &RenderNode, needle: &str) -> Option<(f64, f64)> {
    if matches!(node.node_type, RenderNodeType::Table(_)) && find_run(node, needle).is_some() {
        return Some((node.bbox.y, node.bbox.y + node.bbox.height));
    }
    node.children
        .iter()
        .find_map(|child| find_table_with_text(child, needle))
}

#[test]
fn toc_cell_with_blank_last_paragraph_starts_at_the_cell_top() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(SAMPLE);
    let bytes = fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    let document = HwpDocument::from_bytes(&bytes).expect("parse KTX");

    // 입력이 이 시험이 설명하는 형상인지 먼저 확인한다(없으면 조용히 통과하지 않는다).
    let model = document.document();
    let table = model.sections[0]
        .paragraphs
        .iter()
        .flat_map(|p| p.controls.iter())
        .find_map(|c| match c {
            rhwp::model::control::Control::Table(t)
                if t.row_count == 5
                    && t.col_count == 3
                    && t.common.treat_as_char
                    && t.cells.iter().any(|cell| {
                        cell.paragraphs.iter().any(|p| p.text.contains(FIRST_ENTRY))
                    }) =>
            {
                Some(t)
            }
            _ => None,
        })
        .expect("KTX 목차 표(5×3 TAC)");
    let toc_cell = table
        .cells
        .iter()
        .find(|c| c.paragraphs.iter().any(|p| p.text.contains(FIRST_ENTRY)))
        .expect("목차 칸");
    assert!(
        toc_cell.paragraphs.len() > 20,
        "목차 줄이 한 칸에 모여 있어야 한다"
    );
    let last = toc_cell.paragraphs.last().unwrap();
    assert!(
        !last.text.is_empty() && last.text.trim().is_empty() && last.controls.is_empty(),
        "칸의 마지막 문단은 공백만 있는 글자 문단이어야 한다: {:?}",
        last.text
    );

    // 저장된 머리 행 높이(HWPUNIT → px): r4 칸 윗면은 표 윗면에서 이만큼 내려온다.
    let header_hu: i32 = {
        let spanning = table
            .cells
            .iter()
            .find(|c| c.row == 0 && c.col == 1)
            .expect("r0 c1")
            .height as i32;
        let last_header_row = table
            .cells
            .iter()
            .find(|c| c.row == 3 && c.col == 0)
            .expect("r3 c0")
            .height as i32;
        spanning + last_header_row
    };
    let header_px = header_hu as f64 * 96.0 / 7200.0;
    let pad_top_px = toc_cell.padding.top as f64 * 96.0 / 7200.0;

    let tree = document
        .build_page_render_tree(TOC_PAGE)
        .expect("render TOC page");
    let (table_top, table_bottom) =
        find_table_with_text(&tree.root, FIRST_ENTRY).expect("렌더 트리의 목차 표");
    let (first_top, _) = find_run(&tree.root, FIRST_ENTRY).expect("첫 목차 줄");
    let (_, last_bottom) = find_run(&tree.root, LAST_ENTRY).expect("마지막 목차 줄");

    // 칸 안 첫 줄의 위 끝 = 칸 윗면 + 칸 여백 + 저장 vpos(0). 가운데 정렬 오프셋이 붙으면 7px 넘게 내려간다.
    let cell_top = table_top + header_px;
    let gap = first_top - cell_top - pad_top_px;
    assert!(
        (-1.5..=3.0).contains(&gap),
        "첫 목차 줄이 칸 윗면에서 {gap:.1}px 떨어져 있다. 칸 여백 {pad_top_px:.1}px 에 저장 vpos 0 이면 0 근처여야 한다 \
         (뒤 줄간격을 행에 더하면 가운데 정렬이 7.5px 더 내린다)"
    );
    // 마지막 줄은 표 안에 든다.
    assert!(
        last_bottom <= table_bottom + 0.5,
        "마지막 목차 줄 아래 끝 {last_bottom:.1} 이 표 아래 끝 {table_bottom:.1} 을 넘는다"
    );
}
