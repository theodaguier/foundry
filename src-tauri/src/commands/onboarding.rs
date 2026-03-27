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
        return Ok(onboarding::DependencyInstallResult {
            success: false,
            message: "Another install is already in progress. Please wait.".into(),
        });
    }

    let result = tokio::task::spawn_blocking(move || match name.as_str() {
        "xcode_clt" => onboarding::install_xcode_clt(),
        "cpp_build_tools" => onboarding::install_cpp_build_tools(),
        "cmake" => onboarding::install_cmake(),
        "git" => onboarding::install_git(),
        "claude_code" => onboarding::install_claude_code(),
        "codex" => onboarding::install_codex(),
        _ => onboarding::DependencyInstallResult {
            success: false,
            message: format!("Unknown dependency: {}", name),
        },
    })
    .await
    .map_err(|e| {
        onboarding::release_install_lock();
        e.to_string()
    })?;

    // Invalidate cached shell environment so newly installed tools are detected
    platform::invalidate_shell_cache();
    onboarding::release_install_lock();

    Ok(result)
}

/// Open a terminal window running `claude` so the user can complete the
/// interactive OAuth sign-in flow.
#[command]
pub async fn launch_claude_auth() -> Result<bool, String> {
    let claude_path = platform::resolve_claude_path()
        .unwrap_or_else(|| platform::resolve_command("claude"));

    #[cfg(target_os = "macos")]
    {
        // Open Terminal.app running claude
        let script = format!(
            "tell application \"Terminal\"
                activate
                do script \"'{}'\"
            end tell",
            claude_path
        );
        Command::new("osascript")
            .args(["-e", &script])
            .spawn()
            .map_err(|e| format!("Could not open Terminal: {}", e))?;
        return Ok(true);
    }

    #[cfg(target_os = "windows")]
    {
        // Open a new CMD window running claude
        Command::new("cmd")
            .args(["/c", "start", "cmd", "/k", &claude_path])
            .spawn()
            .map_err(|e| format!("Could not open terminal: {}", e))?;
        return Ok(true);
    }

    #[cfg(target_os = "linux")]
    {
        // Try common terminal emulators
        for term in &["gnome-terminal", "konsole", "xterm"] {
            if Command::new(term)
                .args(["--", &claude_path])
                .spawn()
                .is_ok()
            {
                return Ok(true);
            }
        }
        return Err("Could not find a terminal emulator.".into());
    }
}
