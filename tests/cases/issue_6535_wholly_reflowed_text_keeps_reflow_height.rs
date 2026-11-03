//! 저장 줄이 없는 글자 문단은 재조판 높이를 쓴다 — 앞뒤 저장 앵커 사이 간격으로 되살리지 않는다.
//!
//! `samples/issue6535/36339092_low_slack_absorb_block.hwpx` 는 별표 줄 문단 셋(pi=4~6)에 저장 `linesegarray` 가
//! 없다. 로드 때 재조판이 그 줄들을 만들고, 뒤 문단 pi=7~9 의 저장 vpos 를 재계산한다. 저장 간격(30465 → 44617HU
//! = 188.7px)은 이 세 문단의 **원본 높이**를 품고 있는데 재조판은 4줄 117.9px 로 센다. 종전 코드는 간격과 재조판
//! 높이 중 큰 쪽(`max(running, anchored)`)을 써서 뒤 문단 vpos 를 70.8px 올렸고(pi=9 가 43465 가 아니라 48777),
//! 그 값에서 복원한 본문 끝 678px 에 351px 서명 틀이 들어가지 않아 틀이 2쪽에 홀로 놓였다.
//!
//! 독립 근거(구현 결과가 아니다): 한/글 2022 가 같은 문서를 뽑은 `pdf/36339092_low_slack_absorb_block-2020.pdf` 는
//! 1쪽이고, 그 문단들을 4줄(y=498·529·561·588px)로 놓고 `붙임 1.` 을 644px, 서명 틀을 같은 쪽 아래에 둔다.
//! 상류 `ee4d7c4ad`(#6535)도 이 문서를 1쪽으로 적었고 한글 2024 재확인을 달았다. 이후 로드 재계산이 저장 간격을
//! 되살리도록 바뀌면서(`96e03371f`) 2쪽이 되었다.
//!
//! 쪽수와 함께 **관계**를 본다: 서명 틀은 본문 마지막 줄 아래, 같은 쪽에 있어야 한다.

use std::fs;
use std::path::Path;

use rhwp::document_api::HwpDocument;
use rhwp::renderer::render_tree::{RenderNode, RenderNodeType};

const SAMPLE: &str = "samples/issue6535/36339092_low_slack_absorb_block.hwpx";

fn find_run_top(node: &RenderNode, needle: &str) -> Option<f64> {
    if let RenderNodeType::TextRun(run) = &node.node_type {
        if run.text.contains(needle) {
            return Some(node.bbox.y);
        }
    }
    node.children
        .iter()
        .find_map(|child| find_run_top(child, needle))
}

fn find_table_top_with_text(node: &RenderNode, needle: &str) -> Option<f64> {
    if matches!(node.node_type, RenderNodeType::Table(_)) && find_run_top(node, needle).is_some() {
        return Some(node.bbox.y);
    }
    node.children
        .iter()
        .find_map(|child| find_table_top_with_text(child, needle))
}

#[test]
fn wholly_reflowed_text_paragraphs_do_not_pull_the_signature_block_to_page_two() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(SAMPLE);
    let bytes = fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    let document = HwpDocument::from_bytes(&bytes).expect("parse 36339092");

    // 입력이 시험이 설명하는 형상인지 확인한다: 별표 줄 문단 셋이 있고, 뒤 문단이 그 아래에 이어진다.
    let paragraphs = &document.document().sections[0].paragraphs;
    let star_paras = paragraphs
        .iter()
        .filter(|p| p.text.starts_with("**") && p.controls.is_empty())
        .count();
    assert!(
        star_paras >= 3,
        "별표 줄 문단 셋(pi=4~6)이 있어야 한다: {star_paras}"
    );

    assert_eq!(
        document.page_count(),
        1,
        "한/글 2022·2024 는 이 문서를 1쪽으로 뽑는다. 서명 틀이 2쪽에 홀로 놓이면 재조판한 글자 문단의 높이가 \
         저장 간격으로 다시 늘어난 것이다"
    );

    // 같은 쪽 안의 순서: 본문 마지막 줄(`끝.`)이 서명 틀(결재선) 위에 있다.
    let tree = document.build_page_render_tree(0).expect("render page 1");
    let last_body = find_run_top(&tree.root, "끝.").expect("본문 마지막 줄");
    let signature_top = find_table_top_with_text(&tree.root, "주무관").expect("서명 틀(주무관)");
    assert!(
        last_body < signature_top,
        "본문 마지막 줄({last_body:.1})은 서명 틀({signature_top:.1}) 위에 있어야 한다"
    );
}
