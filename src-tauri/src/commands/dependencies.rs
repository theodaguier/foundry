use tauri::command;
use crate::services::dependency_checker;

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DependencyStatus {
    pub name: String,
    pub installed: bool,
    pub detail: Option<String>,
    pub version: Option<String>,
}

#[command]
pub async fn check_dependencies() -> Result<Vec<DependencyStatus>, String> {
    dependency_checker::check_all().await.map_err(|e| e.to_string())
}

#[command]
pub async fn install_juce() -> Result<(), String> {
    dependency_checker::install_juce().await.map_err(|e| e.to_string())
}
