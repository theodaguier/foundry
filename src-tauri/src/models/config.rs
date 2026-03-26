use super::plugin::Plugin;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GenerationDebugContext {
    pub trigger: String,
    #[serde(default)]
    pub previous_error: String,
    #[serde(default)]
    pub recent_logs: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GenerationConfig {
    pub prompt: String,
    #[serde(default)]
    pub plugin_type: Option<String>,
    pub format: String,
    pub channel_layout: String,
    pub preset_count: i32,
    pub agent: String,
    pub model: String,
    #[serde(default)]
    pub debug_pipeline: bool,
    #[serde(default)]
    pub debug_context: Option<GenerationDebugContext>,
    #[serde(default)]
    pub resume_plugin_id: Option<String>,
    #[serde(default)]
    pub resume_plugin_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RefineConfig {
    pub plugin: Plugin,
    pub modification: String,
}
