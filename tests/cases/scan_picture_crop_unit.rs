//! 해상도가 높은 스캔 그림의 crop 은 dpi 가 아니라 **75 HU/px** 로 풀린다 — 계약 시험.
//!
//! 4단계 렌더러 조사에서 "300dpi 스캔이면 24 HU/px 로 풀어야 한다"는 의심이 있었다. 그러나
//! `1613000-202200037-air-traffic-controller-cbta.hwp` 48쪽의 그림(JFIF 300dpi, 디코딩 2550×3300px,
//! crop `(7675, 7595, 184861, 243129)`)은 파일이 crop 기준 크기 `imgDim = 191280×247500 HU` 를 직접 저장하고 있고,
//! 그것은 픽셀 × 75.01 HU 다(300dpi 의 24 HU/px 가 아니다). 코퍼스에서 `imgDim` 을 저장한 그림 1,278장은 해상도
//! (72~800dpi)와 무관하게 `imgDim / 픽셀` 이 거의 모두 75.0 이다. dpi 로 풀면 이 그림의 crop 창은 오른쪽 끝이 이미지
//! 너비의 3배 밖(184861 / 24 = 7703px)으로 나가 창의 9% 만 이미지와 겹친다.
//!
//! **독립 근거는 둘이다.** (1) 파일이 저장한 `imgDim`(위). (2) 한컴 PDF: `pdf/1613000-202200037-air-traffic-controller-cbta-2020.pdf`
//! 48쪽과 이 문서의 우리 출력이 실루엣 일치율 98.3% 다(`macos/scripts/fidelity-sweep.py`; 51쪽 98.8%, 63쪽 98.7% 도
//! 같은 문서의 300dpi 스캔). 코퍼스 통계는 `mydocs/tech/macos_native_app_architecture.md` 의 "엔진 규칙 두 건 재조사" 에 있다.
//! 이 시험은 해상도로 crop 을 푸는 "일반화"를 막는 가드이고 결함 검출을 주장하지 않는다(수정 전 코드에서도 통과한다).
//! `imgDim` 이 없는 구형 파일의 경로는 한컴 근거가 없어 이 시험이 다루지 않는다.
//!
//! 위치·픽셀 해시가 아니라 **crop 창과 이미지의 포함 관계**와 기준 배율을 검사한다.

use std::path::{Path, PathBuf};

const SAMPLE: &str = "samples/issue6764/1613000-202200037-air-traffic-controller-cbta.hwp";
/// 48쪽(0-base 47). 쪽 번호는 `fidelity-sweep.py` 의 레이어 트리 JSON `page-048` 로 확인했다.
const PAGE: u32 = 47;
const IMAGE_PX: (f64, f64) = (2550.0, 3300.0);
const CROP_HU: (f64, f64, f64, f64) = (7675.0, 7595.0, 184861.0, 243129.0);
/// 파일이 저장한 crop 기준 크기(imgDim, HU). 75 HU/px × 픽셀과 0.02% 안에서 같다.
const IMG_DIM_HU: (f64, f64) = (191280.0, 247500.0);

fn sample_path(rel: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(rel)
}

/// SVG 에서 `<svg … viewBox="x y w h" …><image width="2550" height="3300"` 꼴의 crop 창을 모두 뽑는다.
fn crop_windows_of_image(svg: &str, image_px: (f64, f64)) -> Vec<(f64, f64, f64, f64)> {
    let image_tag = format!("<image width=\"{}\" height=\"{}\"", image_px.0, image_px.1);
    let mut windows = Vec::new();
    for chunk in svg.split("viewBox=\"").skip(1) {
        let Some((values, rest)) = chunk.split_once('"') else {
            continue;
        };
        // 이 viewBox 를 가진 중첩 <svg> 의 첫 자식이 우리 그림이어야 한다.
        if !rest
            .split_once("<image")
            .is_some_and(|(between, _)| !between.contains("</svg>"))
            || !rest.contains(&image_tag)
        {
            continue;
        }
        let numbers: Vec<f64> = values
            .split_whitespace()
            .filter_map(|v| v.parse().ok())
            .collect();
        if let [x, y, w, h] = numbers[..] {
            windows.push((x, y, w, h));
        }
    }
    windows
}

#[test]
fn scan_picture_crop_uses_stored_img_dim_not_image_dpi() {
    let bytes = std::fs::read(sample_path(SAMPLE)).expect("스캔 그림 샘플 읽기");
    let doc = rhwp::document_api::HwpDocument::from_bytes(&bytes).expect("샘플 파싱");
    let svg = doc.render_page_svg_native(PAGE).expect("48쪽 렌더");

    let windows = crop_windows_of_image(&svg, IMAGE_PX);
    // 0건이면 이 시험은 아무것도 지키지 않는다 — 조용히 통과시키지 않는다.
    assert!(
        !windows.is_empty(),
        "48쪽에서 2550×3300 스캔 그림의 crop 창(viewBox)을 찾지 못했다 — 샘플·쪽 번호 전제가 깨졌다"
    );

    // 파일이 저장한 기준 크기로 푼 배율은 75 HU/px 근방이어야 한다(해상도 24 HU/px 가 아니다).
    let scale = (IMG_DIM_HU.0 / IMAGE_PX.0, IMG_DIM_HU.1 / IMAGE_PX.1);
    assert!(
        (scale.0 - 75.0).abs() < 0.1 && (scale.1 - 75.0).abs() < 0.1,
        "imgDim 이 가리키는 배율이 75 HU/px 근방이 아니다: {scale:?}"
    );
    let expected = (
        CROP_HU.0 / scale.0,
        CROP_HU.1 / scale.1,
        (CROP_HU.2 - CROP_HU.0) / scale.0,
        (CROP_HU.3 - CROP_HU.1) / scale.1,
    );
    for (x, y, w, h) in windows {
        assert!(
            (x - expected.0).abs() < 0.01
                && (y - expected.1).abs() < 0.01
                && (w - expected.2).abs() < 0.01
                && (h - expected.3).abs() < 0.01,
            "crop 창이 imgDim(≈75 HU/px) 해석 {expected:?} 와 다르다: ({x}, {y}, {w}, {h}) — \
             dpi(300 → 24 HU/px)로 푸는 변경이 들어갔는지 확인할 것"
        );
        // 창이 이미지 안에 든다(한컴 PDF 가 그리는 영역과 같은 쪽 전체 스캔).
        assert!(x >= 0.0 && y >= 0.0, "crop 창이 이미지 왼쪽·위로 나갔다");
        assert!(
            x + w <= IMAGE_PX.0 + 0.5 && y + h <= IMAGE_PX.1 + 0.5,
            "crop 창이 이미지 오른쪽·아래로 나갔다: ({x}, {y}, {w}, {h})"
        );
    }
}
