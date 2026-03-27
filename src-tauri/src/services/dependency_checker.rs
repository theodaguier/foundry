use crate::commands::dependencies::DependencyStatus;
use crate::platform;
use crate::services::build_environment;
use std::process::Command;

/// Check if Claude Code CLI is authenticated by running `claude auth status`.
fn check_claude_auth() -> bool {
    let resolved = platform::resolve_command("claude");
    if resolved == "claude" && platform::resolve_claude_path().is_none() {
        return false;
    }

    let cmd_path = platform::resolve_claude_path().unwrap_or_else(|| resolved);

    let mut cmd = Command::new(&cmd_path);
    cmd.args(["auth", "status"]);

    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x08000000);
    }

    match cmd.output() {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            stdout.contains("\"loggedIn\":true") || stdout.contains("\"loggedIn\": true")
        }
        _ => false,
    }
}

pub async fn check_all() -> Result<Vec<DependencyStatus>, String> {
    let mut deps = Vec::new();

    // Platform-specific dependencies (C++ toolchain, CMake, Claude CLI, etc.)
    for spec in platform::required_dependencies() {
        let result = platform::check_dependency(&spec);
        let is_installed = result.is_some();

        // For Claude Code: also check authentication
        let auth_required = if spec.name == "Claude Code CLI" && is_installed {
            !check_claude_auth()
        } else {
            false
        };

        deps.push(DependencyStatus {
            name: spec.name.to_string(),
            installed: is_installed,
            auth_required,
            detail: result.clone(),
            version: result,
        });
    }

    let environment = build_environment::get_build_environment().await?;
    deps.push(DependencyStatus {
        name: "JUCE SDK".into(),
        installed: environment.juce_path.is_some(),
        auth_required: false,
        detail: environment.juce_path.as_ref().map(|path| {
            match environment.juce_source.as_deref() {
                Some(source) => format!("{} ({})", path, source),
                None => path.clone(),
            }
        }),
        version: Some(environment.juce_version),
    });

    Ok(deps)
}

pub async fn install_juce() -> Result<build_environment::BuildEnvironmentStatus, String> {
    build_environment::install_managed_juce().await
}
