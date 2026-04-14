use crate::models::plugin::PluginFormat;
use std::path::PathBuf;

pub const DEFAULT_MANAGED_JUCE_VERSION: &str = "8.0.12";

#[cfg(target_os = "macos")]
pub const MANAGED_CODEX_VERSION: &str = "rust-v0.120.0";

#[cfg(target_os = "macos")]
pub const MANAGED_CMAKE_VERSION: &str = "3.31.6";

#[cfg(target_os = "macos")]
pub const MANAGED_NODE_VERSION: &str = "22.14.0";

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct EnvironmentConfig {
    // Install path overrides
    pub au_install_path: Option<String>,
    pub vst3_install_path: Option<String>,
    // Provider path overrides
    pub claude_path_override: Option<String>,
    pub codex_path_override: Option<String>,
    // Build environment (JUCE)
    pub managed_juce_version: Option<String>,
    pub juce_override_path: Option<String>,
    pub last_resolved_juce_path: Option<String>,
    pub last_validation_at: Option<String>,
}

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

#[cfg(target_os = "macos")]
pub fn managed_cmake_root_dir() -> PathBuf {
    application_support_dir().join("CMake")
}

#[cfg(target_os = "macos")]
pub fn managed_cmake_dir() -> PathBuf {
    managed_cmake_root_dir().join(MANAGED_CMAKE_VERSION)
}

#[cfg(target_os = "macos")]
pub fn managed_cmake_binary() -> PathBuf {
    managed_cmake_dir()
        .join(format!("cmake-{}-macos-universal", MANAGED_CMAKE_VERSION))
        .join("CMake.app")
        .join("Contents")
        .join("bin")
        .join("cmake")
}

#[cfg(target_os = "macos")]
pub fn managed_node_root_dir() -> PathBuf {
    application_support_dir().join("Node")
}

#[cfg(target_os = "macos")]
pub fn managed_node_dir() -> PathBuf {
    managed_node_root_dir().join(MANAGED_NODE_VERSION)
}

#[cfg(target_os = "macos")]
pub fn managed_node_binary() -> PathBuf {
    let arch = if std::env::consts::ARCH == "aarch64" {
        "arm64"
    } else {
        "x64"
    };
    managed_node_dir()
        .join(format!("node-v{}-darwin-{}", MANAGED_NODE_VERSION, arch))
        .join("bin")
        .join("node")
}

#[cfg(target_os = "macos")]
pub fn managed_npm_binary() -> PathBuf {
    let arch = if std::env::consts::ARCH == "aarch64" {
        "arm64"
    } else {
        "x64"
    };
    managed_node_dir()
        .join(format!("node-v{}-darwin-{}", MANAGED_NODE_VERSION, arch))
        .join("bin")
        .join("npm")
}

#[cfg(target_os = "macos")]
pub fn managed_codex_root_dir() -> PathBuf {
    application_support_dir().join("Codex")
}

#[cfg(target_os = "macos")]
pub fn managed_codex_dir() -> PathBuf {
    managed_codex_root_dir().join(MANAGED_CODEX_VERSION)
}

#[cfg(target_os = "macos")]
pub fn managed_codex_binary() -> PathBuf {
    // The archive extracts into codex-{arch}-apple-darwin/codex, which is then
    // renamed (not copied) to managed_codex_dir(). So the binary lives directly
    // under the version directory, not in a subdirectory.
    managed_codex_dir().join("codex")
}

/// Read a custom install path override for the given plugin format.
/// Returns `None` if no override is configured.
pub fn install_path_override(format: &PluginFormat) -> Option<PathBuf> {
    let config = load_environment_config().ok()?;

    let path_str = match format {
        PluginFormat::Au => config.au_install_path?,
        PluginFormat::Vst3 => config.vst3_install_path?,
    };

    Some(PathBuf::from(path_str))
}

/// Persist a custom install path override for a plugin format.
pub fn set_install_path_override(format: &PluginFormat, path: &str) -> Result<(), String> {
    let mut config = load_environment_config().unwrap_or_default();

    match format {
        PluginFormat::Au => config.au_install_path = Some(path.to_string()),
        PluginFormat::Vst3 => config.vst3_install_path = Some(path.to_string()),
    }

    save_environment_config(&config)?;

    Ok(())
}

/// Remove a custom install path override, reverting to the platform default.
pub fn clear_install_path_override(format: &PluginFormat) -> Result<(), String> {
    let mut config = load_environment_config().unwrap_or_default();

    match format {
        PluginFormat::Au => config.au_install_path = None,
        PluginFormat::Vst3 => config.vst3_install_path = None,
    }

    save_environment_config(&config)?;

    Ok(())
}

pub fn provider_path_override(command: &str) -> Option<PathBuf> {
    let config = load_environment_config().ok()?;
    let path_str = match command {
        "claude" => config.claude_path_override?,
        "codex" => config.codex_path_override?,
        _ => return None,
    };

    Some(PathBuf::from(path_str))
}

pub fn set_provider_path_override(command: &str, path: &str) -> Result<(), String> {
    let mut config = load_environment_config().unwrap_or_default();

    match command {
        "claude" => config.claude_path_override = Some(path.to_string()),
        "codex" => config.codex_path_override = Some(path.to_string()),
        _ => return Err(format!("Unknown provider command: {}", command)),
    }

    save_environment_config(&config)
}

pub fn clear_provider_path_override(command: &str) -> Result<(), String> {
    let mut config = load_environment_config().unwrap_or_default();

    match command {
        "claude" => config.claude_path_override = None,
        "codex" => config.codex_path_override = None,
        _ => return Err(format!("Unknown provider command: {}", command)),
    }

    save_environment_config(&config)
}

pub fn load_environment_config() -> Result<EnvironmentConfig, String> {
    let config_path = environment_config_path();
    let content = match std::fs::read_to_string(&config_path) {
        Ok(content) => content,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(EnvironmentConfig::default())
        }
        Err(error) => return Err(format!("Failed to read config: {}", error)),
    };

    serde_json::from_str(&content).map_err(|e| format!("Failed to parse config: {}", e))
}

pub fn save_environment_config(config: &EnvironmentConfig) -> Result<(), String> {
    let config_path = environment_config_path();
    let Some(parent) = config_path.parent() else {
        return Err("Failed to resolve config directory.".into());
    };

    std::fs::create_dir_all(parent).map_err(|e| format!("Failed to create config dir: {}", e))?;
    let content = serde_json::to_string_pretty(config)
        .map_err(|e| format!("Failed to serialize config: {}", e))?;
    std::fs::write(&config_path, content).map_err(|e| format!("Failed to write config: {}", e))
}
