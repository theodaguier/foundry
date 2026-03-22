mod commands;
mod models;
mod services;
mod state;

use state::AppState;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::default().level(log::LevelFilter::Info).build())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(AppState::new())
        .invoke_handler(tauri::generate_handler![
            commands::auth::check_session,
            commands::auth::send_otp,
            commands::auth::verify_otp,
            commands::auth::sign_up,
            commands::auth::sign_out,
            commands::auth::get_profile,
            commands::plugins::load_plugins,
            commands::plugins::delete_plugin,
            commands::plugins::rename_plugin,
            commands::plugins::install_version,
            commands::plugins::clear_build_cache,
            commands::generation::start_generation,
            commands::generation::start_refine,
            commands::generation::cancel_build,
            commands::dependencies::check_dependencies,
            commands::dependencies::install_juce,
            commands::settings::get_model_catalog,
            commands::settings::refresh_model_catalog,
            commands::telemetry::load_telemetry,
            commands::telemetry::load_all_telemetry,
            commands::filesystem::show_in_finder,
        ])
        .setup(|app| {
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                services::build_directory_cleaner::sweep_stale_directories(&handle).await;
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
