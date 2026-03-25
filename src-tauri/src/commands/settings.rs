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
    pub platform: String,
    pub supported_formats: Vec<String>,
    pub au_path: Option<String>,
    pub vst3_path: Option<String>,
    pub au_is_default: bool,
    pub vst3_is_default: bool,
}

#[command]
pub async fn get_install_paths() -> Result<InstallPathsConfig, String> {
    let supported_formats = platform::available_plugin_formats();
    let supports_au = supported_formats.contains(&PluginFormat::Au);
    let supports_vst3 = supported_formats.contains(&PluginFormat::Vst3);

    let au_default = supports_au.then(|| platform::default_plugin_install_dir(&PluginFormat::Au));
    let vst3_default =
        supports_vst3.then(|| platform::default_plugin_install_dir(&PluginFormat::Vst3));

    let au_override = supports_au
        .then(|| foundry_paths::install_path_override(&PluginFormat::Au))
        .flatten();
    let vst3_override = supports_vst3
        .then(|| foundry_paths::install_path_override(&PluginFormat::Vst3))
        .flatten();

    Ok(InstallPathsConfig {
        platform: current_platform().into(),
        supported_formats: supported_formats
            .iter()
            .map(|format| match format {
                PluginFormat::Au => "AU".to_string(),
                PluginFormat::Vst3 => "VST3".to_string(),
            })
            .collect(),
        au_path: au_override
            .as_ref()
            .or(au_default.as_ref().map(|dir| &dir.path))
            .map(|path| path.to_string_lossy().to_string()),
        vst3_path: vst3_override
            .as_ref()
            .or(vst3_default.as_ref().map(|dir| &dir.path))
            .map(|path| path.to_string_lossy().to_string()),
        au_is_default: au_override.is_none(),
        vst3_is_default: vst3_override.is_none(),
    })
}

#[command]
pub async fn set_install_path(format: String, path: String) -> Result<InstallPathsConfig, String> {
    let plugin_format = parse_supported_format(&format)?;

    foundry_paths::set_install_path_override(&plugin_format, &path)?;
    get_install_paths().await
}

#[command]
pub async fn reset_install_path(format: String) -> Result<InstallPathsConfig, String> {
    let plugin_format = parse_supported_format(&format)?;

    foundry_paths::clear_install_path_override(&plugin_format)?;
    get_install_paths().await
}

fn parse_supported_format(format: &str) -> Result<PluginFormat, String> {
    let plugin_format = match format.to_uppercase().as_str() {
        "AU" => PluginFormat::Au,
        "VST3" => PluginFormat::Vst3,
        _ => return Err(format!("Unknown format: {}", format)),
    };

    if !platform::available_plugin_formats().contains(&plugin_format) {
        return Err(format!(
            "{} is not supported on {}",
            format.to_uppercase(),
            current_platform()
        ));
    }

    Ok(plugin_format)
}

fn current_platform() -> &'static str {
    #[cfg(target_os = "macos")]
    {
        "macos"
    }
    #[cfg(target_os = "windows")]
    {
        "windows"
    }
    #[cfg(target_os = "linux")]
    {
        "linux"
    }
}
