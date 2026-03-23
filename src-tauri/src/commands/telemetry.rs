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
