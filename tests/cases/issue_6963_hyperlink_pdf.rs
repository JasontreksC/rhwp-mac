//! #6963 출력 레이어의 링크 영역과 실제 PDF annotation 계약.
use rhwp::document_core::{hyperlink::HyperlinkTarget, DocumentCore};
use rhwp::paint::{ClipKind, LayerNode, PageLayerTree, PaintOp, RenderProfile};
use rhwp::renderer::hyperlinks::{export_uri, PdfLink};
use rhwp::renderer::render_tree::{BoundingBox, FieldMarkerType, TextRunNode};

fn blank(text: &str) -> DocumentCore {
    let mut core = DocumentCore::new_empty();
    core.create_blank_document_native().unwrap();
    core.insert_text_native(0, 0, 0, text).unwrap();
    core
}
fn artifact(name: &str, bytes: &[u8]) {
    if let Some(dir) = std::env::var_os("RHWP_HYPERLINK_EVIDENCE_DIR") {
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(std::path::Path::new(&dir).join(name), bytes).unwrap();
    }
}
fn text_run(text: &str, start: usize, positions: Vec<f64>) -> TextRunNode {
    TextRunNode {
        text: text.into(),
        style: Default::default(),
        char_shape_id: Some(0),
        para_shape_id: Some(0),
        section_index: Some(0),
        para_index: Some(0),
        char_start: Some(start),
        cell_context: None,
        is_para_end: false,
        is_line_break_end: false,
        rotation: 0.0,
        is_vertical: false,
        char_overlap: None,
        border_fill_id: 0,
        baseline: 10.0,
        field_marker: FieldMarkerType::None,
        layout_positions: Some(positions),
        display_text: None,
    }
}
fn synthetic_tree(run: TextRunNode, clip: BoundingBox) -> PageLayerTree {
    let bounds = BoundingBox::new(10.0, 20.0, 65.0, 12.0);
    let leaf = LayerNode::leaf(bounds, None, vec![PaintOp::text_run(bounds, run)]);
    PageLayerTree::new(
        100.0,
        100.0,
        LayerNode::clip_rect(bounds, None, clip, leaf, ClipKind::TableCell),
    )
}

#[test]
fn unequal_character_boundaries_and_nested_clip_define_the_link_rect() {
    let mut core = blank("Wi😀X");
    core.insert_hyperlink_native(&HyperlinkTarget::body(0, 0), 1, 3, "https://example.com")
        .unwrap();
    let run = text_run("Wi😀X", 0, vec![0.0, 24.0, 28.0, 51.0, 65.0]);
    let tree = synthetic_tree(run.clone(), BoundingBox::new(0.0, 0.0, 100.0, 100.0));
    let links = core.hyperlinks_in_layer_tree(&tree).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!((links[0].rect.x, links[0].rect.width), (34.0, 27.0));
    let clipped = synthetic_tree(run, BoundingBox::new(40.0, 22.0, 10.0, 8.0));
    let links = core.hyperlinks_in_layer_tree(&clipped).unwrap();
    assert_eq!(
        (
            links[0].rect.x,
            links[0].rect.y,
            links[0].rect.width,
            links[0].rect.height
        ),
        (40.0, 22.0, 10.0, 8.0)
    );
}

#[test]
fn cross_page_run_fragments_intersect_the_same_logical_link() {
    let mut core = blank("Wi😀X");
    core.insert_hyperlink_native(&HyperlinkTarget::body(0, 0), 1, 3, "https://example.com")
        .unwrap();
    let clip = BoundingBox::new(0.0, 0.0, 100.0, 100.0);
    let first = core
        .hyperlinks_in_layer_tree(&synthetic_tree(
            text_run("Wi", 0, vec![0.0, 24.0, 28.0]),
            clip,
        ))
        .unwrap();
    let second = core
        .hyperlinks_in_layer_tree(&synthetic_tree(
            text_run("😀X", 2, vec![0.0, 23.0, 37.0]),
            clip,
        ))
        .unwrap();
    assert_eq!(
        (first[0].start, first[0].end, first[0].rect.width),
        (1, 2, 4.0)
    );
    assert_eq!(
        (second[0].start, second[0].end, second[0].rect.width),
        (2, 3, 23.0)
    );
}

#[test]
fn clipped_out_links_are_absent_and_unsupported_rotation_is_reported() {
    let mut core = blank("Wi😀X");
    core.insert_hyperlink_native(&HyperlinkTarget::body(0, 0), 1, 3, "https://example.com")
        .unwrap();
    let mut run = text_run("Wi😀X", 0, vec![0.0, 24.0, 28.0, 51.0, 65.0]);
    let hidden = synthetic_tree(run.clone(), BoundingBox::new(0.0, 50.0, 10.0, 10.0));
    assert!(core.hyperlinks_in_layer_tree(&hidden).unwrap().is_empty());
    run.rotation = 90.0;
    let tree = synthetic_tree(run, BoundingBox::new(0.0, 0.0, 100.0, 100.0));
    assert!(core.hyperlinks_in_layer_tree(&tree).is_err());
}

fn tiny_svg(width: u32) -> String {
    format!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="100"><rect x="10" y="20" width="30" height="10"/></svg>"#
    )
}
fn link(uri: &str) -> Vec<PdfLink> {
    vec![PdfLink {
        uri: uri.into(),
        rect: BoundingBox::new(10.0, 20.0, 30.0, 10.0),
    }]
}

// 이 writer의 annotation/page 사전은 비압축이다. URI와 /P 참조를 별도로 추적한다.
fn page_uris(pdf: &[u8]) -> Vec<Vec<String>> {
    let text = String::from_utf8_lossy(pdf);
    let objects: Vec<_> = text
        .split("endobj")
        .filter_map(|object| {
            let (header, body) = object.rsplit_once(" 0 obj")?;
            Some((
                header.split_whitespace().last()?.to_string(),
                body.to_string(),
            ))
        })
        .collect();
    objects
        .iter()
        .filter(|(_, body)| {
            body.split_once("/Type ")
                .is_some_and(|(_, tail)| tail.split_whitespace().next() == Some("/Page"))
        })
        .map(|(page_id, body)| {
            let Some((_, annots)) = body.split_once("/Annots [") else {
                return Vec::new();
            };
            let refs: Vec<_> = annots
                .split(']')
                .next()
                .unwrap()
                .split_whitespace()
                .collect();
            refs.chunks_exact(3)
                .map(|reference| {
                    assert_eq!(&reference[1..], &["0", "R"]);
                    let body = &objects.iter().find(|(id, _)| id == reference[0]).unwrap().1;
                    assert!(body.contains(&format!("/P {page_id} 0 R")));
                    assert!(body.contains("/Subtype /Link"));
                    body.split_once("/URI (")
                        .unwrap()
                        .1
                        .split(')')
                        .next()
                        .unwrap()
                        .to_string()
                })
                .collect()
        })
        .collect()
}
