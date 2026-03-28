use crate::models::plugin::{Plugin, PluginFormat, PluginType};
use crate::models::telemetry::{GenerationTelemetry, TelemetryRow};
use crate::services::auth_service::{SupabaseAuth, SUPABASE_ANON_KEY, SUPABASE_URL};
use crate::services::{foundry_paths, plugin_manager, project_assembler};
use std::fs;

/// Save telemetry locally + sync to Supabase (fire-and-forget).
pub fn save(telemetry: &GenerationTelemetry, auth: &SupabaseAuth) {
    let telemetry = normalize_telemetry(telemetry.clone(), &[]);

    // 1. Save locally
    save_local(&telemetry);

    // 2. Sync to Supabase in background
    let session = auth.get_session();
    tokio::spawn(async move {
        if let Some(session) = session {
            sync_to_supabase(&telemetry, &session.user_id, &session.access_token).await;
        } else {
            log::info!("[Telemetry] Not authenticated — skipping Supabase sync");
        }
    });
}

fn save_local(telemetry: &GenerationTelemetry) {
    let dir = foundry_paths::telemetry_dir();
    if fs::create_dir_all(&dir).is_err() {
        log::error!("[Telemetry] Failed to create telemetry dir");
        return;
    }
    let path = dir.join(format!("{}.json", telemetry.id));
    match serde_json::to_string_pretty(telemetry) {
        Ok(json) => {
            if let Err(e) = fs::write(&path, json) {
                log::error!("[Telemetry] Failed to write {}: {}", path.display(), e);
            }
        }
        Err(e) => log::error!("[Telemetry] Failed to serialize: {}", e),
    }
}

pub fn sync_local_backlog(auth: &SupabaseAuth) {
    let session = match auth.get_session() {
        Some(session) => session,
        None => {
            log::info!("[Telemetry] Backlog sync skipped: not authenticated");
            return;
        }
    };

    tokio::spawn(async move {
        let telemetries = match load_all() {
            Ok(rows) => rows,
            Err(e) => {
                log::error!("[Telemetry] Failed to load backlog: {}", e);
                return;
            }
        };
        if telemetries.is_empty() {
            return;
        }

        let plugins = plugin_manager::load_plugins().unwrap_or_default();
        let mut synced = 0usize;
        let mut failed = 0usize;

        for telemetry in telemetries {
            let telemetry = normalize_telemetry(telemetry, &plugins);
            save_local(&telemetry);
            if sync_to_supabase(&telemetry, &session.user_id, &session.access_token).await {
                synced += 1;
            } else {
                failed += 1;
            }
        }

        log::info!(
            "[Telemetry] Backlog sync finished: {} synced, {} failed",
            synced,
            failed
        );
    });
}

fn normalize_telemetry(mut telemetry: GenerationTelemetry, plugins: &[Plugin]) -> GenerationTelemetry {
    if missing_string(telemetry.plugin_type.as_deref()) {
        telemetry.plugin_type = infer_plugin_type(&telemetry, plugins);
    }

    if missing_string(telemetry.format.as_deref()) {
        telemetry.format = plugin_format_from_plugins(&telemetry, plugins);
    }

    if missing_string(telemetry.channel_layout.as_deref()) {
        telemetry.channel_layout = plugin_channel_layout_from_plugins(&telemetry, plugins);
    }

    if missing_string(telemetry.os_platform.as_deref()) {
        telemetry.os_platform = Some(detect_os_platform());
    }

    if missing_string(telemetry.os_version.as_deref()) {
        telemetry.os_version = Some(detect_os_version());
    }

    if missing_string(telemetry.cpu_architecture.as_deref()) {
        telemetry.cpu_architecture = Some(detect_cpu_architecture());
    }

    if missing_string(telemetry.agent_cli_version.as_deref()) {
        telemetry.agent_cli_version = Some(env!("CARGO_PKG_VERSION").to_string());
    }

    if telemetry.estimated_cost.is_none() {
        telemetry.estimated_cost = estimate_codex_cost_usd(
            &telemetry.agent,
            &telemetry.model,
            telemetry.input_tokens,
            telemetry.output_tokens,
            telemetry.cache_read_tokens,
        );
    }

    telemetry
}

fn missing_string(value: Option<&str>) -> bool {
    value.map(str::trim).map(str::is_empty).unwrap_or(true)
}

fn infer_plugin_type(telemetry: &GenerationTelemetry, plugins: &[Plugin]) -> Option<String> {
    plugin_from_telemetry(telemetry, plugins)
        .map(|plugin| plugin_type_label(&plugin.plugin_type).to_string())
        .or_else(|| Some(project_assembler::infer_plugin_type(&telemetry.original_prompt)))
}

fn plugin_format_from_plugins(telemetry: &GenerationTelemetry, plugins: &[Plugin]) -> Option<String> {
    let plugin = plugin_from_telemetry(telemetry, plugins)?;
    let has_au = plugin.formats.iter().any(|format| matches!(format, PluginFormat::Au));
    let has_vst3 = plugin
        .formats
        .iter()
        .any(|format| matches!(format, PluginFormat::Vst3));

    match (has_au, has_vst3) {
        (true, true) => Some("both".to_string()),
        (true, false) => Some("au".to_string()),
        (false, true) => Some("vst3".to_string()),
        (false, false) => None,
    }
}

fn plugin_channel_layout_from_plugins(
    telemetry: &GenerationTelemetry,
    plugins: &[Plugin],
) -> Option<String> {
    plugin_from_telemetry(telemetry, plugins)
        .and_then(|plugin| plugin.generation_config.as_ref())
        .map(|config| config.channel_layout.clone())
}

fn plugin_from_telemetry<'a>(
    telemetry: &GenerationTelemetry,
    plugins: &'a [Plugin],
) -> Option<&'a Plugin> {
    let plugin_id = telemetry.plugin_id.as_deref()?;
    plugins.iter().find(|plugin| plugin.id == plugin_id)
}

fn plugin_type_label(plugin_type: &PluginType) -> &'static str {
    match plugin_type {
        PluginType::Instrument => "instrument",
        PluginType::Utility => "utility",
        PluginType::Effect => "effect",
    }
}

fn estimate_codex_cost_usd(
    agent: &str,
    model: &str,
    input_tokens: Option<i64>,
    output_tokens: Option<i64>,
    cache_read_tokens: Option<i64>,
) -> Option<f64> {
    if !agent.eq_ignore_ascii_case("codex") && !model.starts_with("gpt-5.") {
        return None;
    }

    struct Pricing {
        input_per_million: f64,
        cached_input_per_million: f64,
        output_per_million: f64,
    }

    let pricing = match model.trim().to_ascii_lowercase().as_str() {
        "gpt-5.4" => Pricing {
            input_per_million: 2.50,
            cached_input_per_million: 0.25,
            output_per_million: 15.00,
        },
        "gpt-5.4-mini" => Pricing {
            input_per_million: 0.75,
            cached_input_per_million: 0.075,
            output_per_million: 4.50,
        },
        "gpt-5.2-codex" => Pricing {
            input_per_million: 1.75,
            cached_input_per_million: 0.175,
            output_per_million: 14.00,
        },
        _ => return None,
    };

    let has_usage = input_tokens.is_some() || output_tokens.is_some() || cache_read_tokens.is_some();
    if !has_usage {
        return None;
    }

    let input_tokens = input_tokens.unwrap_or(0).max(0) as f64;
    let output_tokens = output_tokens.unwrap_or(0).max(0) as f64;
    let cached_tokens = cache_read_tokens.unwrap_or(0).max(0) as f64;
    let uncached_input_tokens = (input_tokens - cached_tokens).max(0.0);

    Some(
        (uncached_input_tokens * pricing.input_per_million
            + cached_tokens * pricing.cached_input_per_million
            + output_tokens * pricing.output_per_million)
            / 1_000_000.0,
    )
}

fn detect_os_version() -> String {
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("sw_vers")
            .arg("-productVersion")
            .output()
            .ok()
            .and_then(|output| String::from_utf8(output.stdout).ok())
            .map(|output| output.trim().to_string())
            .unwrap_or_else(|| "unknown".to_string())
    }
    #[cfg(target_os = "windows")]
    {
        std::env::var("OS").unwrap_or_else(|_| "Windows".to_string())
    }
    #[cfg(target_os = "linux")]
    {
        std::fs::read_to_string("/etc/os-release")
            .ok()
            .and_then(|content| {
                content
                    .lines()
                    .find(|line| line.starts_with("PRETTY_NAME="))
                    .map(|line| line.trim_start_matches("PRETTY_NAME=").trim_matches('"').to_string())
            })
            .unwrap_or_else(|| "Linux".to_string())
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
    std::env::consts::ARCH.to_string()
}

async fn sync_to_supabase(
    telemetry: &GenerationTelemetry,
    user_id: &str,
    access_token: &str,
) -> bool {
    let row = TelemetryRow::from_telemetry(telemetry, user_id);
    let url = format!(
        "{}/rest/v1/generation_telemetry?on_conflict=id",
        *SUPABASE_URL
    );

    let client = reqwest::Client::new();
    let result = client
        .post(&url)
        .header("apikey", SUPABASE_ANON_KEY.as_str())
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .header("Prefer", "resolution=merge-duplicates,return=minimal")
        .json(&row)
        .send()
        .await;

    match result {
        Ok(resp) => {
            if resp.status().is_success() {
                log::info!("[Telemetry] Synced to Supabase: {}", telemetry.id);
                true
            } else {
                let status = resp.status();
                let body = resp.text().await.unwrap_or_default();
                log::error!("[Telemetry] Supabase sync failed ({}): {}", status, body);
                false
            }
        }
        Err(e) => {
            log::error!("[Telemetry] Supabase sync request failed: {}", e);
            false
        }
    }
}

pub fn load(id: String) -> Result<Option<GenerationTelemetry>, Box<dyn std::error::Error>> {
    let path = foundry_paths::telemetry_dir().join(format!("{}.json", id));
    if !path.exists() {
        return Ok(None);
    }
    let data = fs::read_to_string(&path)?;
    Ok(Some(serde_json::from_str(&data)?))
}

pub fn load_all() -> Result<Vec<GenerationTelemetry>, Box<dyn std::error::Error>> {
    let dir = foundry_paths::telemetry_dir();
    if !dir.exists() {
        return Ok(Vec::new());
    }
    let mut results = Vec::new();
    for entry in fs::read_dir(&dir)? {
        let entry = entry?;
        if entry.path().extension().map_or(false, |ext| ext == "json") {
            if let Ok(data) = fs::read_to_string(entry.path()) {
                if let Ok(t) = serde_json::from_str::<GenerationTelemetry>(&data) {
                    results.push(t);
                }
            }
        }
    }
    Ok(results)
}

/// Save a user rating (1 = good, -1 = bad) for a generation.
/// Updates local JSON file and syncs to Supabase.
pub fn rate(id: &str, rating: i16, auth: &SupabaseAuth) {
    // Update local file
    let dir = foundry_paths::telemetry_dir();
    let path = dir.join(format!("{}.json", id));
    if let Ok(data) = fs::read_to_string(&path) {
        if let Ok(mut telemetry) = serde_json::from_str::<GenerationTelemetry>(&data) {
            telemetry.user_rating = Some(rating);
            if let Ok(json) = serde_json::to_string_pretty(&telemetry) {
                let _ = fs::write(&path, json);
            }
        }
    }

    // Sync to Supabase
    let id = id.to_string();
    let session = auth.get_session();
    tokio::spawn(async move {
        if let Some(session) = session {
            sync_rating_to_supabase(&id, rating, &session.access_token).await;
        }
    });
}

/// Submit plugin feedback (speed, quality, design ratings 1–5) to Supabase.
pub fn submit_feedback(plugin_id: &str, speed: u8, quality: u8, design: u8, auth: &SupabaseAuth) {
    let plugin_id = plugin_id.to_string();
    let session = auth.get_session();
    tokio::spawn(async move {
        if let Some(session) = session {
            sync_feedback_to_supabase(
                &plugin_id,
                speed,
                quality,
                design,
                &session.user_id,
                &session.access_token,
            )
            .await;
        } else {
            log::info!("[Feedback] Not authenticated — skipping Supabase sync");
        }
    });
}

async fn sync_feedback_to_supabase(
    plugin_id: &str,
    speed: u8,
    quality: u8,
    design: u8,
    user_id: &str,
    access_token: &str,
) {
    let url = format!("{}/rest/v1/plugin_feedback", *SUPABASE_URL);
    let body = serde_json::json!({
        "plugin_id": plugin_id,
        "user_id": user_id,
        "speed": speed,
        "quality": quality,
        "design": design,
    });
    let client = reqwest::Client::new();
    let result = client
        .post(&url)
        .header("apikey", SUPABASE_ANON_KEY.as_str())
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .header("Prefer", "resolution=merge-duplicates,return=minimal")
        .json(&body)
        .send()
        .await;
    match result {
        Ok(resp) if resp.status().is_success() => {
            log::info!("[Feedback] Synced for plugin {}", plugin_id);
        }
        Ok(resp) => {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            log::error!("[Feedback] Sync failed ({}): {}", status, body);
        }
        Err(e) => log::error!("[Feedback] Sync request failed: {}", e),
    }
}

async fn sync_rating_to_supabase(id: &str, rating: i16, access_token: &str) {
    let url = format!(
        "{}/rest/v1/generation_telemetry?id=eq.{}",
        *SUPABASE_URL, id
    );
    let body = serde_json::json!({ "user_rating": rating });
    let client = reqwest::Client::new();
    let result = client
        .patch(&url)
        .header("apikey", SUPABASE_ANON_KEY.as_str())
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .header("Prefer", "return=minimal")
        .json(&body)
        .send()
        .await;
    match result {
        Ok(resp) if resp.status().is_success() => {
            log::info!("[Telemetry] Rating synced: {} = {}", id, rating);
        }
        Ok(resp) => {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            log::error!("[Telemetry] Rating sync failed ({}): {}", status, body);
        }
        Err(e) => log::error!("[Telemetry] Rating sync request failed: {}", e),
    }
}
