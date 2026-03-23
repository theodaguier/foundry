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

pub fn juce_dir() -> PathBuf {
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct EnvironmentConfig {
        juce_override_path: Option<String>,
        last_resolved_juce_path: Option<String>,
    }

    let config_path = environment_config_path();
    if let Ok(content) = std::fs::read_to_string(config_path) {
        if let Ok(config) = serde_json::from_str::<EnvironmentConfig>(&content) {
            if let Some(path) = config.last_resolved_juce_path {
                return PathBuf::from(path);
            }
            if let Some(path) = config.juce_override_path {
                return PathBuf::from(path);
            }
        }
    }

    managed_juce_dir(DEFAULT_MANAGED_JUCE_VERSION)
}

pub fn telemetry_dir() -> PathBuf {
    application_support_dir().join("Telemetry")
}

pub fn models_cache_path() -> PathBuf {
    application_support_dir().join("models-cache.json")
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
