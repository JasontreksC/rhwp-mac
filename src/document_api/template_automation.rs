//! Thin template automation adapter. All parsing/preparation/mutation lives in core.
use super::HwpDocument;
use crate::error::HwpError;

impl HwpDocument {
    /// Import from a distinct, read-only document handle; no source bytes in JSON.
    /// Options JSON: {request:{sourceSection,sourceStart,sourceEnd,targetSection,insertBefore,count,limits?},dryRun?:boolean}.
    pub fn import_paragraph_block(
        &mut self,
        source: &HwpDocument,
        options_json: &str,
    ) -> Result<String, HwpError> {
        self.import_paragraph_block_json_native(source.document(), options_json)
            .map_err(HwpError::from)
    }

    /// Options JSON: {operation:{action,request},dryRun?:boolean}.
    /// Preview prepares detached changes; it never mutates or saves the document.
    pub fn apply_template_operation(&mut self, options_json: &str) -> Result<String, HwpError> {
        self.apply_template_operation_json_native(options_json)
            .map_err(HwpError::from)
    }
}
