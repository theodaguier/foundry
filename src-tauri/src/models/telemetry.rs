use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GenerationTelemetry {
    pub id: String,
    pub plugin_id: Option<String>,
    pub version_number: Option<i32>,
    pub generation_type: String, // "generate", "refine"
    pub agent: String,
    pub model: String,
    pub original_prompt: String,
    pub started_at: String,
    pub generation_duration: Option<f64>,
    pub build_duration: Option<f64>,
    pub install_duration: Option<f64>,
    pub total_duration: f64,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub cache_read_tokens: Option<i64>,
    pub estimated_cost: Option<f64>,
    pub build_attempts: i32,
    #[serde(default)]
    pub build_attempt_logs: Vec<BuildAttemptLog>,
    pub outcome: String, // "success", "failed_build", "failed_generation", "cancelled", etc.
    pub failure_stage: Option<String>,
    pub failure_message: Option<String>,
    pub plugin_type: Option<String>,
    pub format: Option<String>,
    pub channel_layout: Option<String>,
    pub os_platform: Option<String>,
    pub os_version: Option<String>,
    pub cpu_architecture: Option<String>,
    pub agent_cli_version: Option<String>,
    pub juce_version: Option<String>,
    pub created_at: String,
    pub user_rating: Option<i16>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BuildAttemptLog {
    pub attempt: i32,
    pub success: bool,
    pub duration: f64,
    pub error_snippet: Option<String>,
}

/// Supabase row — snake_case to match the `generation_telemetry` table columns.
#[derive(Debug, Serialize)]
pub struct TelemetryRow {
    pub id: String,
    pub user_id: String,
    pub plugin_id: Option<String>,
    pub version_number: Option<i32>,
    pub generation_type: String,
    pub agent: String,
    pub model: String,
    pub original_prompt: String,
    pub started_at: String,
    pub generation_duration: Option<f64>,
    pub build_duration: Option<f64>,
    pub install_duration: Option<f64>,
    pub total_duration: f64,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub cache_read_tokens: Option<i64>,
    pub estimated_cost_usd: Option<f64>,
    pub build_attempts: i32,
    pub build_logs: String, // JSON string of build_attempt_logs
    pub outcome: String,
    pub failure_stage: Option<String>,
    pub failure_message: Option<String>,
    pub plugin_type: Option<String>,
    pub format: Option<String>,
    pub channel_layout: Option<String>,
    pub os_platform: Option<String>,
    pub os_version: Option<String>,
    pub cpu_architecture: Option<String>,
    pub agent_cli_version: Option<String>,
    pub juce_version: Option<String>,
    pub user_rating: Option<i16>,
}

impl TelemetryRow {
    pub fn from_telemetry(t: &GenerationTelemetry, user_id: &str) -> Self {
        Self {
            id: t.id.clone(),
            user_id: user_id.to_string(),
            plugin_id: t.plugin_id.clone(),
            version_number: t.version_number,
            generation_type: t.generation_type.clone(),
            agent: t.agent.clone(),
            model: t.model.clone(),
            original_prompt: t.original_prompt.clone(),
            started_at: t.started_at.clone(),
            generation_duration: t.generation_duration.or(Some(0.0)),
            build_duration: t.build_duration.or(Some(0.0)),
            install_duration: t.install_duration.or(Some(0.0)),
            total_duration: t.total_duration,
            input_tokens: t.input_tokens,
            output_tokens: t.output_tokens,
            cache_read_tokens: t.cache_read_tokens,
            estimated_cost_usd: t.estimated_cost,
            build_attempts: t.build_attempts,
            build_logs: serde_json::to_string(&t.build_attempt_logs)
                .unwrap_or_else(|_| "[]".into()),
            outcome: t.outcome.clone(),
            failure_stage: t.failure_stage.clone(),
            failure_message: t.failure_message.clone(),
            plugin_type: t.plugin_type.clone(),
            format: t.format.clone(),
            channel_layout: t.channel_layout.clone(),
            os_platform: t.os_platform.clone(),
            os_version: t.os_version.clone(),
            cpu_architecture: t.cpu_architecture.clone(),
            agent_cli_version: t.agent_cli_version.clone(),
            juce_version: t.juce_version.clone(),
            user_rating: t.user_rating,
        }
    }
}

/// Mutable builder accumulated during the pipeline, then finalized.
pub struct TelemetryBuilder {
    pub id: String,
    pub plugin_id: Option<String>,
    pub version_number: Option<i32>,
    pub generation_type: String,
    pub agent: String,
    pub model: String,
    pub original_prompt: String,
    pub started_at: std::time::Instant,
    pub started_at_iso: String,

    pub generation_start: Option<std::time::Instant>,
    pub generation_duration: Option<f64>,
    pub build_start: Option<std::time::Instant>,
    pub build_duration: Option<f64>,
    pub install_start: Option<std::time::Instant>,
    pub install_duration: Option<f64>,

    pub build_attempt_logs: Vec<BuildAttemptLog>,
    pub current_attempt_start: Option<std::time::Instant>,

    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub cache_read_tokens: Option<i64>,
    pub estimated_cost: Option<f64>,

    pub outcome: String,
    pub failure_stage: Option<String>,
    pub failure_message: Option<String>,

    pub plugin_type: Option<String>,
    pub format: Option<String>,
    pub channel_layout: Option<String>,
    pub juce_version: Option<String>,
}

impl TelemetryBuilder {
    pub fn new(generation_type: &str, prompt: &str, agent: &str, model: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            plugin_id: None,
            version_number: None,
            generation_type: generation_type.to_string(),
            agent: normalize_agent(agent),
            model: model.to_string(),
            original_prompt: prompt.to_string(),
            started_at: std::time::Instant::now(),
            started_at_iso: chrono::Utc::now().to_rfc3339(),
            generation_start: None,
            generation_duration: None,
            build_start: None,
            build_duration: None,
            install_start: None,
            install_duration: None,
            build_attempt_logs: Vec::new(),
            current_attempt_start: None,
            input_tokens: None,
            output_tokens: None,
            cache_read_tokens: None,
            estimated_cost: None,
            outcome: "success".to_string(),
            failure_stage: None,
            failure_message: None,
            plugin_type: None,
            format: None,
            channel_layout: None,
            juce_version: None,
        }
    }

    pub fn start_generation(&mut self) {
        self.generation_start = Some(std::time::Instant::now());
    }

    pub fn end_generation(&mut self) {
        if let Some(start) = self.generation_start {
            self.generation_duration = Some(start.elapsed().as_secs_f64());
        }
    }

    pub fn start_build(&mut self) {
        self.build_start = Some(std::time::Instant::now());
    }

    pub fn end_build(&mut self) {
        if let Some(start) = self.build_start {
            self.build_duration = Some(start.elapsed().as_secs_f64());
        }
    }

    pub fn start_install(&mut self) {
        self.install_start = Some(std::time::Instant::now());
    }

    pub fn end_install(&mut self) {
        if let Some(start) = self.install_start {
            self.install_duration = Some(start.elapsed().as_secs_f64());
        }
    }

    pub fn start_build_attempt(&mut self) {
        self.current_attempt_start = Some(std::time::Instant::now());
    }

    pub fn end_build_attempt(
        &mut self,
        attempt: i32,
        success: bool,
        error_snippet: Option<String>,
    ) {
        let duration = self
            .current_attempt_start
            .map(|s| s.elapsed().as_secs_f64())
            .unwrap_or(0.0);
        self.build_attempt_logs.push(BuildAttemptLog {
            attempt,
            success,
            duration,
            error_snippet,
        });
        self.current_attempt_start = None;
    }

    /// Accumulate token/cost data from a Claude CLI run result.
    pub fn accumulate_run(&mut self, result: &crate::services::claude_code_service::RunResult) {
        if let Some(t) = result.input_tokens {
            *self.input_tokens.get_or_insert(0) += t;
        }
        if let Some(t) = result.output_tokens {
            *self.output_tokens.get_or_insert(0) += t;
        }
        if let Some(t) = result.cache_read_tokens {
            *self.cache_read_tokens.get_or_insert(0) += t;
        }
        if let Some(c) = result.cost_usd {
            *self.estimated_cost.get_or_insert(0.0) += c;
        }
    }

    pub fn fail(&mut self, stage: &str, message: &str) {
        self.outcome = format!("failed_{}", stage);
        self.failure_stage = Some(stage.to_string());
        self.failure_message = Some(message.to_string());
    }

    pub fn cancel(&mut self) {
        self.outcome = "cancelled".to_string();
    }

    pub fn build(self) -> GenerationTelemetry {
        let os_version = detect_os_version();
        let cpu_arch = detect_cpu_architecture();

        GenerationTelemetry {
            id: self.id,
            plugin_id: self.plugin_id,
            version_number: self.version_number,
            generation_type: self.generation_type,
            agent: self.agent,
            model: self.model,
            original_prompt: self.original_prompt,
            started_at: self.started_at_iso,
            generation_duration: self.generation_duration,
            build_duration: self.build_duration,
            install_duration: self.install_duration,
            total_duration: self.started_at.elapsed().as_secs_f64(),
            input_tokens: self.input_tokens,
            output_tokens: self.output_tokens,
            cache_read_tokens: self.cache_read_tokens,
            estimated_cost: self.estimated_cost,
            build_attempts: self.build_attempt_logs.len() as i32,
            build_attempt_logs: self.build_attempt_logs,
            outcome: self.outcome,
            failure_stage: self.failure_stage,
            failure_message: self.failure_message,
            plugin_type: self.plugin_type,
            format: self.format,
            channel_layout: self.channel_layout,
            os_platform: Some(detect_os_platform()),
            os_version: Some(os_version),
            cpu_architecture: Some(cpu_arch),
            agent_cli_version: Some(env!("CARGO_PKG_VERSION").to_string()),
            juce_version: self.juce_version,
            created_at: chrono::Utc::now().to_rfc3339(),
            user_rating: None,
        }
    }
}

fn normalize_agent(agent: &str) -> String {
    if agent.to_ascii_lowercase().contains("codex") {
        "codex".to_string()
    } else {
        "claude-code".to_string()
    }
}

fn detect_os_version() -> String {
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("sw_vers")
            .arg("-productVersion")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "unknown".into())
    }
    #[cfg(target_os = "windows")]
    {
        std::env::var("OS").unwrap_or_else(|_| "Windows".into())
    }
    #[cfg(target_os = "linux")]
    {
        std::fs::read_to_string("/etc/os-release")
            .ok()
            .and_then(|s| {
                s.lines().find(|l| l.starts_with("PRETTY_NAME=")).map(|l| {
                    l.trim_start_matches("PRETTY_NAME=")
                        .trim_matches('"')
                        .to_string()
                })
            })
            .unwrap_or_else(|| "Linux".into())
    }
}

fn detect_os_platform() -> String {
    #[cfg(target_os = "macos")]
    return "macos".to_string();
    #[cfg(target_os = "windows")]
    return "windows".to_string();
    #[cfg(target_os = "linux")]
    return "linux".to_string();
    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    return std::env::consts::OS.to_string();
}

fn detect_cpu_architecture() -> String {
    #[cfg(target_arch = "aarch64")]
    {
        "arm64".to_string()
    }
    #[cfg(target_arch = "x86_64")]
    {
        "x86_64".to_string()
    }
    #[cfg(not(any(target_arch = "aarch64", target_arch = "x86_64")))]
    {
        std::env::consts::ARCH.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_builder() -> TelemetryBuilder {
        TelemetryBuilder::new("generate", "a warm reverb", "claude-code", "sonnet")
    }

    #[test]
    fn telemetry_build_populates_agent_cli_version() {
        let t = make_builder().build();
        assert!(
            t.agent_cli_version.is_some(),
            "agent_cli_version must be populated at build time"
        );
        let v = t.agent_cli_version.unwrap();
        assert!(!v.is_empty(), "agent_cli_version must not be empty");
        // Must look like a semver string
        assert!(v.contains('.'), "agent_cli_version must be a semver string, got: {}", v);
    }

    #[test]
    fn telemetry_build_no_hardcoded_none_fields() {
        let t = make_builder().build();
        assert!(t.os_version.is_some(), "os_version must be detected");
        assert!(t.cpu_architecture.is_some(), "cpu_architecture must be detected");
        // user_rating starts as None — that's correct
        assert!(t.user_rating.is_none(), "user_rating starts as None before user rates");
    }

    #[test]
    fn telemetry_row_user_rating_round_trips() {
        let mut t = make_builder().build();
        t.user_rating = Some(1);
        let row = TelemetryRow::from_telemetry(&t, "user-123");
        assert_eq!(row.user_rating, Some(1));

        let mut t2 = make_builder().build();
        t2.user_rating = Some(-1);
        let row2 = TelemetryRow::from_telemetry(&t2, "user-123");
        assert_eq!(row2.user_rating, Some(-1));
    }

    #[test]
    fn telemetry_row_from_telemetry_preserves_all_fields() {
        let mut b = make_builder();
        b.plugin_id = Some("plugin-abc".to_string());
        b.plugin_type = Some("effect".to_string());
        b.format = Some("AU".to_string());
        b.channel_layout = Some("Stereo".to_string());
        b.fail("build", "CMake error");
        let t = b.build();
        let row = TelemetryRow::from_telemetry(&t, "user-xyz");

        assert_eq!(row.plugin_id, Some("plugin-abc".to_string()));
        assert_eq!(row.plugin_type, Some("effect".to_string()));
        assert_eq!(row.outcome, "failed_build");
        assert_eq!(row.failure_stage, Some("build".to_string()));
        assert_eq!(row.failure_message, Some("CMake error".to_string()));
    }

    #[test]
    fn normalize_agent_handles_variants() {
        assert_eq!(normalize_agent("claude-code"), "claude-code");
        assert_eq!(normalize_agent("Claude Code"), "claude-code");
        assert_eq!(normalize_agent("Codex"), "codex");
        assert_eq!(normalize_agent("codex-cli"), "codex");
        assert_eq!(normalize_agent("unknown"), "claude-code");
    }
}
