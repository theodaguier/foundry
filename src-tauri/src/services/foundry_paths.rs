use std::path::PathBuf;

pub fn application_support_dir() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("Foundry")
}

pub fn plugins_json_path() -> PathBuf {
    application_support_dir().join("plugins.json")
}

pub fn juce_dir() -> PathBuf {
    application_support_dir().join("JUCE")
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
