use crate::models::telemetry::{GenerationTelemetry, TelemetryRow};
use crate::services::auth_service::{SupabaseAuth, SUPABASE_ANON_KEY, SUPABASE_URL};
use crate::services::foundry_paths;
use std::fs;

/// Save telemetry locally + sync to Supabase (fire-and-forget).
pub fn save(telemetry: &GenerationTelemetry, auth: &SupabaseAuth) {
    // 1. Save locally
    save_local(telemetry);

    // 2. Sync to Supabase in background
    let telemetry = telemetry.clone();
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

async fn sync_to_supabase(telemetry: &GenerationTelemetry, user_id: &str, access_token: &str) {
    let row = TelemetryRow::from_telemetry(telemetry, user_id);
    let url = format!("{}/rest/v1/generation_telemetry", *SUPABASE_URL);

    let client = reqwest::Client::new();
    let result = client
        .post(&url)
        .header("apikey", SUPABASE_ANON_KEY.as_str())
        .header("Authorization", format!("Bearer {}", access_token))
        .header("Content-Type", "application/json")
        .header("Prefer", "return=minimal")
        .json(&row)
        .send()
        .await;

    match result {
        Ok(resp) => {
            if resp.status().is_success() {
                log::info!("[Telemetry] Synced to Supabase: {}", telemetry.id);
            } else {
                let status = resp.status();
                let body = resp.text().await.unwrap_or_default();
                log::error!("[Telemetry] Supabase sync failed ({}): {}", status, body);
            }
        }
        Err(e) => {
            log::error!("[Telemetry] Supabase sync request failed: {}", e);
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
