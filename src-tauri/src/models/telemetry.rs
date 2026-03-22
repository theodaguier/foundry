use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GenerationTelemetry {
    pub id: String,
    pub plugin_id: String,
    pub stage: String,
    pub success: bool,
    pub total_duration: f64,
    pub generation_duration: Option<f64>,
    pub audit_duration: Option<f64>,
    pub build_duration: Option<f64>,
    pub install_duration: Option<f64>,
    pub build_attempts: i32,
    #[serde(default)]
    pub build_attempt_logs: Vec<BuildAttemptLog>,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub cache_read_tokens: Option<i64>,
    pub estimated_cost: Option<f64>,
    pub agent: Option<String>,
    pub model: Option<String>,
    pub prompt: Option<String>,
    pub enhanced_prompt: Option<String>,
    pub error_message: Option<String>,
    pub error_details: Option<String>,
    pub macos_version: Option<String>,
    pub cpu_architecture: Option<String>,
    pub xcode_version: Option<String>,
    pub agent_cli_version: Option<String>,
    pub juce_version: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BuildAttemptLog {
    pub attempt: i32,
    pub success: bool,
    pub duration: f64,
    pub error_snippet: Option<String>,
}
