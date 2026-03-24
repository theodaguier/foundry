use super::types::{BundleMapping, DependencySpec, InstallDir, InstallOperation};
use crate::models::plugin::PluginFormat;
use std::path::PathBuf;
use std::process::Command;

/// On Windows, inherit the system environment directly (no login shell).
pub fn shell_environment() -> Vec<(String, String)> {
    std::env::vars().collect()
}

/// Resolve Claude CLI path using `where` on Windows.
pub fn resolve_claude_path() -> Option<String> {
    let output = Command::new("cmd")
        .args(["/C", "where", "claude"])
        .output()
        .ok()?;
    if output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        // `where` may return multiple lines — take the first
        stdout.lines().next().map(|s| s.trim().to_string())
    } else {
        None
    }
}

/// Resolve Codex CLI path using `where` on Windows.
pub fn resolve_codex_path() -> Option<String> {
    let output = Command::new("cmd")
        .args(["/C", "where", "codex"])
        .output()
        .ok()?;
    if output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        stdout.lines().next().map(|s| s.trim().to_string())
    } else {
        None
    }
}

/// Resolve a command path using `where`.
pub fn resolve_command(cmd: &str) -> String {
    Command::new("cmd")
        .args(["/C", "where", cmd])
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
pub fn create_command(cmd: &str) -> Command {
    Command::new(cmd)
}

/// CMake configure arguments for Windows (use Ninja for consistency).
pub fn cmake_configure_args() -> Vec<String> {
    vec![
        "-G".into(),
        "Ninja".into(),
        "-DCMAKE_BUILD_TYPE=Debug".into(),
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
            check_command: "cl",
            check_args: &[],
        },
        DependencySpec {
            name: "CMake",
            check_command: "cmake",
            check_args: &["--version"],
        },
        DependencySpec {
            name: "Ninja",
            check_command: "ninja",
            check_args: &["--version"],
        },
        DependencySpec {
            name: "Claude Code CLI",
            check_command: "claude",
            check_args: &["--version"],
        },
    ]
}

/// Check a dependency by resolving and running its command.
pub fn check_dependency(spec: &DependencySpec) -> Option<String> {
    let resolved = resolve_command(spec.check_command);
    Command::new(&resolved)
        .args(spec.check_args)
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
