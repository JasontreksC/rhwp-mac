use super::HwpDocument;
use crate::error::HwpError;
use crate::renderer::supplemental_metrics::{MetricBackend, MetricContext};

impl HwpDocument {
    pub fn collect_canvas_metric_requests_js(
        &mut self,
        document: u32,
        fonts: u32,
    ) -> Result<String, HwpError> {
        let batch = self
            .collect_canvas_metric_requests(MetricContext {
                document_generation: document.into(),
                font_generation: fonts.into(),
                backend: MetricBackend::Canvas2d,
            })
            .map_err(|e| HwpError::other(&format!("Canvas metrics: {e:?}")))?;
        serde_json::to_string(&batch).map_err(|e| HwpError::other(&e.to_string()))
    }

    pub fn register_canvas_metric_replies_js(
        &mut self,
        document: u32,
        fonts: u32,
        revision: f64,
        json: &str,
    ) -> Result<bool, HwpError> {
        if !revision.is_finite()
            || revision < 0.0
            || revision > 9_007_199_254_740_991.0
            || revision.fract() != 0.0
            || json.len() > 8 * 1024 * 1024
        {
            return Err(HwpError::other("Invalid Canvas metric reply envelope"));
        }
        let replies = serde_json::from_str(json)
            .map_err(|e| HwpError::other(&format!("Canvas metrics: {e}")))?;
        self.register_canvas_metric_replies(
            MetricContext {
                document_generation: document.into(),
                font_generation: fonts.into(),
                backend: MetricBackend::Canvas2d,
            },
            revision as u64,
            replies,
        )
        .map_err(|e| HwpError::other(&format!("Canvas metrics: {e:?}")))
    }

    pub fn select_canvas_metrics_js(&mut self, enabled: bool) -> Result<bool, HwpError> {
        self.select_canvas_metrics(enabled)
            .map_err(|e| HwpError::other(&format!("Canvas metrics: {e:?}")))
    }

    pub fn canvas_metrics_active_js(&self) -> bool {
        self.canvas_metrics_active()
    }

    pub fn get_canvas_page_layer_tree_js(
        &self,
        page: u32,
        profile: &str,
        omit_font_bytes: bool,
    ) -> Result<String, HwpError> {
        let profile = crate::paint::RenderProfile::parse(profile)
            .ok_or_else(|| HwpError::other("Invalid render profile"))?;
        self.get_canvas_page_layer_tree_with_options_native(
            page,
            profile,
            crate::paint::LayerJsonOptions {
                omit_image_bytes: false,
                omit_font_bytes,
            },
        )
        .map_err(HwpError::from)
    }
}
