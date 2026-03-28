use super::types::{BundleMapping, DependencySpec, InstallDir, InstallOperation};
use crate::models::plugin::PluginFormat;
use std::os::windows::process::CommandExt;
use std::path::Path;
use std::path::PathBuf;
use std::process::Command;

const CREATE_NO_WINDOW: u32 = 0x08000000;

/// On Windows, inherit the system environment directly (no login shell).
pub fn shell_environment() -> Vec<(String, String)> {
    let mut env_vars: Vec<(String, String)> = std::env::vars().collect();

    let has_valid_git_bash = env_vars
        .iter()
        .find(|(key, _)| key == "CLAUDE_CODE_GIT_BASH_PATH")
        .map(|(_, value)| Path::new(value).is_file())
        .unwrap_or(false);

    if !has_valid_git_bash {
        if let Some(path) = resolve_git_bash_path() {
            if let Some(existing) = env_vars
                .iter_mut()
                .find(|(key, _)| key == "CLAUDE_CODE_GIT_BASH_PATH")
            {
                existing.1 = path;
            } else {
                env_vars.push(("CLAUDE_CODE_GIT_BASH_PATH".into(), path));
            }
        }
    }

    env_vars
}

/// Resolve Claude CLI path using `where` on Windows.
pub fn resolve_claude_path() -> Option<String> {
    resolve_known_cli("claude")
}

/// Resolve Codex CLI path using `where` on Windows.
pub fn resolve_codex_path() -> Option<String> {
    resolve_known_cli("codex")
}

/// Resolve the Git Bash executable required by Claude Code on native Windows.
pub fn resolve_git_bash_path() -> Option<String> {
    if let Ok(path) = std::env::var("CLAUDE_CODE_GIT_BASH_PATH") {
        if Path::new(&path).is_file() {
            return Some(path);
        }
    }

    if let Some(path) = git_path_derived_bash() {
        return Some(path);
    }

    for candidate in common_git_bash_locations() {
        if candidate.is_file() {
            return Some(candidate.to_string_lossy().to_string());
        }
    }

    None
}

/// Resolve a command path using `where`.
pub fn resolve_command(cmd: &str) -> String {
    Command::new("cmd")
        .args(["/C", "where", cmd])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                String::from_utf8(o.stdout)
                    .ok()
                    .and_then(|s| s.lines().next().map(|l| l.trim().to_string()))
            } else {
                None
            }
        })
        .unwrap_or_else(|| cmd.to_string())
}

/// Create a Command directly (no /usr/bin/env on Windows).
/// Automatically hides console windows.
pub fn create_command(cmd: &str) -> Command {
    let mut c = Command::new(cmd);
    c.creation_flags(CREATE_NO_WINDOW);
    c
}

/// CMake configure arguments for Windows (use Ninja for consistency).
pub fn cmake_configure_args() -> Vec<String> {
    vec![
        "-G".into(),
        "Visual Studio 17 2022".into(),
        "-A".into(),
        "x64".into(),
    ]
}

/// Only VST3 is available on Windows.
pub fn available_plugin_formats() -> Vec<PluginFormat> {
    vec![PluginFormat::Vst3]
}

/// Install directory for VST3 on Windows.
pub fn plugin_install_dir(format: &PluginFormat) -> InstallDir {
    match format {
        PluginFormat::Vst3 => {
            let common = std::env::var("COMMONPROGRAMFILES")
                .unwrap_or_else(|_| r"C:\Program Files\Common Files".into());
            InstallDir {
                format: PluginFormat::Vst3,
                path: PathBuf::from(common).join("VST3"),
                needs_elevation: true,
            }
        }
        // AU is not supported on Windows — install to VST3 path as fallback
        PluginFormat::Au => plugin_install_dir(&PluginFormat::Vst3),
    }
}

/// Install a plugin bundle using robocopy with elevation via PowerShell.
pub fn install_plugin_bundle(src: &std::path::Path, dest: &std::path::Path) -> Result<(), String> {
    install_plugin_bundles(&[InstallOperation {
        format: PluginFormat::Vst3,
        source: src.to_path_buf(),
        destination: dest.to_path_buf(),
    }])
}

pub fn install_plugin_bundles(operations: &[InstallOperation]) -> Result<(), String> {
    if operations.is_empty() {
        return Ok(());
    }

    // Try direct copy first (works if user has write access)
    let mut direct_copy_ok = true;
    for op in operations {
        if op.destination.exists() {
            let _ = std::fs::remove_dir_all(&op.destination);
        }
        if copy_dir_all(&op.source, &op.destination).is_err() {
            direct_copy_ok = false;
            break;
        }
    }
    if direct_copy_ok {
        return Ok(());
    }

    // Clean up any partial direct-copy results before elevated fallback
    for op in operations {
        if op.destination.exists() {
            let _ = std::fs::remove_dir_all(&op.destination);
        }
    }

    // Fall back to one elevated PowerShell process running all robocopy commands
    let robocopy_commands = operations
        .iter()
        .map(|op| {
            let src_str = op.source.display().to_string();
            let dest_str = op.destination.display().to_string();
            format!(
                "robocopy '\"{}\"' '\"{}\"' /E /NFL /NDL /NJH /NJS | Out-Null",
                src_str, dest_str
            )
        })
        .collect::<Vec<_>>()
        .join("; ");

    let ps_cmd = format!(
        "Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile','-Command','{}' -Verb RunAs -Wait",
        robocopy_commands.replace('\'', "''")
    );

    let output = Command::new("powershell")
        .args(["-Command", &ps_cmd])
        .output()
        .map_err(|e| format!("Failed to run install: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Installation failed: {}", stderr));
    }
    Ok(())
}

/// No post-install refresh needed on Windows.
pub fn post_install_refresh() -> Result<(), String> {
    Ok(())
}

/// Code signing on Windows — skip for now (no-op).
pub fn code_sign(_bundle_path: &std::path::Path) -> Result<(), String> {
    Ok(())
}

/// Temp build directory on Windows.
pub fn temp_build_dir(short_id: &str) -> PathBuf {
    std::env::temp_dir().join(format!("foundry-build-{}", short_id))
}

/// Root temp directory for stale cleanup.
pub fn temp_root() -> PathBuf {
    std::env::temp_dir()
}

/// Bundle extension mappings for Windows.
pub fn bundle_mappings() -> Vec<BundleMapping> {
    vec![BundleMapping {
        format_label: "VST3",
        extension: ".vst3",
    }]
}

/// Smoke test extensions on Windows.
pub fn smoke_test_extensions() -> Vec<&'static str> {
    vec![".vst3"]
}

/// Dependencies to check on Windows.
pub fn required_dependencies() -> Vec<DependencySpec> {
    vec![
        DependencySpec {
            name: "C++ Build Tools",
            check_command: "__vs_build_tools__",
            check_args: &[],
        },
        DependencySpec {
            name: "CMake",
            check_command: "cmake",
            check_args: &["--version"],
        },
        DependencySpec {
            name: "Git",
            check_command: "git",
            check_args: &["--version"],
        },
        DependencySpec {
            name: "Claude Code CLI",
            check_command: "claude",
            check_args: &["--version"],
        },
        DependencySpec {
            name: "Codex CLI",
            check_command: "codex",
            check_args: &["--version"],
        },
    ]
}

/// Check a dependency by resolving and running its command.
pub fn check_dependency(spec: &DependencySpec) -> Option<String> {
    if spec.check_command == "__vs_build_tools__" {
        return resolve_visual_studio_installation();
    }

    let resolved = resolve_command(spec.check_command);
    Command::new(&resolved)
        .args(spec.check_args)
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                String::from_utf8(o.stdout)
                    .ok()
                    .map(|s| s.trim().to_string())
            } else {
                None
            }
        })
}

/// CMake format string for Windows (VST3 only).
pub fn cmake_formats(format: &str) -> &str {
    match format.to_uppercase().as_str() {
        "VST3" => "VST3",
        _ => "VST3", // AU not available, default to VST3
    }
}

/// Open path in Windows Explorer.
pub fn show_in_file_manager(path: &str) -> Result<(), String> {
    Command::new("explorer")
        .args(["/select,", path])
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn invalidate_shell_cache() {
    // No-op on Windows — shell env is not cached with OnceLock on this platform.
}

fn resolve_visual_studio_installation() -> Option<String> {
    let program_files_x86 = std::env::var("ProgramFiles(x86)")
        .or_else(|_| std::env::var("ProgramFiles"))
        .ok()?;
    let vswhere = PathBuf::from(program_files_x86)
        .join("Microsoft Visual Studio")
        .join("Installer")
        .join("vswhere.exe");

    if !vswhere.is_file() {
        return None;
    }

    let output = Command::new(vswhere)
        .args([
            "-latest",
            "-products",
            "*",
            "-requires",
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "-property",
            "installationPath",
        ])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let installation_path = stdout.trim();
    (!installation_path.is_empty()).then(|| installation_path.to_string())
}

fn copy_dir_all(src: &std::path::Path, dst: &std::path::Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let dest = dst.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir_all(&entry.path(), &dest)?;
        } else {
            std::fs::copy(entry.path(), dest)?;
        }
    }
    Ok(())
}

fn resolve_known_cli(cmd: &str) -> Option<String> {
    let candidates = where_results(cmd);

    candidates
        .iter()
        .find(|path| path.to_ascii_lowercase().ends_with(".cmd"))
        .cloned()
        .or_else(|| {
            candidates
                .iter()
                .find(|path| path.to_ascii_lowercase().ends_with(".exe"))
                .cloned()
        })
        .or_else(|| candidates.into_iter().next())
}

fn where_results(cmd: &str) -> Vec<String> {
    let output = match Command::new("cmd")
        .args(["/C", "where", cmd])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    {
        Ok(output) if output.status.success() => output,
        _ => return Vec::new(),
    };

    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

fn git_path_derived_bash() -> Option<String> {
    let git_path = resolve_command("git");
    let git_path = PathBuf::from(git_path);
    if !git_path.is_file() {
        return None;
    }

    let git_dir = git_path.parent()?;
    let git_root = match git_dir.file_name().and_then(|name| name.to_str()) {
        Some("cmd") | Some("bin") => git_dir.parent()?,
        _ => git_dir,
    };

    for relative in ["bin/bash.exe", "usr/bin/bash.exe"] {
        let candidate = git_root.join(relative);
        if candidate.is_file() {
            return Some(candidate.to_string_lossy().to_string());
        }
    }

    None
}

fn common_git_bash_locations() -> Vec<PathBuf> {
    let mut roots = Vec::new();

    for env_key in ["ProgramFiles", "ProgramFiles(x86)", "LocalAppData"] {
        if let Ok(value) = std::env::var(env_key) {
            if !value.is_empty() {
                roots.push(PathBuf::from(value));
            }
        }
    }

    let mut candidates = Vec::new();
    for root in roots {
        for relative in [
            "Git/bin/bash.exe",
            "Git/usr/bin/bash.exe",
            "Programs/Git/bin/bash.exe",
            "Programs/Git/usr/bin/bash.exe",
        ] {
            candidates.push(root.join(relative));
        }
    }

    candidates
}
