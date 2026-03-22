use serde::{Deserialize, Serialize};
use super::plugin::Plugin;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GenerationConfig {
    pub prompt: String,
    pub format: String,
    pub channel_layout: String,
    pub preset_count: i32,
    pub agent: String,
    pub model: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RefineConfig {
    pub plugin: Plugin,
    pub modification: String,
}
