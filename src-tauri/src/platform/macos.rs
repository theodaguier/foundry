use super::types::{BundleMapping, DependencySpec, InstallDir, InstallOperation};
use crate::models::plugin::PluginFormat;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

static SHELL_ENV: OnceLock<Vec<(String, String)>> = OnceLock::new();
static CLAUDE_PATH: OnceLock<Option<String>> = OnceLock::new();

fn resolve_shell_environment() -> Vec<(String, String)> {
    let output = Command::new("/bin/zsh")
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

/// Resolve the shell environment by spawning a login shell once and caching the result.
pub fn shell_environment() -> Vec<(String, String)> {
    SHELL_ENV.get_or_init(resolve_shell_environment).clone()
}

/// Resolve the Claude CLI binary path via the cached shell environment.
pub fn resolve_claude_path() -> Option<String> {
    CLAUDE_PATH
        .get_or_init(|| {
            let resolved = resolve_command("claude");
            if resolved == "claude" {
                None
            } else {
                Some(resolved)
            }
        })
        .clone()
}

fn path_from_cached_env(cmd: &str) -> Option<String> {
    if cmd.contains('/') {
        return Path::new(cmd).is_file().then(|| cmd.to_string());
    }

    let path_value = shell_environment()
        .into_iter()
        .find(|(key, _)| key == "PATH")
        .map(|(_, value)| value)?;

    for dir in path_value.split(':') {
        let candidate = Path::new(dir).join(cmd);
        if candidate.is_file() {
            return Some(candidate.to_string_lossy().to_string());
        }
    }

    None
}

/// Resolve a command path using the cached login shell environment.
pub fn resolve_command(cmd: &str) -> String {
    path_from_cached_env(cmd).unwrap_or_else(|| cmd.to_string())
}

/// Create a Command with proper process wrapping.
pub fn create_command(cmd: &str) -> Command {
    let mut c = Command::new("/usr/bin/env");
    c.arg(cmd);
    c
}

/// CMake configure arguments for macOS.
pub fn cmake_configure_args() -> Vec<String> {
    vec![
        "-DCMAKE_BUILD_TYPE=Debug".into(),
        "-DCMAKE_OSX_ARCHITECTURES=arm64".into(),
    ]
}

/// Plugin formats available on macOS.
pub fn available_plugin_formats() -> Vec<PluginFormat> {
    vec![PluginFormat::Au, PluginFormat::Vst3]
}

/// Install directories for each format on macOS.
pub fn plugin_install_dir(format: &PluginFormat) -> InstallDir {
    match format {
        PluginFormat::Au => InstallDir {
            format: PluginFormat::Au,
            path: PathBuf::from("/Library/Audio/Plug-Ins/Components"),
            needs_elevation: true,
        },
        PluginFormat::Vst3 => InstallDir {
            format: PluginFormat::Vst3,
            path: PathBuf::from("/Library/Audio/Plug-Ins/VST3"),
            needs_elevation: true,
        },
    }
}

fn run_privileged_script(script: &str) -> Result<(), String> {
    let apple_script = format!(
        "do shell script \"{}\" with administrator privileges",
        script.replace('\\', "\\\\").replace('"', "\\\"")
    );

    let output = Command::new("osascript")
        .args(["-e", &apple_script])
        .output()
        .map_err(|e| format!("Failed to run install script: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let detail = if stderr.trim().is_empty() {
            stdout.trim()
        } else {
            stderr.trim()
        };
        return Err(format!("Installation failed: {}", detail));
    }

    Ok(())
}

/// Install a plugin bundle to the destination with admin elevation.
/// Handles ditto, xattr, codesign via osascript.
pub fn install_plugin_bundle(src: &Path, dest: &Path) -> Result<(), String> {
    install_plugin_bundles(&[InstallOperation {
        format: if dest.extension().map(|e| e == "component").unwrap_or(false) {
            PluginFormat::Au
        } else {
            PluginFormat::Vst3
        },
        source: src.to_path_buf(),
        destination: dest.to_path_buf(),
    }])
}

pub fn install_plugin_bundles(operations: &[InstallOperation]) -> Result<(), String> {
    if operations.is_empty() {
        return Ok(());
    }

    let mut commands = Vec::new();

    for op in operations {
        let src_str = op.source.display().to_string();
        let dest_str = op.destination.display().to_string();
        commands.push(format!("rm -rf \"{}\"", dest_str));
        commands.push(format!("ditto \"{}\" \"{}\"", src_str, dest_str));
        commands.push(format!("xattr -cr \"{}\"", dest_str));
        commands.push(format!("codesign --deep --force --sign - \"{}\"", dest_str));
    }

    if operations
        .iter()
        .any(|op| matches!(op.format, PluginFormat::Au))
    {
        commands.push("killall -9 AudioComponentRegistrar 2>/dev/null || true".to_string());
    }

    run_privileged_script(&commands.join(" && "))
}

/// Post-install refresh on macOS.
/// The batched installer already performs the registrar refresh in the same
/// privileged script, so this becomes a no-op to avoid a redundant elevation.
pub fn post_install_refresh() -> Result<(), String> {
    Ok(())
}

/// Code sign a bundle with ad-hoc signature.
pub fn code_sign(bundle_path: &std::path::Path) -> Result<(), String> {
    let output = Command::new("codesign")
        .args([
            "--deep",
            "--force",
            "--sign",
            "-",
            &bundle_path.display().to_string(),
        ])
        .output()
        .map_err(|e| format!("Codesign failed: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Codesign failed: {}", stderr));
    }
    Ok(())
}

/// Temp build directory on macOS.
pub fn temp_build_dir(short_id: &str) -> PathBuf {
    PathBuf::from(format!("/tmp/foundry-build-{}", short_id))
}

/// Root temp directory for stale cleanup.
pub fn temp_root() -> PathBuf {
    PathBuf::from("/tmp")
}

/// Bundle extension mappings for macOS.
pub fn bundle_mappings() -> Vec<BundleMapping> {
    vec![
        BundleMapping {
            format_label: "AU",
            extension: ".component",
        },
        BundleMapping {
            format_label: "VST3",
            extension: ".vst3",
        },
    ]
}

/// Smoke test extensions to check on macOS.
pub fn smoke_test_extensions() -> Vec<&'static str> {
    vec![".component", ".vst3"]
}

/// Dependencies to check on macOS.
pub fn required_dependencies() -> Vec<DependencySpec> {
    vec![
        DependencySpec {
            name: "Xcode Command Line Tools",
            check_command: "xcode-select",
            check_args: &["-p"],
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

/// CMake format string for this platform.
pub fn cmake_formats(format: &str) -> &str {
    match format.to_uppercase().as_str() {
        "AU" => "AU",
        "VST3" => "VST3",
        _ => "AU VST3",
    }
}

/// Open a path in Finder.
pub fn show_in_file_manager(path: &str) -> Result<(), String> {
    Command::new("open")
        .args(["-R", path])
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}
