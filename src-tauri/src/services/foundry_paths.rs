use crate::models::plugin::PluginFormat;
use std::path::PathBuf;

pub const DEFAULT_MANAGED_JUCE_VERSION: &str = "8.0.12";

pub fn application_support_dir() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("Foundry")
}

pub fn plugins_json_path() -> PathBuf {
    application_support_dir().join("plugins.json")
}

pub fn telemetry_dir() -> PathBuf {
    application_support_dir().join("Telemetry")
}

pub fn models_user_override_path() -> PathBuf {
    application_support_dir().join("models.json")
}

pub fn environment_config_path() -> PathBuf {
    application_support_dir().join("environment.json")
}

pub fn managed_juce_root_dir() -> PathBuf {
    application_support_dir().join("JUCE")
}

pub fn managed_juce_dir(version: &str) -> PathBuf {
    managed_juce_root_dir().join(version)
}

/// Read a custom install path override for the given plugin format.
/// Returns `None` if no override is configured.
pub fn install_path_override(format: &PluginFormat) -> Option<PathBuf> {
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct EnvConfig {
        au_install_path: Option<String>,
        vst3_install_path: Option<String>,
    }

    let content = std::fs::read_to_string(environment_config_path()).ok()?;
    let config: EnvConfig = serde_json::from_str(&content).ok()?;

    let path_str = match format {
        PluginFormat::Au => config.au_install_path?,
        PluginFormat::Vst3 => config.vst3_install_path?,
    };

    Some(PathBuf::from(path_str))
}

/// Persist a custom install path override for a plugin format.
pub fn set_install_path_override(format: &PluginFormat, path: &str) -> Result<(), String> {
    let config_path = environment_config_path();
    let mut config: serde_json::Value = std::fs::read_to_string(&config_path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_else(|| serde_json::json!({}));

    let key = match format {
        PluginFormat::Au => "auInstallPath",
        PluginFormat::Vst3 => "vst3InstallPath",
    };

    config[key] = serde_json::Value::String(path.to_string());

    std::fs::create_dir_all(config_path.parent().unwrap())
        .map_err(|e| format!("Failed to create config dir: {}", e))?;
    std::fs::write(&config_path, serde_json::to_string_pretty(&config).unwrap())
        .map_err(|e| format!("Failed to write config: {}", e))?;

    Ok(())
}

/// Remove a custom install path override, reverting to the platform default.
pub fn clear_install_path_override(format: &PluginFormat) -> Result<(), String> {
    let config_path = environment_config_path();
    let mut config: serde_json::Value = std::fs::read_to_string(&config_path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_else(|| serde_json::json!({}));

    let key = match format {
        PluginFormat::Au => "auInstallPath",
        PluginFormat::Vst3 => "vst3InstallPath",
    };

    if let Some(obj) = config.as_object_mut() {
        obj.remove(key);
    }

    std::fs::write(&config_path, serde_json::to_string_pretty(&config).unwrap())
        .map_err(|e| format!("Failed to write config: {}", e))?;

    Ok(())
}
