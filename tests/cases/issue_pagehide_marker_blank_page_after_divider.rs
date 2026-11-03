//! 쪽 나누기와 PageHide 를 가진 빈 문단(구역 표식 뒤의 PageHide marker)은 한컴에서 **빈 쪽을 만든다**.
//!
//! `samples/2025 행정업무운영 편람(최종).hwp` 의 `5 질의 및 답변` 간지(구역 10)와 `부 록` 간지(구역 11)는 같은 모양이다.
//!
//! ```text
//!   pi=0  Section break  (SectionDef·Shape·PageHide)     간지 그림이 있는 쪽
//!   pi=1  빈 문단
//!   pi=2  Page break     (PageHide)                       ← marker: 새 쪽을 열고 머리말·꼬리말·쪽 번호를 감춘다
//!   pi=3  Page break     (Shape 또는 Table)               ← 호스트: marker 쪽 위에서 다시 새 쪽을 연다
//! ```
//!
//! 한컴 PDF(`pdf/2025 행정업무운영 편람(최종)-hwp-2024.pdf`)는 간지 쪽 **다음에 글자 없는 쪽**을 두고 그 다음 쪽에서 내용을
//! 시작한다: 277쪽 `5 질의 및 답변`(31자) → 278쪽(0자) → 279쪽 목차, 310쪽 `부록`(22자) → 311쪽(0자) → 312쪽 본문.
//! 종전 코드는 이 marker 를 "같은 쪽 장식 host 의 중복 break"로 보고 건너뛰어 그 빈 쪽을 없앴다(우리는 278·311쪽 대신 곧바로
//! 내용이 나왔다). 쪽수 원장에서 이 규칙으로 바뀌는 문서는 편람 하나뿐이고 HWPX 편람은 383 → 384 로 정답지 384 와
//! 같아진다.
//!
//! 이 시험은 쪽수 총합이 아니라 **구조**를 본다: 짧은 간지 쪽 다음에 글자 없는 쪽이 오고 그 다음 쪽에 내용이 있다.

use std::path::Path;

use rhwp::document_core::DocumentCore;

const SAMPLES: [&str; 2] = [
    "samples/2025 행정업무운영 편람(최종).hwp",
    "samples/2025 행정업무운영 편람(최종).hwpx",
];
/// 간지 쪽의 글자(공백 제거) 접두와 그 쪽의 최대 길이. 본문 목차 쪽과 구분하려 길이를 본다.
const DIVIDERS: [(&str, usize); 2] = [("5질의및답변", 60), ("부록행정업무의운영", 60)];

fn flat_pages(sample: &str) -> Vec<String> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(sample);
    let core =
        DocumentCore::from_bytes(&std::fs::read(&path).expect("편람 원본")).expect("문서 로드");
    (0..core.page_count())
        .map(|page| {
            core.extract_page_text_native(page)
                .unwrap_or_default()
                .split_whitespace()
                .collect::<String>()
        })
        .collect()
}

#[test]
fn page_after_each_divider_is_blank_and_content_follows() {
    for sample in SAMPLES {
        let pages = flat_pages(sample);
        for (prefix, max_len) in DIVIDERS {
            // 간지 쪽: 접두로 시작하고 짧은 쪽(목차 항목이나 본문 쪽과 구분). 뒤쪽 것을 쓴다(앞쪽 목차 항목 제외).
            let divider = pages
                .iter()
                .enumerate()
                .filter(|(_, text)| text.starts_with(prefix) && text.chars().count() < max_len)
                .map(|(index, _)| index)
                .next_back()
                .unwrap_or_else(|| panic!("{sample}: 간지 쪽 {prefix}"));
            assert!(
                divider + 2 < pages.len(),
                "{sample}: 간지 {} 쪽 뒤에 쪽이 둘 이상 있어야 한다",
                divider + 1
            );
            assert!(
                pages[divider + 1].is_empty(),
                "{sample}: 간지 {}쪽({prefix}) 다음 쪽은 글자 없는 빈 쪽이어야 한다(한컴 PDF 278·311쪽). 실제 {}쪽: {:?}",
                divider + 1,
                divider + 2,
                pages[divider + 1].chars().take(24).collect::<String>()
            );
            assert!(
                !pages[divider + 2].is_empty(),
                "{sample}: 빈 쪽 다음 {}쪽에 내용이 있어야 한다",
                divider + 3
            );
        }
    }
}
