use crate::commands::dependencies::DependencyStatus;
use crate::platform;
use crate::services::build_environment;
use crate::services::onboarding::ProviderCli;
use std::process::Command;

/// Check if Claude Code CLI is authenticated by running `claude auth status`.
fn check_claude_auth(explicit_path: Option<&str>) -> bool {
    let resolved = explicit_path
        .map(ToOwned::to_owned)
        .or_else(platform::resolve_claude_path)
        .unwrap_or_else(|| platform::resolve_command("claude"));

    if resolved == "claude" {
        return false;
    }

    let mut cmd = Command::new(&resolved);
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

/// Check if Codex CLI is authenticated by running `codex login status`.
fn check_codex_auth(explicit_path: Option<&str>) -> bool {
    let resolved = explicit_path
        .map(ToOwned::to_owned)
        .or_else(platform::resolve_codex_path)
        .unwrap_or_else(|| platform::resolve_command("codex"));

    if resolved == "codex" {
        return false;
    }

    let mut cmd = Command::new(&resolved);
    cmd.args(["login", "status"]);

    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x08000000);
    }

    match cmd.output() {
        Ok(output) => output.status.success(),
        _ => false,
    }
}

fn check_dependency_with_path(
    spec: &platform::types::DependencySpec,
    explicit_path: Option<&str>,
) -> Option<String> {
    if spec.check_command == "__vs_build_tools__" {
        return platform::check_dependency(spec);
    }

    let command_path = explicit_path
        .map(ToOwned::to_owned)
        .unwrap_or_else(|| platform::resolve_command(spec.check_command));

    let mut cmd = Command::new(&command_path);
    cmd.args(spec.check_args);
    apply_windows_creation_flags(&mut cmd);

    cmd.output().ok().and_then(|output| {
        if output.status.success() {
            String::from_utf8(output.stdout)
                .ok()
                .map(|s| s.trim().to_string())
        } else {
            None
        }
    })
}

pub fn provider_status(
    provider: ProviderCli,
    explicit_path: Option<&str>,
) -> Result<Option<DependencyStatus>, String> {
    let Some(spec) = platform::required_dependencies()
        .into_iter()
        .find(|spec| spec.name == provider.dependency_name())
    else {
        return Ok(None);
    };

    let version = check_dependency_with_path(&spec, explicit_path);
    let is_installed = version.is_some();
    let auth_required = match provider {
        ProviderCli::Claude if is_installed => !check_claude_auth(explicit_path),
        ProviderCli::Codex if is_installed => !check_codex_auth(explicit_path),
        _ => false,
    };

    Ok(Some(DependencyStatus {
        name: spec.name.to_string(),
        installed: is_installed,
        auth_required,
        detail: version.clone(),
        version,
    }))
}

pub async fn check_all() -> Result<Vec<DependencyStatus>, String> {
    let mut deps = Vec::new();

    // Platform-specific dependencies (C++ toolchain, CMake, Claude CLI, etc.)
    for spec in platform::required_dependencies() {
        let version = check_dependency_with_path(&spec, None);
        let is_installed = version.is_some();

        let auth_required = if spec.name == "Claude Code CLI" && is_installed {
            !check_claude_auth(None)
        } else if spec.name == "Codex CLI" && is_installed {
            !check_codex_auth(None)
        } else {
            false
        };

        deps.push(DependencyStatus {
            name: spec.name.to_string(),
            installed: is_installed,
            auth_required,
            detail: version.clone(),
            version,
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

fn apply_windows_creation_flags(cmd: &mut Command) {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x08000000);
    }

    #[cfg(not(target_os = "windows"))]
    {
        let _ = cmd;
    }
}
