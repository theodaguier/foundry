use crate::models::agent::AgentProvider;
use crate::models::plugin::PluginFormat;
use crate::platform;
use crate::services::{foundry_paths, model_catalog};
use serde::Serialize;
use tauri::command;

#[command]
pub async fn get_model_catalog() -> Result<Vec<AgentProvider>, String> {
    model_catalog::load_catalog().map_err(|e| e.to_string())
}

#[command]
pub async fn refresh_model_catalog() -> Result<Vec<AgentProvider>, String> {
    model_catalog::refresh().await.map_err(|e| e.to_string())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallPathsConfig {
    pub au_path: String,
    pub vst3_path: String,
    pub au_is_default: bool,
    pub vst3_is_default: bool,
}

#[command]
pub async fn get_install_paths() -> Result<InstallPathsConfig, String> {
    let au_default = platform::default_plugin_install_dir(&PluginFormat::Au);
    let vst3_default = platform::default_plugin_install_dir(&PluginFormat::Vst3);

    let au_override = foundry_paths::install_path_override(&PluginFormat::Au);
    let vst3_override = foundry_paths::install_path_override(&PluginFormat::Vst3);

    Ok(InstallPathsConfig {
        au_path: au_override
            .as_ref()
            .unwrap_or(&au_default.path)
            .to_string_lossy()
            .to_string(),
        vst3_path: vst3_override
            .as_ref()
            .unwrap_or(&vst3_default.path)
            .to_string_lossy()
            .to_string(),
        au_is_default: au_override.is_none(),
        vst3_is_default: vst3_override.is_none(),
    })
}

#[command]
pub async fn set_install_path(format: String, path: String) -> Result<InstallPathsConfig, String> {
    let plugin_format = match format.to_uppercase().as_str() {
        "AU" => PluginFormat::Au,
        "VST3" => PluginFormat::Vst3,
        _ => return Err(format!("Unknown format: {}", format)),
    };

    foundry_paths::set_install_path_override(&plugin_format, &path)?;
    get_install_paths().await
}

#[command]
pub async fn reset_install_path(format: String) -> Result<InstallPathsConfig, String> {
    let plugin_format = match format.to_uppercase().as_str() {
        "AU" => PluginFormat::Au,
        "VST3" => PluginFormat::Vst3,
        _ => return Err(format!("Unknown format: {}", format)),
    };

    foundry_paths::clear_install_path_override(&plugin_format)?;
    get_install_paths().await
}
