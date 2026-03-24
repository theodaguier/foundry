use tauri::{command, State};

use crate::platform;
use crate::services::onboarding;
use crate::state::AppState;

#[command]
pub async fn get_onboarding_state(
    state: State<'_, AppState>,
) -> Result<onboarding::OnboardingState, String> {
    Ok(onboarding::get_onboarding_state(&state.auth).await)
}

#[command]
pub async fn complete_onboarding(
    state: State<'_, AppState>,
) -> Result<onboarding::OnboardingState, String> {
    onboarding::complete_onboarding(&state.auth).await
}

#[command]
pub async fn install_dependency(
    name: String,
) -> Result<onboarding::DependencyInstallResult, String> {
    let result = tokio::task::spawn_blocking(move || match name.as_str() {
        "xcode_clt" => onboarding::install_xcode_clt(),
        "cmake" => onboarding::install_cmake(),
        "claude_code" => onboarding::install_claude_code(),
        "codex" => onboarding::install_codex(),
        _ => onboarding::DependencyInstallResult {
            success: false,
            message: format!("Unknown dependency: {}", name),
        },
    })
    .await
    .map_err(|e| e.to_string())?;

    // Invalidate cached shell environment so newly installed tools are detected
    platform::invalidate_shell_cache();

    Ok(result)
}
