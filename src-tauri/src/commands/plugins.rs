use tauri::{command, State};
use crate::state::AppState;
use crate::services::plugin_manager;
use crate::models::plugin::Plugin;

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
pub async fn rename_plugin(id: String, new_name: String, state: State<'_, AppState>) -> Result<(), String> {
    let mut plugins = state.plugins.lock().map_err(|e| e.to_string())?;
    if let Some(plugin) = plugins.iter_mut().find(|p| p.id == id) {
        plugin.name = new_name;
    }
    plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;
    Ok(())
}

#[command]
pub async fn install_version(_plugin_id: String, _version_number: i32) -> Result<(), String> {
    Ok(())
}

#[command]
pub async fn clear_build_cache(_plugin_id: String, _version_number: i32) -> Result<(), String> {
    Ok(())
}
