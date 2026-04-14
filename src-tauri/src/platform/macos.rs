use super::types::{BundleMapping, DependencySpec, InstallDir, InstallOperation};
use crate::models::plugin::PluginFormat;
use crate::services::foundry_paths;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::RwLock;

static SHELL_ENV: RwLock<Option<Vec<(String, String)>>> = RwLock::new(None);
static CLAUDE_PATH: RwLock<Option<Option<String>>> = RwLock::new(None);
static CODEX_PATH: RwLock<Option<Option<String>>> = RwLock::new(None);

fn resolve_shell_environment() -> Vec<(String, String)> {
    let output = Command::new("/bin/zsh").args(["-lic", "env"]).output().ok();
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
    {
        let guard = SHELL_ENV.read().unwrap();
        if let Some(env) = guard.as_ref() {
            return env.clone();
        }
    }
    let env = resolve_shell_environment();
    *SHELL_ENV.write().unwrap() = Some(env.clone());
    env
}

/// Resolve the Claude CLI binary path via the cached shell environment.
pub fn resolve_claude_path() -> Option<String> {
    resolve_provider_path("claude", &CLAUDE_PATH)
}

/// Resolve the Codex CLI binary path via the cached shell environment.
pub fn resolve_codex_path() -> Option<String> {
    resolve_provider_path("codex", &CODEX_PATH)
}

fn resolve_provider_path(command: &str, cache: &RwLock<Option<Option<String>>>) -> Option<String> {
    {
        let guard = cache.read().unwrap();
        if let Some(cached) = guard.as_ref() {
            return cached.clone();
        }
    }

    let resolution = crate::platform::select_provider_resolution(
        foundry_paths::provider_path_override(command),
        resolve_known_cli(command),
        provider_fallback_paths(command),
    );

    // NOTE: We intentionally do NOT clear the override here if the override target
    // is temporarily missing (e.g. during a managed install replacement window).
    // The override is authoritative — it was written by a deliberate install/verify
    // action and must not be discarded by a concurrent read. Override cleanup
    // happens only via explicit reset_local_app_state() or reset_debug_dependencies().
    *cache.write().unwrap() = Some(resolution.path.clone());
    resolution.path
}

/// Clear cached shell environment and tool paths so newly installed tools are detected.
pub fn invalidate_shell_cache() {
    *SHELL_ENV.write().unwrap() = None;
    *CLAUDE_PATH.write().unwrap() = None;
    *CODEX_PATH.write().unwrap() = None;
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
/// Falls back to managed tool installations for cmake, npm, and node.
pub fn resolve_command(cmd: &str) -> String {
    if let Some(resolved) = path_from_cached_env(cmd) {
        if resolved != cmd {
            return resolved;
        }
    }

    let managed = match cmd {
        "cmake" => foundry_paths::managed_cmake_binary(),
        "npm" => foundry_paths::managed_npm_binary(),
        "node" => foundry_paths::managed_node_binary(),
        _ => return cmd.to_string(),
    };
    if managed.is_file() {
        return managed.to_string_lossy().to_string();
    }

    cmd.to_string()
}

fn resolve_known_cli(cmd: &str) -> Option<String> {
    let resolved = resolve_command(cmd);
    (resolved != cmd).then_some(resolved)
}

fn provider_fallback_paths(command: &str) -> Vec<PathBuf> {
    let mut fallbacks = Vec::new();

    if let Some(npm_path) = resolve_known_cli("npm").or_else(find_npm_in_common_locations) {
        if let Some(candidate) = global_cli_path_from_npm(&npm_path, command) {
            fallbacks.push(candidate);
        }
    }

    for dir in common_global_bin_dirs() {
        fallbacks.push(dir.join(command));
    }

    fallbacks
}

fn common_global_bin_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();

    if let Some(home) = dirs::home_dir() {
        dirs.push(home.join(".npm-global").join("bin"));
        dirs.push(home.join(".local").join("bin"));
    }

    dirs.push(PathBuf::from("/opt/homebrew/bin"));
    dirs.push(PathBuf::from("/usr/local/bin"));

    dirs
}

fn find_npm_in_common_locations() -> Option<String> {
    ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]
        .iter()
        .find(|path| Path::new(path).is_file())
        .map(|path| path.to_string())
}

pub fn global_cli_path_from_npm(npm_path: &str, cli_name: &str) -> Option<PathBuf> {
    crate::platform::global_cli_path_from_npm_binary(
        PathBuf::from(npm_path),
        cli_name,
        crate::platform::ProviderPlatform::Unix,
    )
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
            path: PathBuf::from("/Library/Audio/Plug-Ins/Components"),
        },
        PluginFormat::Vst3 => InstallDir {
            path: PathBuf::from("/Library/Audio/Plug-Ins/VST3"),
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
        DependencySpec {
            name: "Codex CLI",
            check_command: "codex",
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
