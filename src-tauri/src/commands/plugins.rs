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

    // Resolve install directories (respects user overrides)
    let au_dir = platform::plugin_install_dir(&PluginFormat::Au);
    let vst3_dir = platform::plugin_install_dir(&PluginFormat::Vst3);
    let au_dest = &au_dir.path;
    let vst3_dest = &vst3_dir.path;

    let mut new_install_paths = crate::models::plugin::InstallPaths::default();

    // Search for .component bundles in build directory
    if let Ok(entries) = find_bundles(build_path, "component") {
        for bundle_path in entries {
            let bundle_name = bundle_path
                .file_name()
                .ok_or_else(|| "Invalid bundle name".to_string())?;
            let dest = au_dest.join(bundle_name);

            // Remove existing bundle if present
            if dest.exists() {
                std::fs::remove_dir_all(&dest)
                    .map_err(|e| format!("Failed to remove existing AU: {}", e))?;
            }

            copy_dir_recursive(&bundle_path, &dest)
                .map_err(|e| format!("Failed to copy AU bundle: {}", e))?;

            new_install_paths.au = Some(dest.to_string_lossy().to_string());
            log::info!("Installed AU bundle to: {}", dest.display());
        }
    }

    // Search for .vst3 bundles in build directory
    if let Ok(entries) = find_bundles(build_path, "vst3") {
        for bundle_path in entries {
            let bundle_name = bundle_path
                .file_name()
                .ok_or_else(|| "Invalid bundle name".to_string())?;
            let dest = vst3_dest.join(bundle_name);

            // Remove existing bundle if present
            if dest.exists() {
                std::fs::remove_dir_all(&dest)
                    .map_err(|e| format!("Failed to remove existing VST3: {}", e))?;
            }

            copy_dir_recursive(&bundle_path, &dest)
                .map_err(|e| format!("Failed to copy VST3 bundle: {}", e))?;

            new_install_paths.vst3 = Some(dest.to_string_lossy().to_string());
            log::info!("Installed VST3 bundle to: {}", dest.display());
        }
    }

    if new_install_paths.au.is_none() && new_install_paths.vst3.is_none() {
        return Err("No AU or VST3 bundles found in build directory".to_string());
    }

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

/// Recursively copy a directory
fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<(), std::io::Error> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path)?;
        } else {
            std::fs::copy(&src_path, &dst_path)?;
        }
    }
    Ok(())
}
