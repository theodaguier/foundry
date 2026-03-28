use crate::models::telemetry::GenerationTelemetry;
use crate::services::telemetry_service;
use tauri::command;

#[command]
pub async fn load_telemetry(id: String) -> Result<Option<GenerationTelemetry>, String> {
    telemetry_service::load(id).map_err(|e| e.to_string())
}

#[command]
pub async fn load_all_telemetry() -> Result<Vec<GenerationTelemetry>, String> {
    telemetry_service::load_all().map_err(|e| e.to_string())
}

#[command]
pub async fn rate_generation(
    id: String,
    rating: i16,
    state: tauri::State<'_, crate::state::AppState>,
) -> Result<(), String> {
    crate::services::telemetry_service::rate(&id, rating, &state.auth);
    Ok(())
}

#[command]
pub async fn submit_plugin_feedback(
    plugin_id: String,
    speed: u8,
    quality: u8,
    design: u8,
    state: tauri::State<'_, crate::state::AppState>,
) -> Result<(), String> {
    telemetry_service::submit_feedback(&plugin_id, speed, quality, design, &state.auth);
    Ok(())
}
