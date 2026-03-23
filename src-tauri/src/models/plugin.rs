use serde::{Deserialize, Serialize};

use super::agent::{AgentModel, GenerationAgent};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum PluginType {
    Instrument,
    Effect,
    Utility,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PluginFormat {
    #[serde(rename = "AU")]
    Au,
    #[serde(rename = "VST3")]
    Vst3,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum PluginStatus {
    Installed,
    Failed,
    Building,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct InstallPaths {
    pub au: Option<String>,
    pub vst3: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Plugin {
    pub id: String,
    pub name: String,
    #[serde(rename = "type")]
    pub plugin_type: PluginType,
    pub prompt: String,
    pub created_at: String,
    pub formats: Vec<PluginFormat>,
    pub install_paths: InstallPaths,
    pub icon_color: String,
    #[serde(default)]
    pub logo_asset_path: Option<String>,
    pub status: PluginStatus,
    #[serde(default)]
    pub build_directory: Option<String>,
    #[serde(default)]
    pub generation_log_path: Option<String>,
    #[serde(default)]
    pub agent: Option<GenerationAgent>,
    #[serde(default)]
    pub model: Option<AgentModel>,
    #[serde(default = "default_version")]
    pub current_version: i32,
    #[serde(default)]
    pub versions: Vec<PluginVersion>,
}

fn default_version() -> i32 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PluginVersion {
    pub id: String,
    pub plugin_id: String,
    pub version_number: i32,
    pub prompt: String,
    pub created_at: String,
    #[serde(default)]
    pub build_directory: Option<String>,
    #[serde(default)]
    pub install_paths: InstallPaths,
    #[serde(default)]
    pub icon_color: String,
    pub is_active: bool,
    #[serde(default)]
    pub agent: Option<GenerationAgent>,
    #[serde(default)]
    pub model: Option<AgentModel>,
    #[serde(default)]
    pub telemetry_id: Option<String>,
}
