//! C ABI entry points for language bindings.
//!
//! The API mirrors the CLI `export-text` and `export-markdown` commands and
//! returns a UTF-8 JSON result string. Call `rhwp_string_free` for every string
//! returned from this module.

use std::ffi::{CStr, CString};
use std::fs;
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use rhwp_core::paint::{LayerJsonOptions, RenderProfile};
use rhwp_core::wasm_api::HwpDocument;

const ALL_PAGES: i32 = -1;

#[no_mangle]
pub extern "C" fn rhwp_export_text(
    input_path: *const c_char,
    output_dir: *const c_char,
    page: i32,
) -> *mut c_char {
    ffi_result(|| {
        let input_path = read_utf8(input_path, "input_path")?;
        let output_dir = read_utf8(output_dir, "output_dir")?;
        export_text_to_dir(
            Path::new(&input_path),
            Path::new(&output_dir),
            normalize_page(page)?,
        )
    })
}

#[no_mangle]
pub extern "C" fn rhwp_export_markdown(
    input_path: *const c_char,
    output_dir: *const c_char,
    page: i32,
) -> *mut c_char {
    ffi_result(|| {
        let input_path = read_utf8(input_path, "input_path")?;
        let output_dir = read_utf8(output_dir, "output_dir")?;
        export_markdown_to_dir(
            Path::new(&input_path),
            Path::new(&output_dir),
            normalize_page(page)?,
        )
    })
}

#[no_mangle]
pub extern "C" fn rhwp_read_text(input_path: *const c_char, page: i32) -> *mut c_char {
    ffi_result(|| {
        let input_path = read_utf8(input_path, "input_path")?;
        read_text(Path::new(&input_path), normalize_page(page)?)
    })
}

// ── 핸들 기반 문서 API ──────────────────────────────────────────────────────
//
// 위의 무상태 함수들은 호출마다 파일을 다시 파싱한다. 네이티브 앱은 문서를 한 번 열어 두고
// 쪽 단위로 반복 질의해야 하므로, 열린 문서를 불투명 핸들로 돌려주는 API를 따로 둔다.
//
// 소유권 규칙
// - `rhwp_document_open*` 가 돌려준 핸들은 호출자 소유이며 `rhwp_document_free` 로 한 번만 해제한다.
// - 핸들을 쓰는 함수가 돌려준 문자열은 `rhwp_string_free` 로 해제한다.
// - 해제한 핸들이나 다른 곳에서 온 포인터를 넘기면 정의되지 않은 동작이다(널은 안전하게 거부한다).
//
// 동시성 규칙
// - 핸들은 스레드 안전을 약속하지 않는다. 호출자(Swift의 actor)가 호출을 직렬화해야 한다.
//   그래도 내부 Mutex가 동시 호출을 직렬화하므로 데이터 경쟁은 생기지 않는다.
// - 호출 중 panic이 나면 문서 상태를 신뢰할 수 없으므로 Mutex가 poison되고, 이후 호출은
//   손상됐을 수 있는 문서를 다시 쓰지 않고 오류를 돌려준다. 문서를 다시 열어야 한다.

/// 열린 문서. C 쪽에는 `typedef struct RhwpDocument RhwpDocument;` 불투명 타입으로만 보인다.
pub struct RhwpDocument {
    inner: Mutex<HwpDocument>,
}

const NULL_HANDLE_ERROR: &str = "문서 핸들이 null입니다.";
const POISONED_ERROR: &str =
    "이전 호출에서 panic이 발생해 문서 상태를 신뢰할 수 없습니다. 문서를 다시 여십시오.";
const PANIC_ERROR: &str = "FFI 호출 중 panic이 발생했습니다.";

/// 경로의 HWP/HWPX/HWP3 파일을 열어 핸들을 돌려준다.
///
/// 실패하면 널을 돌려주고, `out_error` 가 널이 아니면 `{"ok":false,"error":"..."}` 를 써 준다.
/// 성공하면 `*out_error` 는 널이 된다. 쓴 문자열은 `rhwp_string_free` 로 해제한다.
///
/// # Safety
///
/// `path` 는 NUL로 끝나는 UTF-8 문자열이거나 널이어야 하고, `out_error` 는 쓸 수 있는
/// `char *` 위치이거나 널이어야 한다.
#[no_mangle]
pub unsafe extern "C" fn rhwp_document_open(
    path: *const c_char,
    out_error: *mut *mut c_char,
) -> *mut RhwpDocument {
    open_document(out_error, || {
        let path = read_utf8(path, "path")?;
        let data = fs::read(&path).map_err(|e| format!("파일을 읽을 수 없습니다 - {path}: {e}"))?;
        parse_document(&data)
    })
}

/// 메모리의 파일 내용(`data`, `len` 바이트)으로 문서를 열어 핸들을 돌려준다.
/// 오류 보고와 해제 규칙은 `rhwp_document_open` 과 같다. 바이트는 호출 안에서 복사되므로
/// 호출이 끝나면 호출자가 버려도 된다.
///
/// # Safety
///
/// `data` 는 `len` 바이트를 읽을 수 있는 포인터이거나 널이어야 하고, `out_error` 는 쓸 수 있는
/// `char *` 위치이거나 널이어야 한다.
#[no_mangle]
pub unsafe extern "C" fn rhwp_document_open_bytes(
    data: *const u8,
    len: usize,
    out_error: *mut *mut c_char,
) -> *mut RhwpDocument {
    open_document(out_error, || {
        if data.is_null() {
            return Err("data가 null입니다.".to_string());
        }
        // SAFETY: 호출자가 `data` 가 `len` 바이트를 읽을 수 있음을 보장한다.
        let bytes = unsafe { std::slice::from_raw_parts(data, len) };
        parse_document(bytes)
    })
}

/// 문서의 전체 쪽수를 돌려준다. 핸들이 널이거나 이전 호출에서 panic이 난 문서면 -1.
///
/// # Safety
///
/// `doc` 은 `rhwp_document_open*` 가 돌려준 아직 해제하지 않은 핸들이거나 널이어야 한다.
#[no_mangle]
pub unsafe extern "C" fn rhwp_document_page_count(doc: *const RhwpDocument) -> i32 {
    with_document(doc, |doc| Ok(doc.page_count()))
        .map(|count| i32::try_from(count).unwrap_or(i32::MAX))
        .unwrap_or(-1)
}

/// 한 쪽(0부터)의 레이어 트리(PaintOp IR)를 JSON으로 돌려준다.
///
/// 반환 JSON: `{"ok":true,"pageCount":N,"page":P,"layerTree":{...}}` 또는 `{"ok":false,"error":"..."}`.
/// `layerTree` 는 `get_page_layer_tree_with_options_native` 원문을 이스케이프 없이 싣는다.
///
/// # Safety
///
/// `doc` 은 `rhwp_document_open*` 가 돌려준 아직 해제하지 않은 핸들이거나 널이어야 한다.
#[no_mangle]
pub unsafe extern "C" fn rhwp_document_page_layer_tree(
    doc: *const RhwpDocument,
    page: u32,
) -> *mut c_char {
    ffi_result(|| with_document(doc, |doc| layer_tree_envelope(doc, page)))
}

/// 핸들을 해제한다. 널은 무시한다.
///
/// # Safety
///
/// `doc` 은 `rhwp_document_open*` 가 돌려준 핸들이거나 널이어야 하며, 한 번만 해제해야 한다.
/// 해제한 뒤에는 어떤 함수에도 넘기면 안 된다.
#[no_mangle]
pub unsafe extern "C" fn rhwp_document_free(doc: *mut RhwpDocument) {
    if doc.is_null() {
        return;
    }
    // 문서 소멸 중 panic이 C 쪽으로 풀려나가지 않게 막는다. 결과는 돌려줄 곳이 없다.
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        // SAFETY: 널이 아니고 `rhwp_document_open*` 의 `Box::into_raw` 가 만든 포인터다.
        drop(unsafe { Box::from_raw(doc) });
    }));
}

/// 이 모듈이 돌려준 문자열을 해제한다.
///
/// # Safety
///
/// `ptr` 은 이 모듈의 함수가 돌려준(또는 `out_error` 로 써 준) 문자열 포인터이거나 널이어야 한다.
/// 다른 할당자에서 온 포인터를 넘기거나 같은 포인터를 두 번 넘기면 정의되지 않은 동작이다.
///
/// C ABI 심볼은 바뀌지 않으므로 C#·Swift 등 호출 측 선언은 그대로 쓸 수 있다.
#[no_mangle]
pub unsafe extern "C" fn rhwp_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }

    unsafe {
        drop(CString::from_raw(ptr));
    }
}

fn export_text_to_dir(
    input_path: &Path,
    output_dir: &Path,
    target_page: Option<u32>,
) -> Result<String, String> {
    let data = fs::read(input_path)
        .map_err(|e| format!("파일을 읽을 수 없습니다 - {}: {}", input_path.display(), e))?;
    let doc = HwpDocument::from_bytes(&data).map_err(|e| format!("HWP 파싱 실패 - {}", e))?;
    let page_count = doc.page_count();
    let pages = select_pages(page_count, target_page)?;
    fs::create_dir_all(output_dir).map_err(|e| {
        format!(
            "출력 폴더를 생성할 수 없습니다 - {}: {}",
            output_dir.display(),
            e
        )
    })?;

    let file_stem = file_stem(input_path);
    let mut written = Vec::new();

    for page_num in pages {
        let mut text = doc
            .extract_page_text_native(page_num)
            .map_err(|e| format!("페이지 {} 텍스트 추출 실패 - {:?}", page_num, e))?;
        ensure_trailing_newline(&mut text);

        let output_path = output_dir.join(page_file_name(&file_stem, "txt", page_count, page_num));
        fs::write(&output_path, text.as_bytes())
            .map_err(|e| format!("TXT 저장 실패 - {}: {}", output_path.display(), e))?;
        written.push(output_path);
    }

    Ok(success_json(page_count, &written, None))
}

fn read_text(input_path: &Path, target_page: Option<u32>) -> Result<String, String> {
    let data = fs::read(input_path)
        .map_err(|e| format!("파일을 읽을 수 없습니다 - {}: {}", input_path.display(), e))?;
    let doc = HwpDocument::from_bytes(&data).map_err(|e| format!("HWP 파싱 실패 - {}", e))?;
    let page_count = doc.page_count();
    let pages = select_pages(page_count, target_page)?;

    let mut extracted = Vec::new();
    for page_num in pages {
        let mut text = doc
            .extract_page_text_native(page_num)
            .map_err(|e| format!("페이지 {} 텍스트 추출 실패 - {:?}", page_num, e))?;
        ensure_trailing_newline(&mut text);
        extracted.push((page_num, text));
    }

    Ok(text_json(page_count, &extracted))
}

fn parse_document(data: &[u8]) -> Result<HwpDocument, String> {
    HwpDocument::from_bytes(data).map_err(|e| format!("HWP 파싱 실패 - {}", e))
}

/// 문서를 여는 두 진입점의 공통 뒤처리. 성공이면 핸들을 만들고 `*out_error` 를 비우며,
/// 실패(panic 포함)면 오류 JSON을 `*out_error` 에 쓰고 널을 돌려준다.
fn open_document<F>(out_error: *mut *mut c_char, open: F) -> *mut RhwpDocument
where
    F: FnOnce() -> Result<HwpDocument, String> + std::panic::UnwindSafe,
{
    let result = std::panic::catch_unwind(open).unwrap_or_else(|_| Err(PANIC_ERROR.to_string()));
    match result {
        Ok(document) => {
            write_out_error(out_error, std::ptr::null_mut());
            Box::into_raw(Box::new(RhwpDocument {
                inner: Mutex::new(document),
            }))
        }
        Err(message) => {
            write_out_error(out_error, json_c_string(&error_json(&message)));
            std::ptr::null_mut()
        }
    }
}

fn write_out_error(out_error: *mut *mut c_char, value: *mut c_char) {
    if !out_error.is_null() {
        // SAFETY: 호출자가 `out_error` 가 쓸 수 있는 위치임을 보장한다.
        unsafe { *out_error = value };
    }
}

/// 핸들이 가리키는 문서를 잠그고 `f` 를 실행한다. 널 핸들, poison된 문서, panic은 오류로 바꾼다.
///
/// panic을 잠금 **바깥**에서 잡아야 한다. 안쪽에서 잡으면 guard가 정상 해제되어 Mutex가
/// poison되지 않고, 손상됐을 수 있는 문서가 다음 호출에 그대로 쓰인다.
fn with_document<R>(
    doc: *const RhwpDocument,
    f: impl FnOnce(&HwpDocument) -> Result<R, String>,
) -> Result<R, String> {
    // SAFETY: 호출자가 `doc` 이 널이거나 해제되지 않은 핸들임을 보장한다.
    let doc = unsafe { doc.as_ref() }.ok_or_else(|| NULL_HANDLE_ERROR.to_string())?;
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let guard = doc.inner.lock().map_err(|_| POISONED_ERROR.to_string())?;
        f(&guard)
    }))
    .unwrap_or_else(|_| Err(PANIC_ERROR.to_string()))
}

fn json_c_string(json: &str) -> *mut c_char {
    CString::new(json)
        .unwrap_or_else(|_| {
            CString::new(error_json("결과 문자열에 NUL 문자가 포함되었습니다.")).unwrap()
        })
        .into_raw()
}

fn layer_tree_envelope(doc: &HwpDocument, page: u32) -> Result<String, String> {
    let page_count = doc.page_count();
    // 범위 검사는 기존 경로와 같은 규칙(select_pages)을 재사용한다.
    select_pages(page_count, Some(page))?;

    let layer_tree = doc
        .get_page_layer_tree_with_options_native(
            page,
            RenderProfile::Screen,
            LayerJsonOptions::default(),
        )
        .map_err(|e| format!("페이지 {} 레이어 트리 생성 실패 - {:?}", page, e))?;

    // layerTree는 이미 유효한 JSON이므로 이스케이프 없이 그대로 끼워 넣는다.
    Ok(format!(
        "{{\"ok\":true,\"pageCount\":{},\"page\":{},\"layerTree\":{}}}",
        page_count, page, layer_tree
    ))
}

fn export_markdown_to_dir(
    input_path: &Path,
    output_dir: &Path,
    target_page: Option<u32>,
) -> Result<String, String> {
    let data = fs::read(input_path)
        .map_err(|e| format!("파일을 읽을 수 없습니다 - {}: {}", input_path.display(), e))?;
    let doc = HwpDocument::from_bytes(&data).map_err(|e| format!("HWP 파싱 실패 - {}", e))?;
    let page_count = doc.page_count();
    let pages = select_pages(page_count, target_page)?;
    fs::create_dir_all(output_dir).map_err(|e| {
        format!(
            "출력 폴더를 생성할 수 없습니다 - {}: {}",
            output_dir.display(),
            e
        )
    })?;

    let file_stem = file_stem(input_path);
    let assets_dir_name = format!("{}_assets", file_stem);
    let assets_dir_path = output_dir.join(&assets_dir_name);
    let mut written = Vec::new();
    let mut written_image_count = 0usize;

    for page_num in pages {
        let (mut markdown, image_refs) = doc
            .extract_page_markdown_with_images_native(page_num)
            .map_err(|e| format!("페이지 {} Markdown 생성 실패 - {:?}", page_num, e))?;

        for (img_idx, (sec_idx, para_idx, control_idx, bin_data_id)) in
            image_refs.iter().enumerate()
        {
            let token = format!("[[RHWP_IMAGE:{}]]", img_idx + 1);
            let Some((mime, image_data)) =
                extract_image_data(&doc, *sec_idx, *para_idx, *control_idx, *bin_data_id)?
            else {
                markdown = markdown.replace(&token, "");
                continue;
            };

            fs::create_dir_all(&assets_dir_path).map_err(|e| {
                format!(
                    "이미지 출력 폴더 생성 실패 - {}: {}",
                    assets_dir_path.display(),
                    e
                )
            })?;

            let image_filename = format!(
                "{}_p{:03}_img{:03}.{}",
                file_stem,
                page_num + 1,
                img_idx + 1,
                mime_to_ext(&mime),
            );
            let image_path = assets_dir_path.join(&image_filename);
            fs::write(&image_path, &image_data)
                .map_err(|e| format!("이미지 저장 실패 - {}: {}", image_path.display(), e))?;

            let image_link = format!(
                "![image {}]({}/{})",
                img_idx + 1,
                assets_dir_name,
                image_filename
            );
            markdown = markdown.replace(&token, &image_link);
            written_image_count += 1;
        }

        ensure_trailing_newline(&mut markdown);
        let output_path = output_dir.join(page_file_name(&file_stem, "md", page_count, page_num));
        fs::write(&output_path, markdown.as_bytes())
            .map_err(|e| format!("Markdown 저장 실패 - {}: {}", output_path.display(), e))?;
        written.push(output_path);
    }

    Ok(success_json(
        page_count,
        &written,
        Some(written_image_count),
    ))
}

fn extract_image_data(
    doc: &HwpDocument,
    sec_idx: Option<usize>,
    para_idx: Option<usize>,
    control_idx: Option<usize>,
    bin_data_id: u16,
) -> Result<Option<(String, Vec<u8>)>, String> {
    if let (Some(si), Some(pi), Some(ci)) = (sec_idx, para_idx, control_idx) {
        // [#1161] cell_path 가 비면 본문 문단. FFI 표면은 셀/글상자 안 컨트롤을
        // 아직 지정할 수 없으므로 본문으로 고정한다 — `src/main.rs` 의 CLI 경로와 같다.
        const BODY_PARA: &[(usize, usize, usize)] = &[];
        if let (Ok(mime), Ok(data)) = (
            doc.get_control_image_mime_native(si, pi, BODY_PARA, ci),
            doc.get_control_image_data_native(si, pi, BODY_PARA, ci),
        ) {
            return Ok(Some((mime, data)));
        }
    }

    if bin_data_id == 0 {
        return Ok(None);
    }

    let mime = doc
        .get_bin_data_image_mime_native(bin_data_id)
        .map_err(|e| format!("이미지 MIME fallback 실패 (bin={}): {:?}", bin_data_id, e))?;
    let data = doc
        .get_bin_data_image_data_native(bin_data_id)
        .map_err(|e| format!("이미지 데이터 fallback 실패 (bin={}): {:?}", bin_data_id, e))?;
    Ok(Some((mime, data)))
}

fn select_pages(page_count: u32, target_page: Option<u32>) -> Result<Vec<u32>, String> {
    if page_count == 0 {
        return Err("문서에 페이지가 없습니다.".to_string());
    }

    match target_page {
        Some(page) if page >= page_count => Err(format!(
            "페이지 번호가 범위를 벗어났습니다 (0~{})",
            page_count - 1
        )),
        Some(page) => Ok(vec![page]),
        None => Ok((0..page_count).collect()),
    }
}

fn normalize_page(page: i32) -> Result<Option<u32>, String> {
    if page == ALL_PAGES {
        Ok(None)
    } else if page < 0 {
        Err("page는 -1(전체) 또는 0 이상의 페이지 번호여야 합니다.".to_string())
    } else {
        Ok(Some(page as u32))
    }
}

fn read_utf8(ptr: *const c_char, name: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{}가 null입니다.", name));
    }

    unsafe {
        CStr::from_ptr(ptr)
            .to_str()
            .map(|s| s.to_string())
            .map_err(|e| format!("{}는 유효한 UTF-8 문자열이어야 합니다: {}", name, e))
    }
}

fn ffi_result<F>(f: F) -> *mut c_char
where
    F: FnOnce() -> Result<String, String> + std::panic::UnwindSafe,
{
    let json = match std::panic::catch_unwind(f) {
        Ok(Ok(json)) => json,
        Ok(Err(error)) => error_json(&error),
        Err(_) => error_json("FFI 호출 중 panic이 발생했습니다."),
    };

    json_c_string(&json)
}

fn file_stem(path: &Path) -> String {
    path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("page")
        .to_string()
}

fn page_file_name(file_stem: &str, ext: &str, page_count: u32, page_num: u32) -> String {
    if page_count == 1 {
        format!("{}.{}", file_stem, ext)
    } else {
        format!("{}_{:03}.{}", file_stem, page_num + 1, ext)
    }
}

fn ensure_trailing_newline(s: &mut String) {
    if !s.ends_with('\n') {
        s.push('\n');
    }
}

fn mime_to_ext(mime: &str) -> &'static str {
    match mime {
        "image/png" => "png",
        "image/jpeg" => "jpg",
        "image/gif" => "gif",
        "image/bmp" => "bmp",
        "image/webp" => "webp",
        _ => "bin",
    }
}

fn success_json(page_count: u32, files: &[PathBuf], image_count: Option<usize>) -> String {
    let files_json = files
        .iter()
        .map(|p| format!("\"{}\"", json_escape(&p.display().to_string())))
        .collect::<Vec<_>>()
        .join(",");
    let image_json = image_count
        .map(|count| format!(",\"imageCount\":{}", count))
        .unwrap_or_default();

    format!(
        "{{\"ok\":true,\"pageCount\":{},\"files\":[{}]{}}}",
        page_count, files_json, image_json
    )
}

fn error_json(error: &str) -> String {
    format!("{{\"ok\":false,\"error\":\"{}\"}}", json_escape(error))
}

fn text_json(page_count: u32, pages: &[(u32, String)]) -> String {
    let pages_json = pages
        .iter()
        .map(|(index, text)| format!("{{\"index\":{},\"text\":\"{}\"}}", index, json_escape(text)))
        .collect::<Vec<_>>()
        .join(",");

    format!(
        "{{\"ok\":true,\"pageCount\":{},\"pages\":[{}]}}",
        page_count, pages_json
    )
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c < '\u{20}' => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;
    use std::ptr;

    /// 저장소 루트 기준 샘플 경로. 파일이 없으면 조용히 통과하지 않고 실패시킨다.
    fn sample(name: &str) -> PathBuf {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../samples")
            .join(name);
        assert!(path.exists(), "샘플 파일 없음: {}", path.display());
        path
    }

    fn c_path(path: &Path) -> CString {
        CString::new(path.to_str().unwrap()).unwrap()
    }

    /// 돌려받은 C 문자열을 Rust 문자열로 옮기고 해제한다.
    fn take_string(raw: *mut c_char) -> String {
        assert!(!raw.is_null(), "문자열 포인터가 null");
        let text = unsafe { CStr::from_ptr(raw) }.to_str().unwrap().to_owned();
        unsafe { rhwp_string_free(raw) };
        text
    }

    fn open_sample(name: &str) -> *mut RhwpDocument {
        let path = c_path(&sample(name));
        let mut error: *mut c_char = ptr::null_mut();
        let doc = unsafe { rhwp_document_open(path.as_ptr(), &mut error) };
        assert!(!doc.is_null(), "문서 열기 실패");
        assert!(error.is_null(), "성공 시 out_error는 null이어야 함");
        doc
    }

    #[test]
    fn open_reports_page_count_and_closes() {
        let doc = open_sample("KTX.hwp");
        // 한컴 PDF(pdf/KTX-2022.pdf)가 27쪽이다. 쪽수는 독립 기준에서 정한 값이다.
        assert_eq!(unsafe { rhwp_document_page_count(doc) }, 27);
        unsafe { rhwp_document_free(doc) };
    }

    #[test]
    fn open_bytes_matches_open_path() {
        let bytes = std::fs::read(sample("KTX.hwp")).unwrap();
        let mut error: *mut c_char = ptr::null_mut();
        let doc = unsafe { rhwp_document_open_bytes(bytes.as_ptr(), bytes.len(), &mut error) };
        assert!(!doc.is_null() && error.is_null());
        assert_eq!(unsafe { rhwp_document_page_count(doc) }, 27);
        unsafe { rhwp_document_free(doc) };
    }

    #[test]
    fn layer_tree_envelope_wraps_raw_layer_json() {
        let doc = open_sample("KTX.hwp");
        let json = take_string(unsafe { rhwp_document_page_layer_tree(doc, 0) });
        unsafe { rhwp_document_free(doc) };

        // 봉투 필드와, Swift 렌더러가 소비하는 최상위 필드가 모두 실려 있어야 한다.
        assert!(
            json.starts_with("{\"ok\":true,\"pageCount\":27,"),
            "{json:.80}"
        );
        assert!(json.contains("\"page\":0,\"layerTree\":{"));
        assert!(json.contains("\"coordinateSystem\":\"page-top-left-y-down\""));
        assert!(json.contains("\"pageWidth\":") && json.contains("\"pageHeight\":"));
        // 레이어 트리 원문은 이스케이프 없이 그대로 들어간다(문자열 안에 갇히면 안 된다).
        assert!(!json.contains("\\\"layerTree\\\""));
        assert!(json.ends_with('}'));
    }

    #[test]
    fn repeated_queries_on_one_handle_are_consistent() {
        // 핸들의 존재 이유: 한 번 열고 여러 쪽·같은 쪽을 반복 질의해도 결과가 변하지 않아야 한다.
        let doc = open_sample("KTX.hwp");
        let first = take_string(unsafe { rhwp_document_page_layer_tree(doc, 3) });
        let other = take_string(unsafe { rhwp_document_page_layer_tree(doc, 5) });
        let again = take_string(unsafe { rhwp_document_page_layer_tree(doc, 3) });
        unsafe { rhwp_document_free(doc) };

        assert_eq!(first, again, "같은 쪽 재질의 결과가 달라짐");
        assert_ne!(first, other, "서로 다른 쪽이 같은 JSON을 돌려줌");
        assert!(other.contains("\"page\":5,"));
    }

    #[test]
    fn layer_tree_rejects_out_of_range_page() {
        let doc = open_sample("KTX.hwp");
        let json = take_string(unsafe { rhwp_document_page_layer_tree(doc, 27) });
        unsafe { rhwp_document_free(doc) };
        assert!(json.starts_with("{\"ok\":false"), "{json}");
        assert!(json.contains("범위를 벗어났습니다"), "{json}");
    }

    #[test]
    fn open_missing_file_reports_error_and_null_handle() {
        let path = CString::new("/nonexistent/rhwp.hwp").unwrap();
        let mut error: *mut c_char = ptr::null_mut();
        let doc = unsafe { rhwp_document_open(path.as_ptr(), &mut error) };
        assert!(doc.is_null());
        let json = take_string(error);
        assert!(json.starts_with("{\"ok\":false"), "{json}");
        assert!(json.contains("파일을 읽을 수 없습니다"), "{json}");
    }

    #[test]
    fn open_garbage_bytes_reports_parse_error() {
        let junk = b"this is not a hwp file";
        let mut error: *mut c_char = ptr::null_mut();
        let doc = unsafe { rhwp_document_open_bytes(junk.as_ptr(), junk.len(), &mut error) };
        assert!(doc.is_null());
        assert!(take_string(error).contains("HWP 파싱 실패"));
    }

    #[test]
    fn open_tolerates_null_arguments() {
        // out_error가 널이어도 실패를 널 핸들로만 알리고 죽지 않는다.
        assert!(unsafe { rhwp_document_open(ptr::null(), ptr::null_mut()) }.is_null());
        assert!(unsafe { rhwp_document_open_bytes(ptr::null(), 0, ptr::null_mut()) }.is_null());

        // 널 경로는 out_error에 오류 봉투를 남긴다.
        let mut error: *mut c_char = ptr::null_mut();
        assert!(unsafe { rhwp_document_open(ptr::null(), &mut error) }.is_null());
        assert!(take_string(error).contains("path가 null"));
    }

    #[test]
    fn null_handle_is_rejected_not_dereferenced() {
        assert_eq!(unsafe { rhwp_document_page_count(ptr::null()) }, -1);
        let json = take_string(unsafe { rhwp_document_page_layer_tree(ptr::null(), 0) });
        assert!(json.contains(NULL_HANDLE_ERROR), "{json}");
        // 널 해제는 무시한다.
        unsafe { rhwp_document_free(ptr::null_mut()) };
        unsafe { rhwp_string_free(ptr::null_mut()) };
    }

    #[test]
    fn panic_poisons_handle_and_later_calls_fail_closed() {
        let doc = open_sample("KTX.hwp");

        // 호출 도중 panic은 C 쪽으로 풀려나가지 않고 오류로 바뀐다.
        let result: Result<(), String> = with_document(doc, |_| panic!("의도한 panic"));
        assert_eq!(result, Err(PANIC_ERROR.to_string()));

        // 손상됐을 수 있는 문서는 이후 호출에서 다시 쓰이지 않는다.
        assert_eq!(unsafe { rhwp_document_page_count(doc) }, -1);
        let json = take_string(unsafe { rhwp_document_page_layer_tree(doc, 0) });
        assert!(json.contains("panic이 발생해"), "{json}");

        // poison된 핸들도 해제는 정상이어야 한다.
        unsafe { rhwp_document_free(doc) };
    }

    /// Swift actor 는 `await` 사이에 실행 스레드를 옮길 수 있다. 문서를 연 스레드와 다른 스레드에서
    /// 질의해도 같은 스레드에서의 결과와 같아야 한다(스레드 로컬 상태에 기대지 않는다는 계약).
    #[test]
    fn handle_gives_same_result_on_another_thread() {
        // 컴파일 타임 검사: 문서가 `Send` 가 아니면 핸들을 스레드 사이로 옮길 수 없다.
        fn assert_send<T: Send>() {}
        assert_send::<HwpDocument>();

        let same_thread = {
            let doc = open_sample("KTX.hwp");
            let json = take_string(unsafe { rhwp_document_page_layer_tree(doc, 3) });
            unsafe { rhwp_document_free(doc) };
            json
        };

        // 스레드 A 에서 열고, 스레드 B 에서 질의하고, 이 스레드에서 해제한다.
        // 원시 포인터는 `Send` 가 아니므로 주소로 넘긴다.
        let opened_on_a = std::thread::spawn(|| open_sample("KTX.hwp") as usize)
            .join()
            .unwrap();
        let queried_on_b = std::thread::spawn(move || {
            let doc = opened_on_a as *const RhwpDocument;
            take_string(unsafe { rhwp_document_page_layer_tree(doc, 3) })
        })
        .join()
        .unwrap();
        unsafe { rhwp_document_free(opened_on_a as *mut RhwpDocument) };

        assert_eq!(same_thread, queried_on_b, "스레드를 바꾸면 결과가 달라짐");
    }

    /// 호출자가 직렬화하지 못해 동시에 부르더라도 내부 Mutex 가 데이터 경쟁 없이 직렬화한다.
    #[test]
    fn concurrent_calls_on_one_handle_are_serialized() {
        let doc = open_sample("KTX.hwp") as usize;
        let workers: Vec<_> = (0..4)
            .map(|_| {
                std::thread::spawn(move || {
                    let doc = doc as *const RhwpDocument;
                    (0..25)
                        .map(|_| unsafe { rhwp_document_page_count(doc) })
                        .all(|count| count == 27)
                })
            })
            .collect();
        for worker in workers {
            assert!(worker.join().unwrap(), "동시 호출에서 쪽수가 흔들림");
        }
        unsafe { rhwp_document_free(doc as *mut RhwpDocument) };
    }

    /// 헤더가 선언한 함수 집합과 실제로 내보내는 `extern "C"` 함수 집합이 같아야 한다.
    /// 어긋나면 Swift가 없는 심볼을 선언하거나, 선언 없는 함수가 ABI에 남는다.
    #[test]
    fn header_declares_exactly_the_exported_symbols() {
        let header = include_str!("../include/rhwp_native.h");
        let source = include_str!("lib.rs");

        // 이 파일의 문자열 리터럴에 같은 패턴이 남지 않도록 검색어를 런타임에 조립한다.
        let needle = format!("extern \"C\" fn {}", "rhwp_");
        let exported: BTreeSet<String> = source
            .match_indices(&needle)
            .map(|(at, _)| {
                source[at + needle.len() - "rhwp_".len()..]
                    .chars()
                    .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                    .collect()
            })
            .collect();

        let declared: BTreeSet<String> = header
            .match_indices("rhwp_")
            .filter_map(|(at, _)| {
                let name: String = header[at..]
                    .chars()
                    .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                    .collect();
                // 함수 선언만 센다: 이름 바로 뒤가 `(` 인 경우.
                header[at + name.len()..].starts_with('(').then_some(name)
            })
            .collect();

        assert!(!exported.is_empty());
        assert_eq!(declared, exported, "헤더와 내보낸 심볼 불일치");
    }
}
