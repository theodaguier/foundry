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
use std::path::{Path, PathBuf};
use types::{BundleMapping, DependencySpec, InstallDir, InstallOperation};

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
        return InstallDir {
            format: format.clone(),
            path: override_path,
            needs_elevation: false,
        };
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

pub fn install_plugin_bundle(src: &Path, dest: &Path) -> Result<(), String> {
    imp::install_plugin_bundle(src, dest)
}

pub fn install_plugin_bundles(operations: &[InstallOperation]) -> Result<(), String> {
    imp::install_plugin_bundles(operations)
}

pub fn post_install_refresh() -> Result<(), String> {
    imp::post_install_refresh()
}

pub fn code_sign(bundle_path: &Path) -> Result<(), String> {
    imp::code_sign(bundle_path)
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
