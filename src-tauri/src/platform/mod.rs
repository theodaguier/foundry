//! Platform abstraction layer.
//!
//! All platform-specific logic is centralized here. Services call `platform::*`
//! functions and never use `#[cfg]` directly.

pub mod types;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "linux")]
use linux as imp;
#[cfg(target_os = "macos")]
use macos as imp;
#[cfg(target_os = "windows")]
use windows as imp;

use crate::models::plugin::PluginFormat;
use std::path::PathBuf;
use types::{BundleMapping, DependencySpec, InstallDir, InstallOperation};

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderPlatform {
    Windows,
    Unix,
}

#[derive(Debug, Clone)]
pub struct ProviderResolution {
    pub path: Option<String>,
    pub clear_override: bool,
}

// ---- Shell & CLI resolution ----

pub fn shell_environment() -> Vec<(String, String)> {
    imp::shell_environment()
}

pub fn resolve_claude_path() -> Option<String> {
    imp::resolve_claude_path()
}

pub fn resolve_codex_path() -> Option<String> {
    imp::resolve_codex_path()
}

pub fn resolve_command(cmd: &str) -> String {
    imp::resolve_command(cmd)
}

pub fn global_cli_path_from_npm(npm_path: &str, cli_name: &str) -> Option<PathBuf> {
    imp::global_cli_path_from_npm(npm_path, cli_name)
}

pub fn create_command(cmd: &str) -> std::process::Command {
    imp::create_command(cmd)
}

// ---- Build ----

pub fn cmake_configure_args() -> Vec<String> {
    imp::cmake_configure_args()
}

pub fn cmake_formats(format: &str) -> &str {
    imp::cmake_formats(format)
}

pub fn temp_build_dir(short_id: &str) -> PathBuf {
    imp::temp_build_dir(short_id)
}

pub fn temp_root() -> PathBuf {
    imp::temp_root()
}

// ---- Plugin formats ----

pub fn available_plugin_formats() -> Vec<PluginFormat> {
    imp::available_plugin_formats()
}

/// Returns the platform default install directory (ignoring user overrides).
pub fn default_plugin_install_dir(format: &PluginFormat) -> InstallDir {
    imp::plugin_install_dir(format)
}

/// Returns the effective install directory, checking user overrides first.
pub fn plugin_install_dir(format: &PluginFormat) -> InstallDir {
    if let Some(override_path) = crate::services::foundry_paths::install_path_override(format) {
        return InstallDir { path: override_path };
    }
    imp::plugin_install_dir(format)
}

pub fn bundle_mappings() -> Vec<BundleMapping> {
    imp::bundle_mappings()
}

pub fn smoke_test_extensions() -> Vec<&'static str> {
    imp::smoke_test_extensions()
}

// ---- Install ----

pub fn install_plugin_bundles(operations: &[InstallOperation]) -> Result<(), String> {
    imp::install_plugin_bundles(operations)
}

pub fn post_install_refresh() -> Result<(), String> {
    imp::post_install_refresh()
}

// ---- Dependencies ----

pub fn required_dependencies() -> Vec<DependencySpec> {
    imp::required_dependencies()
}

pub fn check_dependency(spec: &DependencySpec) -> Option<String> {
    imp::check_dependency(spec)
}

// ---- Cache ----

pub fn invalidate_shell_cache() {
    imp::invalidate_shell_cache()
}

// ---- File manager ----

pub fn show_in_file_manager(path: &str) -> Result<(), String> {
    imp::show_in_file_manager(path)
}

pub(crate) fn cli_shim_from_prefix(
    prefix: impl AsRef<std::path::Path>,
    cli_name: &str,
    platform: ProviderPlatform,
) -> PathBuf {
    let prefix = prefix.as_ref();
    match platform {
        ProviderPlatform::Windows => prefix.join(format!("{}.cmd", cli_name)),
        ProviderPlatform::Unix => prefix.join("bin").join(cli_name),
    }
}

pub(crate) fn global_cli_path_from_npm_binary(
    npm_path: impl AsRef<std::path::Path>,
    cli_name: &str,
    platform: ProviderPlatform,
) -> Option<PathBuf> {
    let npm_path = npm_path.as_ref();
    let npm_dir = npm_path.parent()?;

    match platform {
        ProviderPlatform::Windows => Some(npm_dir.join(format!("{}.cmd", cli_name))),
        ProviderPlatform::Unix => npm_dir
            .parent()
            .map(|prefix| cli_shim_from_prefix(prefix, cli_name, platform))
            .or_else(|| Some(npm_dir.join(cli_name))),
    }
}

pub(crate) fn select_provider_resolution(
    override_path: Option<PathBuf>,
    resolved_path: Option<String>,
    fallback_paths: Vec<PathBuf>,
) -> ProviderResolution {
    if let Some(path) = override_path {
        if path.is_file() {
            return ProviderResolution {
                path: Some(path.to_string_lossy().to_string()),
                clear_override: false,
            };
        }

        return ProviderResolution {
            path: resolved_path.or_else(|| first_existing_path(fallback_paths)),
            clear_override: true,
        };
    }

    ProviderResolution {
        path: resolved_path.or_else(|| first_existing_path(fallback_paths)),
        clear_override: false,
    }
}

fn first_existing_path(paths: Vec<PathBuf>) -> Option<String> {
    paths.into_iter()
        .find(|path| path.is_file())
        .map(|path| path.to_string_lossy().to_string())
}

#[cfg(test)]
mod tests {
    use super::{cli_shim_from_prefix, global_cli_path_from_npm_binary, select_provider_resolution, ProviderPlatform};
    use std::path::PathBuf;

    #[test]
    fn computes_windows_cli_path_from_npm_binary() {
        // On non-Windows platforms, construct the path properly using forward slashes
        // internally, but verify the function produces the right structure
        let npm_dir = PathBuf::from("C:/Users/Theo/AppData/Roaming/npm");
        let npm_path = npm_dir.join("npm.cmd");
        let path = global_cli_path_from_npm_binary(
            npm_path,
            "codex",
            ProviderPlatform::Windows,
        )
        .unwrap();

        let expected = npm_dir.join("codex.cmd");
        assert_eq!(path, expected);
    }

    #[test]
    fn computes_unix_cli_path_from_npm_binary() {
        let path = global_cli_path_from_npm_binary(
            PathBuf::from("/opt/homebrew/bin/npm"),
            "codex",
            ProviderPlatform::Unix,
        )
        .unwrap();

        assert_eq!(path, PathBuf::from("/opt/homebrew/bin/codex"));
    }

    #[test]
    fn computes_cli_shim_from_prefix() {
        assert_eq!(
            cli_shim_from_prefix("/opt/homebrew", "claude", ProviderPlatform::Unix),
            PathBuf::from("/opt/homebrew/bin/claude")
        );
        // Use forward slashes for path construction on non-Windows platforms
        let npm_prefix = PathBuf::from("C:/Users/Theo/AppData/Roaming/npm");
        let result = cli_shim_from_prefix(&npm_prefix, "codex", ProviderPlatform::Windows);
        let expected = npm_prefix.join("codex.cmd");
        assert_eq!(result, expected);
    }

    #[test]
    fn prefers_valid_override_path() {
        let current_exe = std::env::current_exe().unwrap();
        let resolution = select_provider_resolution(
            Some(current_exe.clone()),
            Some("/tmp/other".into()),
            vec![PathBuf::from("/tmp/fallback")],
        );

        assert_eq!(
            resolution.path,
            Some(current_exe.to_string_lossy().to_string())
        );
        assert!(!resolution.clear_override);
    }

    #[test]
    fn clears_missing_override_and_uses_fallback() {
        let current_exe = std::env::current_exe().unwrap();
        let resolution = select_provider_resolution(
            Some(PathBuf::from("/definitely/missing/provider")),
            None,
            vec![current_exe.clone()],
        );

        assert_eq!(
            resolution.path,
            Some(current_exe.to_string_lossy().to_string())
        );
        assert!(resolution.clear_override);
    }
}
