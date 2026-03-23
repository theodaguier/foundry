use crate::models::agent::AgentProvider;
use crate::services::model_catalog;
use tauri::command;

#[command]
pub async fn get_model_catalog() -> Result<Vec<AgentProvider>, String> {
    model_catalog::load_catalog().map_err(|e| e.to_string())
}

#[command]
pub async fn refresh_model_catalog() -> Result<Vec<AgentProvider>, String> {
    model_catalog::refresh().await.map_err(|e| e.to_string())
}
