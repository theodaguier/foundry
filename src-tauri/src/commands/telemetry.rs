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
    app: tauri::AppHandle,
) -> Result<(), String> {
    use crate::services::auth_service::SupabaseAuth;
    use crate::AppState;
    use tauri::Manager;

    let auth = app
        .try_state::<AppState>()
        .map(|s| s.auth.clone())
        .unwrap_or_else(SupabaseAuth::new);

    crate::services::telemetry_service::rate(&id, rating, &auth);
    Ok(())
}
