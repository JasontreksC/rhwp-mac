//! Issue #1144: filename field context must be resolved before PageLayerTree.
//!
//! Filename is document context, not renderer-local metadata. PageLayerTree,
//! native Skia export, and CanvasKit direct replay all consume the same
//! filename-resolved layer state through `build_page_layer_tree`.

#[path = "support/issue_1144_support.rs"]
mod issue_1144_support;

use issue_1144_support::{document_with_filename_footer, layer_tree_texts};

#[test]
fn issue_1144_page_layer_tree_uses_filename_context() {
    let mut doc = document_with_filename_footer();
    doc.set_file_name("issue-1144-fixture.hwp");

    let texts = layer_tree_texts(&doc);

    assert!(
        texts
            .iter()
            .any(|text| text.contains("issue-1144-fixture.hwp")),
        "PageLayerTree text runs should contain resolved filename. texts={texts:?}"
    );
    assert!(
        texts.iter().all(|text| !text.contains('\u{0017}')),
        "PageLayerTree should not leak raw filename field marker. texts={texts:?}"
    );
}

#[test]
fn issue_1144_set_file_name_invalidates_cached_page_tree() {
    let mut doc = document_with_filename_footer();
    doc.set_file_name("old-name.hwp");

    let old_texts = layer_tree_texts(&doc);
    assert!(
        old_texts.iter().any(|text| text.contains("old-name.hwp")),
        "initial render should resolve old filename. texts={old_texts:?}"
    );

    doc.set_file_name("new-name.hwp");
    let new_texts = layer_tree_texts(&doc);

    assert!(
        new_texts.iter().any(|text| text.contains("new-name.hwp")),
        "cached PageRenderTree should be invalidated after filename change. texts={new_texts:?}"
    );
    assert!(
        new_texts.iter().all(|text| !text.contains("old-name.hwp")),
        "stale filename should not survive cache invalidation. texts={new_texts:?}"
    );
}

#[test]
fn issue_1144_empty_filename_context_resolves_to_empty_string() {
    let mut doc = document_with_filename_footer();
    doc.set_file_name("");

    let texts = layer_tree_texts(&doc);

    // 필드는 제 런으로 떨어지므로(Task #3216) 줄 전체를 이어 붙여서 본다.
    assert_eq!(
        texts.concat(),
        "1\t",
        "empty filename should resolve to empty string while preserving surrounding text. texts={texts:?}"
    );
    assert!(
        texts.iter().all(|text| !text.contains('\u{0017}')),
        "empty filename fallback should not leak raw marker. texts={texts:?}"
    );
}
