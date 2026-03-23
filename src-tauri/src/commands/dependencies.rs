use crate::services::build_environment;
use crate::services::dependency_checker;
use tauri::{command, Emitter};

#[derive(Clone, serde::Serialize)]
struct ErrorEvent {
    message: String,
}

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
    dependency_checker::check_all()
        .await
        .map_err(|e| e.to_string())
}

#[command]
pub async fn install_juce() -> Result<build_environment::BuildEnvironmentStatus, String> {
    dependency_checker::install_juce()
        .await
        .map_err(|e| e.to_string())
}

#[command]
pub async fn get_build_environment() -> Result<build_environment::BuildEnvironmentStatus, String> {
    build_environment::get_build_environment().await
}

#[command]
pub async fn prepare_build_environment(
    auto_repair: bool,
    app: tauri::AppHandle,
) -> Result<build_environment::BuildEnvironmentStatus, String> {
    let status = build_environment::prepare_build_environment(auto_repair, Some(&app)).await?;
    if status.state != "ready" {
        let _ = app.emit(
            "pipeline:error",
            ErrorEvent {
                message: build_environment::format_blocked_message(&status),
            },
        );
    }
    Ok(status)
}

#[command]
pub async fn set_juce_override_path(
    path: String,
) -> Result<build_environment::BuildEnvironmentStatus, String> {
    build_environment::set_juce_override_path(path).await
}

#[command]
pub async fn clear_juce_override_path() -> Result<build_environment::BuildEnvironmentStatus, String>
{
    build_environment::clear_juce_override_path().await
}
