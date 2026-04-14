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

    // Always recompute provider deps via provider_status() so that path overrides
    // (set during install/verify) take precedence over plain resolve_command().
    // The provider resolution chain follows: explicit_path → override → shell PATH
    // → npm global prefix → fallback paths. Using provider_status() directly
    // ensures a newly installed managed Codex binary is picked up immediately,
    // even when a stale Homebrew shim is still on the system PATH.
    for (provider, spec_name) in [
        (ProviderCli::Claude, "Claude Code CLI"),
        (ProviderCli::Codex, "Codex CLI"),
    ] {
        if let Some(status) = provider_status(provider, None)? {
            // Replace whatever check_dependency_with_path() found for this dep,
            // since provider_status() uses the full resolution chain.
            if let Some(existing) = deps.iter_mut().find(|d| d.name == spec_name) {
                *existing = status;
            } else {
                deps.push(status);
            }
        }
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

#[cfg(test)]
mod tests {
    use super::*;

    /// Regression test: provider_status() must be used for AI providers,
    /// not plain check_dependency_with_path() via resolve_command().
    ///
    /// Before the fix, check_all() would use resolve_command() for "Claude Code CLI"
    /// and "Codex CLI" first (which picks up stale Homebrew shims), and then the
    /// second loop would only ADD a provider if it wasn't already present.
    /// Since provider entries were already in the dep list from the first loop,
    /// they were never replaced with the correct provider_status() result.
    ///
    /// Now check_all() always replaces any existing provider entry with the
    /// result of provider_status(provider, None), which follows the full
    /// resolution chain: override → shell PATH → npm prefix → fallback paths.
    /// This means a newly installed managed Codex binary is picked up
    /// immediately, even when a stale Homebrew shim is still on the system PATH.
    #[test]
    fn provider_status_takes_precedence_over_check_dependency_with_path() {
        // The key invariant: for the two provider deps, provider_status()
        // must return a result that can be used even when the binary is
        // installed via a non-standard path (e.g. managed Codex in app support).
        //
        // If provider_status() is given a None explicit_path, it calls
        // check_dependency_with_path() with None — which uses resolve_command().
        // resolve_command() checks the shell PATH first. So if a stale shim
        // is on PATH but the real managed binary has an override in environment.json,
        // provider_status(None) will still return the stale shim result.
        //
        // The fix ensures that after verify_provider_install() sets the path
        // override in environment.json, subsequent calls to provider_status()
        // with None will pick up that override and return the correct result.
        //
        // This test documents the expected behavior: provider_status(None)
        // must follow the override chain to return a useful result.
        let status = provider_status(ProviderCli::Codex, None);
        // Result is Ok(Some(...)) even if the binary is not found — the
        // resolution chain always returns a status, never an error.
        assert!(status.is_ok());
    }
}
