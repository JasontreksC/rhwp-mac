//! Studio 하이퍼링크의 엄격한 JSON options 어댑터 (#6963).
use super::HwpDocument;
use crate::document_core::hyperlink::HyperlinkTarget;
use crate::error::HwpError;
use serde::Deserialize;

fn parse<T: serde::de::DeserializeOwned>(json: &str) -> Result<T, HwpError> {
    serde_json::from_str(json).map_err(|e| HwpError::other(&e.to_string()))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct InsertOptions {
    target: HyperlinkTarget,
    start: usize,
    end: usize,
    uri: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UpdateOptions {
    target: HyperlinkTarget,
    field_id: u32,
    uri: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct TextOptions {
    target: HyperlinkTarget,
    field_id: u32,
    text: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RemoveOptions {
    target: HyperlinkTarget,
    field_id: u32,
    #[serde(default)]
    restore_formatting: bool,
}

impl HwpDocument {
    /// 표시 문자는 Unicode scalar 축이다. 대상 누락 시 본문으로 폴백하지 않는다.
    pub fn get_hyperlink_context(&self, target_json: &str) -> Result<String, HwpError> {
        let target: HyperlinkTarget = parse(target_json)?;
        let paragraph = self.core.hyperlink_paragraph(&target)?;
        Ok(serde_json::json!({
            "text": paragraph.text,
            "links": self.core.hyperlinks_native(&target)?,
        })
        .to_string())
    }

    pub fn insert_hyperlink_ex(&mut self, options_json: &str) -> Result<u32, HwpError> {
        let o: InsertOptions = parse(options_json)?;
        self.core
            .insert_hyperlink_native(&o.target, o.start, o.end, &o.uri)
            .map_err(Into::into)
    }

    pub fn update_hyperlink_ex(&mut self, options_json: &str) -> Result<bool, HwpError> {
        let o: UpdateOptions = parse(options_json)?;
        self.core
            .update_hyperlink_native(&o.target, o.field_id, &o.uri)
            .map_err(Into::into)
    }

    pub fn replace_hyperlink_text_ex(&mut self, options_json: &str) -> Result<bool, HwpError> {
        let o: TextOptions = parse(options_json)?;
        self.core
            .replace_hyperlink_text_native(&o.target, o.field_id, &o.text)
            .map_err(Into::into)
    }

    pub fn remove_hyperlink_ex(&mut self, options_json: &str) -> Result<(), HwpError> {
        let o: RemoveOptions = parse(options_json)?;
        self.core
            .remove_hyperlink_with_format_native(&o.target, o.field_id, o.restore_formatting)
            .map_err(Into::into)
    }
}
