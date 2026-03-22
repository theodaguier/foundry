use std::fs;
use std::path::Path;

pub async fn sweep_stale_directories(_app: &tauri::AppHandle) {
    let tmp_dir = Path::new("/tmp");
    if let Ok(entries) = fs::read_dir(tmp_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str.starts_with("foundry-build-") {
                if let Ok(metadata) = entry.metadata() {
                    if let Ok(modified) = metadata.modified() {
                        let age = std::time::SystemTime::now().duration_since(modified).unwrap_or_default();
                        if age.as_secs() > 86400 {
                            let _ = fs::remove_dir_all(entry.path());
                            log::info!("Cleaned stale build directory: {}", name_str);
                        }
                    }
                }
            }
        }
    }
}
