//! SVG 조각 파서 유틸리티 (Task #275)
//!
//! RenderNodeType::RawSvg 에 담긴 SVG 조각 (shape_layout.rs 가 생성) 을
//! 파싱·디코드하기 위한 문자열 유틸. 네이티브/WASM 양쪽에서 사용 가능.

/// SVG 프리픽스 감지 — 선행 공백/XML 선언 이후 `<svg` 로 시작하는지.
///
/// RenderNodeType::RawSvg 래퍼 경로에서 생성된 SVG 문서 바이트의 MIME 감지에 사용.
/// (detect_image_mime_type 확장 — Task #275)
pub(crate) fn is_svg_prefix(data: &[u8]) -> bool {
    // 선행 공백 스킵 (최대 64바이트까지만)
    let mut i = 0;
    while i < data.len().min(64) && matches!(data[i], b' ' | b'\t' | b'\n' | b'\r') {
        i += 1;
    }
    if data.len().saturating_sub(i) < 4 {
        return false;
    }
    // `<svg` 직접 시작
    if data[i..].starts_with(b"<svg") {
        return true;
    }
    // `<?xml ... ?>` 선언 후 `<svg`
    if data[i..].starts_with(b"<?xml") {
        // 첫 256바이트 내에 `<svg` 등장하면 SVG 간주
        let search_end = data.len().min(i + 256);
        return data[i..search_end].windows(4).any(|w| w == b"<svg");
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_svg_prefix_direct() {
        assert!(is_svg_prefix(b"<svg"));
        assert!(is_svg_prefix(b"<svg xmlns=\"http://www.w3.org/2000/svg\">"));
        assert!(is_svg_prefix(b"  \n  <svg>"));
        assert!(is_svg_prefix(b"\t<svg width=\"10\">"));
    }

    #[test]
    fn is_svg_prefix_xml_decl() {
        assert!(is_svg_prefix(b"<?xml version=\"1.0\"?>\n<svg>"));
        assert!(is_svg_prefix(
            b"<?xml version=\"1.0\" encoding=\"utf-8\"?><!DOCTYPE svg>\n<svg>"
        ));
    }

    #[test]
    fn is_svg_prefix_rejects_png() {
        assert!(!is_svg_prefix(b"\x89PNG\r\n\x1a\n"));
        assert!(!is_svg_prefix(b"\xFF\xD8\xFF")); // JPEG
        assert!(!is_svg_prefix(b"BM")); // BMP
    }

    #[test]
    fn is_svg_prefix_rejects_html_etc() {
        assert!(!is_svg_prefix(b"<html>"));
        assert!(!is_svg_prefix(b"<!DOCTYPE html>"));
        assert!(!is_svg_prefix(b""));
        assert!(!is_svg_prefix(b"<?"));
    }

    #[test]
    fn is_svg_prefix_xml_without_svg() {
        // XML 선언은 있지만 256바이트 내에 <svg 가 없으면 거부
        let mut data = b"<?xml version=\"1.0\"?>".to_vec();
        data.extend_from_slice(&[b'a'; 300]);
        data.extend_from_slice(b"<svg>");
        assert!(!is_svg_prefix(&data), "256바이트 창 밖은 매칭하지 않음");
    }
}
