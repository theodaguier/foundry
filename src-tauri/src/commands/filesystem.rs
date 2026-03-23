use tauri::command;

#[command]
pub async fn show_in_finder(path: String) -> Result<(), String> {
    crate::platform::show_in_file_manager(&path)
}
