use super::types::{BundleMapping, DependencySpec, InstallDir, InstallOperation};
use crate::models::plugin::PluginFormat;
use std::path::PathBuf;
use std::process::Command;

/// Resolve the shell environment by spawning a login bash shell.
pub fn shell_environment() -> Vec<(String, String)> {
    let output = Command::new("/bin/bash")
        .args(["-l", "-c", "env"])
        .output()
        .ok();
    let mut env = Vec::new();
    if let Some(out) = output {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            if let Some((k, v)) = line.split_once('=') {
                env.push((k.to_string(), v.to_string()));
            }
        }
    }
    env
}

/// Resolve the Claude CLI binary path via login shell.
pub fn resolve_claude_path() -> Option<String> {
    let output = Command::new("/bin/bash")
        .args(["-l", "-c", "which claude"])
        .output()
        .ok()?;
    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    }
}

/// Resolve the Codex CLI binary path via login shell.
pub fn resolve_codex_path() -> Option<String> {
    let output = Command::new("/bin/bash")
        .args(["-l", "-c", "which codex"])
        .output()
        .ok()?;
    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    }
}

/// Resolve a command path using the login shell.
pub fn resolve_command(cmd: &str) -> String {
    Command::new("/bin/bash")
        .args(["-l", "-c", &format!("which {}", cmd)])
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
        .unwrap_or_else(|| cmd.to_string())
}

/// Create a Command with proper process wrapping.
pub fn create_command(cmd: &str) -> Command {
    let mut c = Command::new("/usr/bin/env");
    c.arg(cmd);
    c
}

/// CMake configure arguments for Linux.
pub fn cmake_configure_args() -> Vec<String> {
    vec!["-DCMAKE_BUILD_TYPE=Debug".into()]
}

/// Only VST3 is available on Linux (LV2 support can be added later).
pub fn available_plugin_formats() -> Vec<PluginFormat> {
    vec![PluginFormat::Vst3]
}

/// Install directory for VST3 on Linux (user-local, no elevation needed).
pub fn plugin_install_dir(format: &PluginFormat) -> InstallDir {
    match format {
        PluginFormat::Vst3 => {
            let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/tmp"));
            InstallDir {
                format: PluginFormat::Vst3,
                path: home.join(".vst3"),
                needs_elevation: false,
            }
        }
        // AU is not supported on Linux
        PluginFormat::Au => plugin_install_dir(&PluginFormat::Vst3),
    }
}

/// Install a plugin bundle using plain file copy (user-local, no elevation).
pub fn install_plugin_bundle(src: &std::path::Path, dest: &std::path::Path) -> Result<(), String> {
    if dest.exists() {
        std::fs::remove_dir_all(dest).map_err(|e| format!("Failed to remove old bundle: {}", e))?;
    }
    copy_dir_all(src, dest).map_err(|e| format!("Failed to copy bundle: {}", e))
}

pub fn install_plugin_bundles(operations: &[InstallOperation]) -> Result<(), String> {
    for operation in operations {
        install_plugin_bundle(&operation.source, &operation.destination)?;
    }
    Ok(())
}

/// No post-install refresh needed on Linux.
pub fn post_install_refresh() -> Result<(), String> {
    Ok(())
}

/// No code signing on Linux.
pub fn code_sign(_bundle_path: &std::path::Path) -> Result<(), String> {
    Ok(())
}

/// Temp build directory on Linux.
pub fn temp_build_dir(short_id: &str) -> PathBuf {
    PathBuf::from(format!("/tmp/foundry-build-{}", short_id))
}

/// Root temp directory for stale cleanup.
pub fn temp_root() -> PathBuf {
    PathBuf::from("/tmp")
}

/// Bundle extension mappings for Linux.
pub fn bundle_mappings() -> Vec<BundleMapping> {
    vec![BundleMapping {
        format_label: "VST3",
        extension: ".vst3",
    }]
}

/// Smoke test extensions on Linux.
pub fn smoke_test_extensions() -> Vec<&'static str> {
    vec![".vst3"]
}

/// Dependencies to check on Linux.
pub fn required_dependencies() -> Vec<DependencySpec> {
    vec![
        DependencySpec {
            name: "C++ Compiler",
            check_command: "g++",
            check_args: &["--version"],
        },
        DependencySpec {
            name: "CMake",
            check_command: "cmake",
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

/// CMake format string for Linux (VST3 only).
pub fn cmake_formats(format: &str) -> &str {
    match format.to_uppercase().as_str() {
        "VST3" => "VST3",
        _ => "VST3",
    }
}

/// Open path in the default file manager.
pub fn show_in_file_manager(path: &str) -> Result<(), String> {
    Command::new("xdg-open")
        .arg(path)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn invalidate_shell_cache() {
    // No-op on Linux — shell env is not cached with OnceLock on this platform.
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
