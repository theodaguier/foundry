use std::fs;
use serde::{Deserialize, Serialize};
use crate::models::plugin::Plugin;
use crate::services::foundry_paths;

/// Swift format: `{ "plugins": [...] }`
#[derive(Serialize, Deserialize)]
struct PluginFile {
    plugins: Vec<Plugin>,
}

pub fn load_plugins() -> Result<Vec<Plugin>, Box<dyn std::error::Error>> {
    let path = foundry_paths::plugins_json_path();
    log::info!("Loading plugins from: {}", path.display());
    if !path.exists() {
        log::info!("plugins.json not found");
        return Ok(Vec::new());
    }
    let data = fs::read_to_string(&path)?;
    log::info!("Read {} bytes from plugins.json", data.len());

    // Try Swift format first: { "plugins": [...] }
    match serde_json::from_str::<PluginFile>(&data) {
        Ok(file) => {
            log::info!("Loaded {} plugins (Swift format)", file.plugins.len());
            return Ok(file.plugins);
        }
        Err(e) => {
            log::warn!("Swift format parse failed: {}", e);
        }
    }

    // Fallback: bare array [...]
    match serde_json::from_str::<Vec<Plugin>>(&data) {
        Ok(plugins) => {
            log::info!("Loaded {} plugins (array format)", plugins.len());
            Ok(plugins)
        }
        Err(e) => {
            log::error!("Failed to parse plugins.json: {}", e);
            Err(Box::new(e))
        }
    }
}

pub fn save_plugins(plugins: &[Plugin]) -> Result<(), Box<dyn std::error::Error>> {
    let path = foundry_paths::plugins_json_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    // Write in Swift-compatible format
    let file = PluginFile { plugins: plugins.to_vec() };
    let data = serde_json::to_string_pretty(&file)?;
    fs::write(&path, data)?;
    Ok(())
}
