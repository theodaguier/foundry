mod commands;
mod models;
mod platform;
mod services;
mod state;

use state::AppState;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Load .env file (silently ignore if missing)
    let _ = dotenvy::dotenv();
    tauri::Builder::default()
        .plugin(
            tauri_plugin_log::Builder::default()
                .level(log::LevelFilter::Info)
                .build(),
        )
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(AppState::new())
        .invoke_handler(tauri::generate_handler![
            commands::auth::check_session,
            commands::auth::send_otp,
            commands::auth::verify_otp,
            commands::auth::sign_up,
            commands::auth::sign_out,
            commands::auth::get_profile,
            commands::auth::update_card_variant,
            commands::auth::assign_card_variant_batch,
            commands::plugins::load_plugins,
            commands::plugins::delete_plugin,
            commands::plugins::rename_plugin,
            commands::plugins::install_version,
            commands::plugins::clear_build_cache,
            commands::generation::start_generation,
            commands::generation::start_refine,
            commands::generation::cancel_build,
            commands::dependencies::check_dependencies,
            commands::dependencies::get_build_environment,
            commands::dependencies::prepare_build_environment,
            commands::dependencies::set_juce_override_path,
            commands::dependencies::clear_juce_override_path,
            commands::dependencies::install_juce,
            commands::settings::get_model_catalog,
            commands::settings::refresh_model_catalog,
            commands::settings::get_install_paths,
            commands::settings::set_install_path,
            commands::settings::reset_install_path,
            commands::telemetry::load_telemetry,
            commands::telemetry::load_all_telemetry,
            commands::telemetry::rate_generation,
            commands::telemetry::submit_plugin_feedback,
            commands::filesystem::show_in_finder,
            commands::onboarding::get_onboarding_state,
            commands::onboarding::complete_onboarding,
            commands::onboarding::install_dependency,
            commands::onboarding::launch_claude_auth,
        ])
        .setup(|app| {
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                services::build_directory_cleaner::sweep_stale_directories(&handle).await;
            });

            services::telemetry_service::sync_local_backlog(&app.state::<AppState>().auth);

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
