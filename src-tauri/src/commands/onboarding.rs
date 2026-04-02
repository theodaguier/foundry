use std::process::Command;
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
    // Enforce one install at a time
    if !onboarding::try_acquire_install_lock() {
        return Ok(onboarding::DependencyInstallResult::failed(
            "Another install is already in progress. Please wait.",
        ));
    }

    let outcome = tokio::task::spawn_blocking(move || match name.as_str() {
        "xcode_clt" => onboarding::DependencyInstallDispatchResult::Final(onboarding::install_xcode_clt()),
        "cpp_build_tools" => {
            onboarding::DependencyInstallDispatchResult::Final(onboarding::install_cpp_build_tools())
        }
        "cmake" => onboarding::DependencyInstallDispatchResult::Final(onboarding::install_cmake()),
        "git" => onboarding::DependencyInstallDispatchResult::Final(onboarding::install_git()),
        "claude_code" => onboarding::install_claude_code(),
        "codex" => onboarding::install_codex(),
        _ => onboarding::DependencyInstallDispatchResult::Final(onboarding::DependencyInstallResult::failed(
            format!("Unknown dependency: {}", name),
        )),
    })
    .await
    .map_err(|e| {
        onboarding::release_install_lock();
        e.to_string()
    })?;

    // Invalidate cached shell environment so newly installed tools are detected
    platform::invalidate_shell_cache();

    let result = match outcome {
        onboarding::DependencyInstallDispatchResult::Final(result) => result,
        onboarding::DependencyInstallDispatchResult::Provider(preparation) => {
            onboarding::verify_provider_install(preparation).await?
        }
    };

    onboarding::release_install_lock();

    Ok(result)
}

/// Launch `claude auth login` directly — opens the browser for OAuth.
/// No terminal window needed.
#[command]
pub async fn launch_claude_auth() -> Result<bool, String> {
    let claude_path = platform::resolve_claude_path()
        .unwrap_or_else(|| platform::resolve_command("claude"));

    Command::new(&claude_path)
        .args(["auth", "login"])
        .spawn()
        .map_err(|e| format!("Could not launch claude auth login: {}", e))?;

    Ok(true)
}

/// Launch `codex login` directly — opens the browser for OAuth.
#[command]
pub async fn launch_codex_auth() -> Result<bool, String> {
    let codex_path = platform::resolve_codex_path()
        .unwrap_or_else(|| platform::resolve_command("codex"));

    Command::new(&codex_path)
        .args(["login"])
        .spawn()
        .map_err(|e| format!("Could not launch codex login: {}", e))?;

    Ok(true)
}
