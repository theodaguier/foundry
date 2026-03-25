use crate::models::plugin::{Plugin, PluginFormat};
use crate::platform;
use crate::services::plugin_manager;
use crate::state::AppState;
use std::path::Path;
use tauri::{command, State};

#[command]
pub async fn load_plugins(state: State<'_, AppState>) -> Result<Vec<Plugin>, String> {
    let plugins = plugin_manager::load_plugins().map_err(|e| e.to_string())?;
    let mut locked = state.plugins.lock().map_err(|e| e.to_string())?;
    *locked = plugins.clone();
    Ok(plugins)
}

#[command]
pub async fn delete_plugin(id: String, state: State<'_, AppState>) -> Result<(), String> {
    let mut plugins = state.plugins.lock().map_err(|e| e.to_string())?;
    plugins.retain(|p| p.id != id);
    plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;
    Ok(())
}

#[command]
pub async fn rename_plugin(
    id: String,
    new_name: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let mut plugins = state.plugins.lock().map_err(|e| e.to_string())?;
    if let Some(plugin) = plugins.iter_mut().find(|p| p.id == id) {
        plugin.name = new_name;
    }
    plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;
    Ok(())
}

#[command]
pub async fn install_version(
    plugin_id: String,
    version_number: i32,
    state: State<'_, AppState>,
) -> Result<Plugin, String> {
    let mut plugins = state.plugins.lock().map_err(|e| e.to_string())?;

    let plugin = plugins
        .iter_mut()
        .find(|p| p.id == plugin_id)
        .ok_or_else(|| format!("Plugin not found: {}", plugin_id))?;

    let version = plugin
        .versions
        .iter()
        .find(|v| v.version_number == version_number)
        .ok_or_else(|| format!("Version {} not found", version_number))?;

    let build_dir = version
        .build_directory
        .as_ref()
        .ok_or_else(|| "No build directory for this version".to_string())?;

    let build_path = Path::new(build_dir);
    if !build_path.exists() {
        return Err(format!("Build directory does not exist: {}", build_dir));
    }

    let mut new_install_paths = crate::models::plugin::InstallPaths::default();
    let mut operations = Vec::new();

    for mapping in platform::bundle_mappings() {
        let plugin_format = match mapping.format_label {
            "AU" => PluginFormat::Au,
            "VST3" => PluginFormat::Vst3,
            _ => continue,
        };

        let extension = mapping.extension.trim_start_matches('.');
        if let Ok(entries) = find_bundles(build_path, extension) {
            for bundle_path in entries {
                let bundle_name = bundle_path
                    .file_name()
                    .ok_or_else(|| "Invalid bundle name".to_string())?;
                let install_dir = platform::plugin_install_dir(&plugin_format);
                let dest = install_dir.path.join(bundle_name);

                operations.push(platform::types::InstallOperation {
                    format: plugin_format.clone(),
                    source: bundle_path,
                    destination: dest.clone(),
                });

                let dest_string = dest.to_string_lossy().to_string();
                match plugin_format {
                    PluginFormat::Au => new_install_paths.au = Some(dest_string),
                    PluginFormat::Vst3 => new_install_paths.vst3 = Some(dest_string),
                }
            }
        }
    }

    if new_install_paths.au.is_none() && new_install_paths.vst3.is_none() {
        return Err("No AU or VST3 bundles found in build directory".to_string());
    }

    platform::install_plugin_bundles(&operations)?;
    platform::post_install_refresh()?;

    // Update plugin state
    plugin.current_version = version_number;
    plugin.install_paths = new_install_paths.clone();
    plugin.build_directory = Some(build_dir.clone());

    // Mark all versions inactive, then set the target version active
    for v in plugin.versions.iter_mut() {
        v.is_active = v.version_number == version_number;
        if v.version_number == version_number {
            v.install_paths = new_install_paths.clone();
        }
    }

    let updated_plugin = plugin.clone();

    plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;

    Ok(updated_plugin)
}

#[command]
pub async fn clear_build_cache(
    plugin_id: String,
    version_number: i32,
    state: State<'_, AppState>,
) -> Result<Plugin, String> {
    let mut plugins = state.plugins.lock().map_err(|e| e.to_string())?;

    let plugin = plugins
        .iter_mut()
        .find(|p| p.id == plugin_id)
        .ok_or_else(|| format!("Plugin not found: {}", plugin_id))?;

    let version = plugin
        .versions
        .iter_mut()
        .find(|v| v.version_number == version_number)
        .ok_or_else(|| format!("Version {} not found", version_number))?;

    if let Some(build_dir) = version.build_directory.take() {
        let build_path = Path::new(&build_dir);
        if build_path.exists() {
            std::fs::remove_dir_all(build_path)
                .map_err(|e| format!("Failed to remove build directory: {}", e))?;
            log::info!("Cleared build cache: {}", build_dir);
        }
    }

    // If this version is the current one, also clear plugin-level build_directory
    if plugin.current_version == version_number {
        plugin.build_directory = None;
    }

    let updated_plugin = plugin.clone();

    plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;

    Ok(updated_plugin)
}

/// Recursively find bundles with a given extension in a directory
fn find_bundles(dir: &Path, extension: &str) -> Result<Vec<std::path::PathBuf>, std::io::Error> {
    let mut results = Vec::new();
    find_bundles_recursive(dir, extension, &mut results)?;
    Ok(results)
}

fn find_bundles_recursive(
    dir: &Path,
    extension: &str,
    results: &mut Vec<std::path::PathBuf>,
) -> Result<(), std::io::Error> {
    if !dir.is_dir() {
        return Ok(());
    }
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if let Some(ext) = path.extension() {
            if ext.to_string_lossy().eq_ignore_ascii_case(extension) {
                results.push(path);
                continue; // Don't recurse into bundles
            }
        }
        if path.is_dir() {
            find_bundles_recursive(&path, extension, results)?;
        }
    }
    Ok(())
}
