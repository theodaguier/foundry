use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use log::{info, warn};
use serde::{Deserialize, Serialize};

use crate::commands::dependencies::DependencyStatus;
use crate::platform;
use crate::services::{
    auth_service::{SupabaseAuth, SUPABASE_ANON_KEY, SUPABASE_URL},
    build_environment, dependency_checker, foundry_paths,
};

/// Global lock: only one install can run at a time.
static INSTALL_ACTIVE: AtomicBool = AtomicBool::new(false);

/// Create a Command that hides console windows on Windows and inherits the
/// current process environment.
///
/// Inheriting env is important for npm: npm scripts use `#!/usr/bin/env node`
/// and rely on `env` finding `node` in PATH. If the subprocess does not
/// inherit a PATH that includes the managed Node binary directory, the
/// shebang lookup fails at runtime even when npm itself is correctly invoked.
fn silent_command(cmd: &str) -> Command {
    #[allow(unused_mut)]
    let mut c = Command::new(cmd);
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x08000000); // CREATE_NO_WINDOW
    }
    // Inherit current process environment so that PATH (and other vars) are
    // available to subprocesses. This is especially important on macOS where
    // the managed Node binary directory needs to be in PATH for npm's shebang.
    c.envs(std::env::vars());
    c
}

#[cfg(target_os = "macos")]
const CMAKE_DOWNLOAD_URL: &str = "https://github.com/Kitware/CMake/releases/download/v{version}/cmake-{version}-macos-universal.tar.gz";

#[cfg(target_os = "macos")]
const NODE_DOWNLOAD_URL: &str =
    "https://nodejs.org/dist/v{version}/node-v{version}-darwin-{arch}.tar.gz";

#[cfg(target_os = "macos")]
const CODEX_DOWNLOAD_URL: &str =
    "https://github.com/openai/codex/releases/download/{version}/codex-{arch}-apple-darwin.tar.gz";

#[cfg(target_os = "macos")]
fn macos_node_arch() -> &'static str {
    if std::env::consts::ARCH == "aarch64" {
        "arm64"
    } else {
        "x64"
    }
}

#[cfg(target_os = "macos")]
fn download_file_sync(url: &str, dest: &Path) -> Result<(), String> {
    let runtime = tokio::runtime::Handle::current();
    let url = url.to_string();
    let dest = dest.to_path_buf();
    runtime.block_on(async {
        let response = reqwest::get(&url)
            .await
            .map_err(|e| format!("Download failed: {}", e))?;
        if !response.status().is_success() {
            return Err(format!(
                "Download returned status {} for {}",
                response.status(),
                url
            ));
        }
        let bytes = response
            .bytes()
            .await
            .map_err(|e| format!("Download failed: {}", e))?;
        std::fs::write(&dest, &bytes)
            .map_err(|e| format!("Failed to write {}: {}", dest.display(), e))?;
        Ok(())
    })
}

#[cfg(target_os = "macos")]
fn extract_tarball(archive_path: &Path, extract_dir: &Path) -> Result<(), String> {
    let output = Command::new("tar")
        .args([
            "-xzf",
            &archive_path.to_string_lossy(),
            "-C",
            &extract_dir.to_string_lossy(),
        ])
        .output()
        .map_err(|e| format!("Failed to run tar: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Extraction failed: {}", stderr.trim()));
    }

    Ok(())
}

#[cfg(target_os = "macos")]
fn install_managed_cmake() -> Result<PathBuf, String> {
    let cmake_binary = foundry_paths::managed_cmake_binary();
    if cmake_binary.is_file() {
        info!("Managed CMake already installed at {}", cmake_binary.display());
        return Ok(cmake_binary);
    }

    let version = foundry_paths::MANAGED_CMAKE_VERSION;
    let url = CMAKE_DOWNLOAD_URL.replace("{version}", version);
    let cmake_dir = foundry_paths::managed_cmake_dir();
    let temp_root = foundry_paths::application_support_dir().join("tmp");
    std::fs::create_dir_all(&cmake_dir).map_err(|e| format!("Failed to create CMake dir: {}", e))?;
    std::fs::create_dir_all(&temp_root).map_err(|e| format!("Failed to create temp dir: {}", e))?;

    let archive_path = temp_root.join(format!("cmake-{}.tar.gz", version));
    info!("Downloading CMake {} from {}", version, url);
    download_file_sync(&url, &archive_path)?;
    info!("Extracting CMake {}...", version);
    extract_tarball(&archive_path, &cmake_dir)?;
    let _ = std::fs::remove_file(&archive_path);

    if cmake_binary.is_file() {
        info!("Managed CMake installed at {}", cmake_binary.display());
        Ok(cmake_binary)
    } else {
        Err(format!(
            "CMake archive extracted but binary not found at {}",
            cmake_binary.display()
        ))
    }
}

#[cfg(target_os = "macos")]
fn install_managed_node() -> Result<PathBuf, String> {
    let npm_binary = foundry_paths::managed_npm_binary();
    if npm_binary.is_file() {
        info!("Managed Node.js already installed at {}", npm_binary.display());
        return Ok(npm_binary);
    }

    let version = foundry_paths::MANAGED_NODE_VERSION;
    let arch = macos_node_arch();
    let url = NODE_DOWNLOAD_URL
        .replace("{version}", version)
        .replace("{arch}", arch);
    let node_dir = foundry_paths::managed_node_dir();
    let temp_root = foundry_paths::application_support_dir().join("tmp");
    std::fs::create_dir_all(&node_dir).map_err(|e| format!("Failed to create Node dir: {}", e))?;
    std::fs::create_dir_all(&temp_root).map_err(|e| format!("Failed to create temp dir: {}", e))?;

    let archive_name = format!("node-v{}-darwin-{}.tar.gz", version, arch);
    let archive_path = temp_root.join(&archive_name);
    info!("Downloading Node.js {} from {}", version, url);
    download_file_sync(&url, &archive_path)?;
    info!("Extracting Node.js {}...", version);
    extract_tarball(&archive_path, &node_dir)?;
    let _ = std::fs::remove_file(&archive_path);

    let node_binary = foundry_paths::managed_node_binary();
    if node_binary.is_file() {
        info!(
            "Managed Node.js installed at {}",
            node_binary.display()
        );
        Ok(npm_binary)
    } else {
        Err(format!(
            "Node.js archive extracted but binary not found at {}",
            node_binary.display()
        ))
    }
}

#[cfg(target_os = "macos")]
fn install_managed_codex() -> Result<PathBuf, String> {
    let codex_binary = foundry_paths::managed_codex_binary();
    if codex_binary.is_file() {
        info!(
            "Managed Codex already installed at {}",
            codex_binary.display()
        );
        return Ok(codex_binary);
    }

    let version = foundry_paths::MANAGED_CODEX_VERSION;
    let arch = if std::env::consts::ARCH == "aarch64" {
        "aarch64"
    } else {
        "x86_64"
    };
    let url = CODEX_DOWNLOAD_URL
        .replace("{version}", version)
        .replace("{arch}", arch);

    let codex_dir = foundry_paths::managed_codex_dir();
    let temp_root = foundry_paths::application_support_dir().join("tmp");
    let archive_path = temp_root.join(format!(
        "codex-{}-{}.tar.gz",
        version.replace("/", "-"),
        uuid::Uuid::new_v4().simple()
    ));

    std::fs::create_dir_all(&codex_dir)
        .map_err(|e| format!("Failed to create Codex dir: {}", e))?;
    std::fs::create_dir_all(&temp_root)
        .map_err(|e| format!("Failed to create temp dir: {}", e))?;

    info!("Downloading Codex {} from {}", version, url);
    download_file_sync(&url, &archive_path)?;
    info!("Extracting Codex {}...", version);
    // The tarball extracts into a subdirectory: codex-{arch}-apple-darwin/
    // We extract to temp_root so the subdirectory lands there.
    extract_tarball(&archive_path, &temp_root)?;
    let _ = std::fs::remove_file(&archive_path);

    // Find the extracted subdirectory inside temp_root
    let extracted_subdir = temp_root.join(format!("codex-{}-apple-darwin", arch));
    if !extracted_subdir.exists() {
        return Err(format!(
            "Codex archive extracted but directory not found at {}",
            extracted_subdir.display()
        ));
    }

    if codex_dir.exists() {
        std::fs::remove_dir_all(&codex_dir)
            .map_err(|e| format!("Failed to clean Codex dir: {}", e))?;
    }
    std::fs::rename(&extracted_subdir, &codex_dir)
        .map_err(|e| format!("Failed to move Codex dir: {}", e))?;

    if codex_binary.is_file() {
        info!(
            "Managed Codex installed at {}",
            codex_binary.display()
        );
        Ok(codex_binary)
    } else {
        Err(format!(
            "Codex archive extracted but binary not found at {}",
            codex_binary.display()
        ))
    }
}

#[cfg(not(target_os = "macos"))]
fn install_managed_codex() -> Result<PathBuf, String> {
    Err("Managed Codex install is only supported on macOS.".into())
}

/// Try to acquire the install lock. Returns true if acquired.
pub fn try_acquire_install_lock() -> bool {
    INSTALL_ACTIVE
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
}

/// Release the install lock.
pub fn release_install_lock() {
    INSTALL_ACTIVE.store(false, Ordering::SeqCst);
}

fn push_reset_item(
    items: &mut Vec<DependencyResetItem>,
    name: &str,
    status: DependencyResetStatus,
    detail: impl Into<String>,
) {
    items.push(DependencyResetItem {
        name: name.to_string(),
        status,
        detail: detail.into(),
    });
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct OnboardingState {
    pub completed: bool,
    pub completed_at: Option<String>,
}

/// Aggregated local machine readiness state.
/// This is the single source of truth for whether the app should show
/// the onboarding screen — computed entirely from local machine state,
/// not from a remote Supabase flag.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetupState {
    /// True when the machine is fully set up and a provider is authenticated.
    pub ready: bool,
    /// True when the build toolchain and JUCE are ready.
    pub build_environment_ready: bool,
    /// List of provider summaries (Claude + Codex) with their install/auth status.
    pub providers: Vec<ProviderSummary>,
    /// True when at least one provider is installed and authenticated.
    pub has_authenticated_provider: bool,
    /// Human-readable summary of what's missing, if anything.
    pub blocked_reason: Option<String>,
    /// When true, the onboarding has been completed at least once on this account
    /// (fetched from Supabase). This is informational only — it does NOT gate
    /// the app; `ready` does.
    pub remote_completed_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ProviderSetupStatus {
    InstalledAndAuthenticated,
    InstalledNeedsAuth,
    NotInstalled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSummary {
    pub id: String,
    pub name: String,
    pub status: ProviderSetupStatus,
    pub version: Option<String>,
    pub auth_url: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DependencyInstallResult {
    pub success: bool,
    pub message: String,
    pub verification: DependencyInstallVerification,
    pub status: Option<DependencyStatus>,
    pub detected_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DependencyInstallVerification {
    Verified,
    AuthRequired,
    Pending,
    NotDetected,
}

#[derive(Debug, Clone)]
pub enum DependencyInstallDispatchResult {
    Final(DependencyInstallResult),
    Provider(ProviderInstallPreparation),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DependencyResetStatus {
    Removed,
    Skipped,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DependencyResetItem {
    pub name: String,
    pub status: DependencyResetStatus,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DependencyResetResult {
    pub items: Vec<DependencyResetItem>,
    pub summary: String,
}

#[derive(Debug, Clone)]
pub struct ProviderInstallPreparation {
    pub provider: ProviderCli,
    pub installer: &'static str,
    pub npm_path: Option<String>,
    pub expected_path: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderCli {
    Claude,
    Codex,
}

impl ProviderCli {
    pub fn command(self) -> &'static str {
        match self {
            ProviderCli::Claude => "claude",
            ProviderCli::Codex => "codex",
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            ProviderCli::Claude => "Claude Code",
            ProviderCli::Codex => "Codex",
        }
    }

    pub fn dependency_name(self) -> &'static str {
        match self {
            ProviderCli::Claude => "Claude Code CLI",
            ProviderCli::Codex => "Codex CLI",
        }
    }
}

impl DependencyInstallResult {
    pub fn verified(message: impl Into<String>) -> Self {
        Self {
            success: true,
            message: message.into(),
            verification: DependencyInstallVerification::Verified,
            status: None,
            detected_path: None,
        }
    }

    #[allow(dead_code)]
    pub fn pending(message: impl Into<String>) -> Self {
        Self {
            success: true,
            message: message.into(),
            verification: DependencyInstallVerification::Pending,
            status: None,
            detected_path: None,
        }
    }

    pub fn failed(message: impl Into<String>) -> Self {
        Self {
            success: false,
            message: message.into(),
            verification: DependencyInstallVerification::NotDetected,
            status: None,
            detected_path: None,
        }
    }
}

fn resolve_provider_path(provider: ProviderCli) -> Option<String> {
    match provider {
        ProviderCli::Claude => platform::resolve_claude_path(),
        ProviderCli::Codex => platform::resolve_codex_path(),
    }
}

fn user_local_cli_path(path: &str, cli_name: &str) -> bool {
    let cli_path = Path::new(path);
    let Some(file_name) = cli_path.file_name().and_then(|value| value.to_str()) else {
        return false;
    };

    #[cfg(target_os = "windows")]
    let matches_name = file_name.eq_ignore_ascii_case(&format!("{}.cmd", cli_name));
    #[cfg(not(target_os = "windows"))]
    let matches_name = file_name == cli_name;

    if !matches_name {
        return false;
    }

    let Some(home) = dirs::home_dir() else {
        return false;
    };

    [
        home.join(".local").join("bin"),
        home.join(".npm-global").join("bin"),
    ]
    .iter()
    .any(|dir| cli_path.starts_with(dir))
}

fn npm_global_modules_dir(npm_path: &str) -> Result<PathBuf, String> {
    let output = silent_command(npm_path)
        .args(["root", "-g"])
        .output()
        .map_err(|e| format!("Failed to inspect npm global modules: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("npm root -g failed: {}", stderr.trim()));
    }

    let root = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if root.is_empty() {
        return Err("npm root -g returned an empty path.".into());
    }

    Ok(PathBuf::from(root))
}

fn uninstall_global_npm_package(npm_path: &str, package_name: &str) -> Result<bool, String> {
    let package_dir = npm_global_modules_dir(npm_path)?.join(package_name);
    if !package_dir.exists() {
        return Ok(false);
    }

    let output = silent_command(npm_path)
        .args(["uninstall", "-g", package_name])
        .output()
        .map_err(|e| format!("Failed to uninstall {}: {}", package_name, e))?;

    if output.status.success() {
        Ok(true)
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!(
            "npm uninstall -g {} failed: {}",
            package_name,
            stderr.trim()
        ))
    }
}

fn uninstall_provider_cli(
    provider: ProviderCli,
    package_name: &str,
    items: &mut Vec<DependencyResetItem>,
) {
    let dependency_name = provider.dependency_name();
    let path_before = resolve_provider_path(provider);
    let mut notes = Vec::new();
    let mut removed_any = false;
    let mut errors = Vec::new();

    match resolve_npm_path() {
        Some(npm_path) => match uninstall_global_npm_package(&npm_path, package_name) {
            Ok(true) => {
                removed_any = true;
                notes.push(format!("Removed npm package {}.", package_name));
            }
            Ok(false) => {}
            Err(error) => errors.push(error),
        },
        None => notes.push("npm was not available to remove global packages.".into()),
    }

    if let Err(error) = foundry_paths::clear_provider_path_override(provider.command()) {
        errors.push(format!(
            "Failed to clear {} path override: {}",
            provider.command(),
            error
        ));
    }

    platform::invalidate_shell_cache();

    if let Some(path) = resolve_provider_path(provider) {
        if user_local_cli_path(&path, provider.command()) {
            match std::fs::remove_file(&path) {
                Ok(()) => {
                    removed_any = true;
                    notes.push(format!("Removed local CLI shim at {}.", path));
                    platform::invalidate_shell_cache();
                }
                Err(error) => errors.push(format!("Failed to remove {}: {}", path, error)),
            }
        }
    }

    platform::invalidate_shell_cache();
    let path_after = resolve_provider_path(provider);

    if let Some(path) = path_after {
        if errors.is_empty() {
            let detail = if removed_any {
                format!(
                    "{} still resolves at {}. Foundry removed managed installs but left any external install intact.",
                    dependency_name, path
                )
            } else {
                format!(
                    "{} is still installed at {}. No managed install was removed.",
                    dependency_name, path
                )
            };
            push_reset_item(
                items,
                dependency_name,
                DependencyResetStatus::Skipped,
                detail,
            );
        } else {
            push_reset_item(
                items,
                dependency_name,
                DependencyResetStatus::Failed,
                errors.join(" "),
            );
        }
        return;
    }

    if !errors.is_empty() {
        push_reset_item(
            items,
            dependency_name,
            DependencyResetStatus::Failed,
            errors.join(" "),
        );
    } else if removed_any {
        if notes.is_empty() {
            notes.push(format!("Removed {}.", dependency_name));
        }
        push_reset_item(
            items,
            dependency_name,
            DependencyResetStatus::Removed,
            notes.join(" "),
        );
    } else if path_before.is_some() {
        push_reset_item(
            items,
            dependency_name,
            DependencyResetStatus::Removed,
            format!("{} is no longer detected.", dependency_name),
        );
    } else {
        push_reset_item(
            items,
            dependency_name,
            DependencyResetStatus::Skipped,
            format!("{} was not installed.", dependency_name),
        );
    }
}

#[cfg(target_os = "windows")]
fn uninstall_cmake(items: &mut Vec<DependencyResetItem>) {
    let cmake_path = platform::resolve_command("cmake");
    let detail = if cmake_path == "cmake" {
        "CMake is not reset on Windows by this debug action.".to_string()
    } else {
        format!(
            "CMake is installed at {}. Windows debug reset leaves this install intact.",
            cmake_path
        )
    };

    push_reset_item(items, "CMake", DependencyResetStatus::Skipped, detail);
}

#[cfg(not(target_os = "windows"))]
fn uninstall_cmake(items: &mut Vec<DependencyResetItem>) {
    let cmake_path = platform::resolve_command("cmake");
    let Some(brew_path) = resolve_brew_path() else {
        let detail = if cmake_path == "cmake" {
            "Homebrew is not available and CMake is not currently detected.".to_string()
        } else {
            format!(
                "CMake is installed at {} but not via a removable Homebrew setup.",
                cmake_path
            )
        };
        push_reset_item(items, "CMake", DependencyResetStatus::Skipped, detail);
        return;
    };

    let list_output = silent_command(&brew_path)
        .args(["list", "--versions", "cmake"])
        .output();

    let installed_via_brew = matches!(list_output, Ok(output) if output.status.success() && !String::from_utf8_lossy(&output.stdout).trim().is_empty());

    if !installed_via_brew {
        let detail = if cmake_path == "cmake" {
            "CMake is not installed via Homebrew.".to_string()
        } else {
            format!(
                "CMake is installed at {} but not via Homebrew, so it was left intact.",
                cmake_path
            )
        };
        push_reset_item(items, "CMake", DependencyResetStatus::Skipped, detail);
        return;
    }

    let output = silent_command(&brew_path)
        .args(["uninstall", "cmake"])
        .output();

    match output {
        Ok(result) if result.status.success() => push_reset_item(
            items,
            "CMake",
            DependencyResetStatus::Removed,
            "Removed Homebrew CMake install.",
        ),
        Ok(result) => {
            let stderr = String::from_utf8_lossy(&result.stderr);
            push_reset_item(
                items,
                "CMake",
                DependencyResetStatus::Failed,
                format!("Homebrew uninstall failed: {}", stderr.trim()),
            );
        }
        Err(error) => push_reset_item(
            items,
            "CMake",
            DependencyResetStatus::Failed,
            format!("Failed to launch Homebrew uninstall: {}", error),
        ),
    }
}

pub fn reset_debug_dependencies() -> DependencyResetResult {
    let mut items = Vec::new();

    platform::invalidate_shell_cache();
    uninstall_provider_cli(ProviderCli::Claude, "@anthropic-ai/claude-code", &mut items);
    uninstall_provider_cli(ProviderCli::Codex, "@openai/codex", &mut items);

    // Also remove managed Codex directory if present (native install)
    #[cfg(target_os = "macos")]
    {
        use crate::services::foundry_paths;
        let codex_dir = foundry_paths::managed_codex_root_dir();
        if codex_dir.exists() {
            match std::fs::remove_dir_all(&codex_dir) {
                Ok(()) => push_reset_item(
                    &mut items,
                    "Codex CLI",
                    DependencyResetStatus::Removed,
                    "Removed managed Codex install.",
                ),
                Err(e) => push_reset_item(
                    &mut items,
                    "Codex CLI",
                    DependencyResetStatus::Failed,
                    format!("Failed to remove managed Codex: {}", e),
                ),
            }
        }
    }

    uninstall_cmake(&mut items);

    match build_environment::reset_managed_juce_state() {
        Ok(actions) if actions.is_empty() => push_reset_item(
            &mut items,
            "JUCE SDK",
            DependencyResetStatus::Skipped,
            "No managed JUCE install was present.",
        ),
        Ok(actions) => push_reset_item(
            &mut items,
            "JUCE SDK",
            DependencyResetStatus::Removed,
            actions.join(" "),
        ),
        Err(error) => push_reset_item(&mut items, "JUCE SDK", DependencyResetStatus::Failed, error),
    }

    push_reset_item(
        &mut items,
        "Xcode Command Line Tools",
        DependencyResetStatus::Skipped,
        "Left intact because it is a system toolchain install.",
    );

    platform::invalidate_shell_cache();

    let removed = items
        .iter()
        .filter(|item| item.status == DependencyResetStatus::Removed)
        .count();
    let failed = items
        .iter()
        .filter(|item| item.status == DependencyResetStatus::Failed)
        .count();

    let summary = if failed > 0 {
        format!(
            "Dependency reset finished with {} removal(s) and {} failure(s).",
            removed, failed
        )
    } else if removed > 0 {
        format!("Removed {} dependency install(s).", removed)
    } else {
        "No removable dependency installs were found.".to_string()
    };

    DependencyResetResult { items, summary }
}

/// Reset local app state files for development testing.
/// Does NOT touch PluginBuilds/ or Telemetry/.
/// Does NOT call Supabase logout — only clears local session.
pub fn reset_local_app_state(auth: &SupabaseAuth) -> DependencyResetResult {
    let mut items = Vec::new();

    // environment.json
    let env_path = foundry_paths::environment_config_path();
    if env_path.exists() {
        match std::fs::remove_file(&env_path) {
            Ok(()) => push_reset_item(
                &mut items,
                "Environment Config",
                DependencyResetStatus::Removed,
                "Removed environment.json.",
            ),
            Err(e) => push_reset_item(
                &mut items,
                "Environment Config",
                DependencyResetStatus::Failed,
                format!("Failed to remove environment.json: {}", e),
            ),
        }
    } else {
        push_reset_item(
            &mut items,
            "Environment Config",
            DependencyResetStatus::Skipped,
            "No environment.json to remove.",
        );
    }

    // auth_session.json (local clear only, no network call)
    let auth_path = foundry_paths::application_support_dir().join("auth_session.json");
    if auth_path.exists() {
        auth.clear_local_session();
        push_reset_item(
            &mut items,
            "Auth Session",
            DependencyResetStatus::Removed,
            "Cleared local auth session.",
        );
    } else {
        push_reset_item(
            &mut items,
            "Auth Session",
            DependencyResetStatus::Skipped,
            "No auth session file to clear.",
        );
    }

    // plugins.json
    let plugins_path = foundry_paths::plugins_json_path();
    if plugins_path.exists() {
        match std::fs::remove_file(&plugins_path) {
            Ok(()) => push_reset_item(
                &mut items,
                "Plugin Library",
                DependencyResetStatus::Removed,
                "Removed plugins.json.",
            ),
            Err(e) => push_reset_item(
                &mut items,
                "Plugin Library",
                DependencyResetStatus::Failed,
                format!("Failed to remove plugins.json: {}", e),
            ),
        }
    } else {
        push_reset_item(
            &mut items,
            "Plugin Library",
            DependencyResetStatus::Skipped,
            "No plugins.json to remove.",
        );
    }

    // models.json (user model overrides)
    let models_path = foundry_paths::models_user_override_path();
    if models_path.exists() {
        match std::fs::remove_file(&models_path) {
            Ok(()) => push_reset_item(
                &mut items,
                "Model Overrides",
                DependencyResetStatus::Removed,
                "Removed models.json.",
            ),
            Err(e) => push_reset_item(
                &mut items,
                "Model Overrides",
                DependencyResetStatus::Failed,
                format!("Failed to remove models.json: {}", e),
            ),
        }
    } else {
        push_reset_item(
            &mut items,
            "Model Overrides",
            DependencyResetStatus::Skipped,
            "No models.json to remove.",
        );
    }

    let removed = items
        .iter()
        .filter(|item| item.status == DependencyResetStatus::Removed)
        .count();
    let failed = items
        .iter()
        .filter(|item| item.status == DependencyResetStatus::Failed)
        .count();

    let summary = if failed > 0 {
        format!(
            "Local app state reset finished with {} removal(s) and {} failure(s).",
            removed, failed
        )
    } else if removed > 0 {
        format!("Removed {} local app state file(s).", removed)
    } else {
        "No local app state files to remove.".to_string()
    };

    DependencyResetResult { items, summary }
}

/// Read onboarding state from the user's Supabase profile.
pub async fn get_onboarding_state(auth: &SupabaseAuth) -> OnboardingState {
    let session = match auth.get_session() {
        Some(s) => s,
        None => return OnboardingState::default(),
    };

    let url = format!(
        "{}/rest/v1/profiles?id=eq.{}&select=onboarding_completed_at",
        *SUPABASE_URL, session.user_id
    );

    let client = reqwest::Client::new();
    let resp = client
        .get(&url)
        .header("apikey", SUPABASE_ANON_KEY.as_str())
        .header("Authorization", format!("Bearer {}", session.access_token))
        .send()
        .await;

    match resp {
        Ok(r) if r.status().is_success() => {
            let text = r.text().await.unwrap_or_default();
            let rows: Vec<serde_json::Value> = serde_json::from_str(&text).unwrap_or_default();
            if let Some(row) = rows.first() {
                let completed_at = row
                    .get("onboarding_completed_at")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                OnboardingState {
                    completed: completed_at.is_some(),
                    completed_at,
                }
            } else {
                OnboardingState::default()
            }
        }
        _ => OnboardingState::default(),
    }
}

/// Compute the aggregated local machine readiness state.
///
/// This function is the single entry point for determining whether the app
/// should show the onboarding screen. It combines:
/// - Build environment readiness (toolchain + JUCE)
/// - Provider install + auth status
///
/// Unlike `get_onboarding_state()`, this does NOT read from Supabase to
/// decide if onboarding should be shown. The remote `onboarding_completed_at`
/// field is fetched only for informational purposes (e.g. showing "Welcome back").
pub async fn get_setup_state(auth: &SupabaseAuth) -> SetupState {
    let build_env = build_environment::get_build_environment()
        .await
        .unwrap_or_else(|_| build_environment::BuildEnvironmentStatus {
            state: "blocked".into(),
            issues: vec![],
            juce_source: None,
            juce_path: None,
            juce_version: String::new(),
        });

    let deps = dependency_checker::check_all()
        .await
        .unwrap_or_default();

    let build_ready = build_env.state == "ready";

    let mut providers = Vec::new();
    let mut has_authenticated = false;

    for (id, name, dep_name) in [
        ("claude_code", "Claude Code", "Claude Code CLI"),
        ("codex", "Codex", "Codex CLI"),
    ] {
        let dep = deps.iter().find(|d| d.name == dep_name);
        let (status, version) = match dep {
            Some(d) if d.installed && !d.auth_required => {
                has_authenticated = true;
                (ProviderSetupStatus::InstalledAndAuthenticated, d.version.clone())
            }
            Some(d) if d.installed && d.auth_required => {
                (ProviderSetupStatus::InstalledNeedsAuth, d.version.clone())
            }
            _ => (ProviderSetupStatus::NotInstalled, None),
        };
        providers.push(ProviderSummary {
            id: id.to_string(),
            name: name.to_string(),
            status,
            version,
            auth_url: None,
        });
    }

    let ready = build_ready && has_authenticated;

    let blocked_reason = if !build_ready {
        // Surface the actual toolchain issues (Xcode CLT, CMake, etc.)
        // rather than a generic "not ready" message.
        Some(build_environment::format_blocked_message(&build_env))
    } else if !has_authenticated {
        let missing: Vec<_> = providers
            .iter()
            .filter(|p| p.status != ProviderSetupStatus::InstalledAndAuthenticated)
            .map(|p| p.name.as_str())
            .collect();
        if missing.len() == 2 {
            Some("Claude Code and Codex are not installed or not signed in.".to_string())
        } else if missing.len() == 1 {
            Some(format!("{} is not installed or not signed in.", missing[0]))
        } else {
            None
        }
    } else {
        None
    };

    let remote_completed_at = if let Some(session) = auth.get_session() {
        let url = format!(
            "{}/rest/v1/profiles?id=eq.{}&select=onboarding_completed_at",
            *SUPABASE_URL, session.user_id
        );
        let client = reqwest::Client::new();
        let resp = client
            .get(&url)
            .header("apikey", SUPABASE_ANON_KEY.as_str())
            .header("Authorization", format!("Bearer {}", session.access_token))
            .send()
            .await;
        let text = match resp {
            Ok(r) => r.text().await.unwrap_or_default(),
            Err(_) => String::new(),
        };
        let rows: Vec<serde_json::Value> = serde_json::from_str(&text).unwrap_or_default();
        rows.first()
            .and_then(|row| row.get("onboarding_completed_at"))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    } else {
        None
    };

    SetupState {
        ready,
        build_environment_ready: build_ready,
        providers,
        has_authenticated_provider: has_authenticated,
        blocked_reason,
        remote_completed_at,
    }
}

/// Mark onboarding as completed in the user's Supabase profile.
pub async fn complete_onboarding(auth: &SupabaseAuth) -> Result<OnboardingState, String> {
    let session = auth
        .get_session()
        .ok_or_else(|| "Not authenticated".to_string())?;

    let now = chrono::Utc::now().to_rfc3339();
    let url = format!(
        "{}/rest/v1/profiles?id=eq.{}",
        *SUPABASE_URL, session.user_id
    );

    let client = reqwest::Client::new();
    let resp = client
        .patch(&url)
        .header("apikey", SUPABASE_ANON_KEY.as_str())
        .header("Authorization", format!("Bearer {}", session.access_token))
        .header("Content-Type", "application/json")
        .header("Prefer", "return=minimal")
        .json(&serde_json::json!({
            "onboarding_completed_at": now,
        }))
        .send()
        .await
        .map_err(|e| format!("Request failed: {}", e))?;

    if !resp.status().is_success() {
        let text = resp.text().await.unwrap_or_default();
        return Err(format!("Failed to update profile: {}", text));
    }

    Ok(OnboardingState {
        completed: true,
        completed_at: Some(now),
    })
}

/// Install Xcode Command Line Tools. Launches the macOS installer GUI.
pub fn install_xcode_clt() -> DependencyInstallResult {
    #[cfg(not(target_os = "macos"))]
    {
        DependencyInstallResult::failed("Xcode Command Line Tools are only available on macOS.")
    }

    #[cfg(target_os = "macos")]
    {
        let output = silent_command("xcode-select").args(["--install"]).output();

        match output {
            Ok(o) => {
                let stderr = String::from_utf8_lossy(&o.stderr);
                if stderr.contains("already installed") {
                    DependencyInstallResult::verified(
                        "Xcode Command Line Tools are already installed.",
                    )
                } else {
                    DependencyInstallResult::pending(
                        "Xcode Command Line Tools installer launched. Please complete the installation in the popup window.",
                    )
                }
            }
            Err(e) => DependencyInstallResult::failed(format!("Failed to launch installer: {}", e)),
        }
    }
}

#[cfg(not(target_os = "windows"))]
fn resolve_brew_path() -> Option<String> {
    let resolved = platform::resolve_command("brew");
    if resolved != "brew" {
        return Some(resolved);
    }
    for path in &["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
        if std::path::Path::new(path).is_file() {
            return Some(path.to_string());
        }
    }
    None
}

fn resolve_npm_path() -> Option<String> {
    #[cfg(target_os = "windows")]
    {
        // On Windows, always prefer npm.cmd — the bare "npm" shim is not a
        // valid Win32 executable and will fail with "%1 is not a valid Win32
        // application".
        let resolved = platform::resolve_command("npm.cmd");
        if resolved != "npm.cmd" {
            return Some(resolved);
        }

        // Check well-known install locations
        let program_files = std::env::var("ProgramFiles").unwrap_or_default();
        let appdata = std::env::var("APPDATA").unwrap_or_default();
        for candidate in &[
            std::path::PathBuf::from(&program_files)
                .join("nodejs")
                .join("npm.cmd"),
            std::path::PathBuf::from(&appdata)
                .join("npm")
                .join("npm.cmd"),
        ] {
            if candidate.is_file() {
                return Some(candidate.to_string_lossy().to_string());
            }
        }

        None
    }

    #[cfg(not(target_os = "windows"))]
    {
        let resolved = platform::resolve_command("npm");
        if resolved != "npm" {
            return Some(resolved);
        }
        #[cfg(target_os = "macos")]
        for path in &["/opt/homebrew/bin/npm", "/usr/local/bin/npm"] {
            if std::path::Path::new(path).is_file() {
                return Some(path.to_string());
            }
        }
        None
    }
}

#[cfg(target_os = "windows")]
fn resolve_winget_path() -> Option<String> {
    let resolved = platform::resolve_command("winget");
    if resolved != "winget" {
        return Some(resolved);
    }

    let local_app_data = std::env::var("LOCALAPPDATA").ok()?;
    let fallback = std::path::Path::new(&local_app_data)
        .join("Microsoft")
        .join("WindowsApps")
        .join("winget.exe");

    fallback
        .is_file()
        .then(|| fallback.to_string_lossy().to_string())
}

#[cfg(target_os = "windows")]
/// Extract a short, user-friendly error from raw winget output.
/// Strips progress spinners, license boilerplate, and blank lines.
fn sanitize_winget_output(raw: &str) -> String {
    let meaningful: Vec<String> = raw
        .lines()
        .map(|l| {
            // Strip spinner sequences: runs of - \ | / and spaces
            let cleaned: String = l
                .trim()
                .replace("- \\", "")
                .replace("| /", "")
                .replace("\\ |", "")
                .replace("/ -", "")
                .trim()
                .to_string();
            // Also strip any remaining runs of just spinner chars at end
            cleaned
                .trim_end_matches(['-', '\\', '|', '/', ' '])
                .trim()
                .to_string()
        })
        .filter(|l| {
            !l.is_empty()
                && l.len() > 2 // Skip lines that are just residual chars
                && !l.chars().all(|c| matches!(c, '-' | '\\' | '|' | '/' | ' ' | '.'))
                && !l.contains("Successfully verified installer hash")
                && !l.contains("Starting package install")
                && !l.contains("This application is licensed")
                && !l.contains("Microsoft is not responsible")
                && !l.contains("does it grant any licenses")
                && !l.contains("third-party packages")
                && !l.contains("install...")
                && !l.starts_with("Version ")
                && !l.starts_with('[') // [Microsoft.VisualStudio...] header
        })
        .collect();

    if meaningful.is_empty() {
        return "Installation did not complete. Try again or install manually.".to_string();
    }

    // Take the last meaningful line (usually the actual error)
    let last = &meaningful[meaningful.len() - 1];
    if last.len() > 120 {
        format!("{}…", &last[..120])
    } else {
        last.to_string()
    }
}

#[cfg(target_os = "windows")]
fn run_winget_install(
    package_id: &str,
    display_name: &str,
    extra_args: &[&str],
) -> DependencyInstallResult {
    let winget = match resolve_winget_path() {
        Some(path) => path,
        None => {
            return DependencyInstallResult::failed(format!(
                "winget is not available. Install {} manually, then click Re-check.",
                display_name
            ));
        }
    };

    let mut args = vec![
        "install",
        "--id",
        package_id,
        "-e",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--silent",
    ];
    args.extend_from_slice(extra_args);

    let result = silent_command(&winget).args(&args).output();

    match result {
        Ok(output) if output.status.success() => {
            DependencyInstallResult::verified(format!("{} installed successfully.", display_name))
        }
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let stdout = String::from_utf8_lossy(&output.stdout);
            let combined = format!("{}\n{}", stdout, stderr);
            if combined.contains("No available upgrade found")
                || combined.contains("No installed package found matching input criteria")
                || combined.contains("already installed")
                || combined.contains("Found an existing package already installed")
                || combined.contains("No newer package versions are available")
            {
                DependencyInstallResult::verified(format!("{} is already installed.", display_name))
            } else {
                let clean = sanitize_winget_output(&combined);
                DependencyInstallResult::failed(format!(
                    "Could not install {}. {}",
                    display_name, clean
                ))
            }
        }
        Err(error) => DependencyInstallResult::failed(format!(
            "Could not install {}: {}",
            display_name, error
        )),
    }
}

#[cfg(not(target_os = "windows"))]
fn install_homebrew() -> Result<(), String> {
    #[cfg(not(target_os = "macos"))]
    {
        Err("Homebrew installation is only supported on macOS.".into())
    }

    #[cfg(target_os = "macos")]
    {
        let result = silent_command("/bin/bash")
        .args([
            "-c",
            "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
        ])
        .output()
        .map_err(|e| format!("Failed to run Homebrew installer: {}", e))?;

        if !result.status.success() {
            let stderr = String::from_utf8_lossy(&result.stderr);
            return Err(format!("Homebrew installation failed: {}", stderr.trim()));
        }
        Ok(())
    }
}

/// Install Git for Windows via winget. Required by Claude Code on Windows.
pub fn install_git() -> DependencyInstallResult {
    let resolved = platform::resolve_command("git");
    if resolved != "git" {
        return DependencyInstallResult::verified("Git is already installed.");
    }

    #[cfg(target_os = "windows")]
    {
        run_winget_install("Git.Git", "Git for Windows", &[])
    }

    #[cfg(not(target_os = "windows"))]
    {
        DependencyInstallResult::failed("Git installation is only automated on Windows.")
    }
}

/// Install CMake via Homebrew (installs Homebrew first if needed).
pub fn install_cmake() -> DependencyInstallResult {
    let resolved = platform::resolve_command("cmake");
    if resolved != "cmake" {
        return DependencyInstallResult::verified("CMake is already installed.");
    }

    #[cfg(target_os = "windows")]
    {
        run_winget_install("Kitware.CMake", "CMake", &[])
    }

    #[cfg(not(target_os = "windows"))]
    {
        #[cfg(target_os = "macos")]
        if install_managed_cmake().is_ok() {
            return DependencyInstallResult::verified(format!(
                "CMake {} installed successfully.",
                foundry_paths::MANAGED_CMAKE_VERSION
            ));
        }

        let brew = match resolve_brew_path() {
            Some(path) => path,
            None => {
                if let Err(e) = install_homebrew() {
                    return DependencyInstallResult::failed(e);
                }
                match resolve_brew_path() {
                    Some(path) => path,
                    None => {
                        return DependencyInstallResult::failed(
                            "Homebrew installed but could not be found on PATH.",
                        )
                    }
                }
            }
        };

        let result = silent_command(&brew).args(["install", "cmake"]).output();

        match result {
            Ok(o) if o.status.success() => {
                DependencyInstallResult::verified("CMake installed successfully via Homebrew.")
            }
            Ok(o) => {
                let stderr = String::from_utf8_lossy(&o.stderr);
                let stdout = String::from_utf8_lossy(&o.stdout);
                if stderr.contains("already installed") || stdout.contains("already installed") {
                    DependencyInstallResult::verified("CMake is already installed via Homebrew.")
                } else {
                    DependencyInstallResult::failed(format!(
                        "Failed to install CMake: {}",
                        stderr.trim()
                    ))
                }
            }
            Err(e) => DependencyInstallResult::failed(format!("Failed to run brew: {}", e)),
        }
    }
}

/// Check if VS Build Tools with C++ workload are installed via vswhere.
#[cfg(target_os = "windows")]
fn vs_build_tools_installed() -> bool {
    platform::check_dependency(&platform::types::DependencySpec {
        name: "C++ Build Tools",
        check_command: "__vs_build_tools__",
        check_args: &[],
    })
    .is_some()
}

#[cfg(target_os = "windows")]
fn download_vs_build_tools_bootstrapper(bootstrapper_path: &std::path::Path) -> Result<(), String> {
    let bootstrapper = bootstrapper_path.to_string_lossy().to_string();

    let curl_download = silent_command("curl.exe")
        .args([
            "-fsSL",
            "-o",
            &bootstrapper,
            "https://aka.ms/vs/17/release/vs_BuildTools.exe",
        ])
        .output();

    if matches!(curl_download, Ok(output) if output.status.success() && bootstrapper_path.is_file())
    {
        return Ok(());
    }

    let ps_script = format!(
        "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_BuildTools.exe' -OutFile '{}'",
        bootstrapper.replace('\'', "''"),
    );

    let powershell_download = silent_command("powershell")
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            &ps_script,
        ])
        .output();

    match powershell_download {
        Ok(output) if output.status.success() && bootstrapper_path.is_file() => Ok(()),
        _ => Err(
            "Could not download the Build Tools installer. Check your internet connection and try again."
                .into(),
        ),
    }
}

#[cfg(target_os = "windows")]
fn wait_for_vs_build_tools_registration(timeout_secs: u64) -> bool {
    let start = std::time::Instant::now();
    let timeout = std::time::Duration::from_secs(timeout_secs);

    while start.elapsed() < timeout {
        if vs_build_tools_installed() {
            return true;
        }
        std::thread::sleep(std::time::Duration::from_secs(2));
    }

    vs_build_tools_installed()
}

#[cfg(target_os = "windows")]
fn format_vs_build_tools_failure(exit_code: Option<i32>) -> String {
    match exit_code {
        Some(1602) => {
            "Windows Build Tools installation was canceled. Approve the administrator prompt and try again."
                .into()
        }
        Some(1618) => {
            "Another Windows installation is already running. Let it finish, then retry.".into()
        }
        Some(code) => match code as u32 {
            0x80070005 => {
                "Windows denied access while installing Build Tools. Approve the administrator prompt and try again."
                    .into()
            }
            0x80070070 => {
                "Not enough free disk space for Windows Build Tools. Free space on your system drive (usually C:) and try again."
                    .into()
            }
            0x80072EE7 | 0x80072EFD => {
                "Foundry could not reach Microsoft's download or install servers. Check your internet connection and try again."
                    .into()
            }
            hresult => format!(
                "Microsoft Build Tools installer exited with code {} (0x{:08X}). Try again. If it keeps failing, restart Windows and retry the onboarding step.",
                code,
                hresult
            ),
        },
        None => "Microsoft Build Tools installer did not return an exit code. Try again.".into(),
    }
}

/// Install Visual Studio Build Tools on Windows.
///
/// Uses the official Microsoft bootstrapper (vs_BuildTools.exe) in passive
/// mode so Foundry can wait for completion, handle exit codes, and verify
/// that the C++ workload is actually available before continuing onboarding.
pub fn install_cpp_build_tools() -> DependencyInstallResult {
    #[cfg(not(target_os = "windows"))]
    {
        DependencyInstallResult::failed(
            "C++ Build Tools installation is only available on Windows.",
        )
    }

    #[cfg(target_os = "windows")]
    {
        // Pre-check with vswhere
        if vs_build_tools_installed() {
            return DependencyInstallResult::verified("Windows Build Tools are already installed.");
        }

        // Download the official VS Build Tools bootstrapper
        let temp_dir = std::env::temp_dir();
        let bootstrapper_path = temp_dir.join("vs_BuildTools.exe");

        if let Err(message) = download_vs_build_tools_bootstrapper(&bootstrapper_path) {
            return DependencyInstallResult::failed(message);
        }

        let run_install = silent_command(&bootstrapper_path.to_string_lossy())
            .args([
                "--add",
                "Microsoft.VisualStudio.Workload.VCTools",
                "--includeRecommended",
                "--passive",
                "--wait",
                "--norestart",
            ])
            .output();

        let _ = std::fs::remove_file(&bootstrapper_path);

        match run_install {
            Ok(output) => {
                let exit_code = output.status.code();
                let install_succeeded = matches!(exit_code, Some(0) | Some(1641) | Some(3010));

                if !install_succeeded {
                    return DependencyInstallResult::failed(format_vs_build_tools_failure(
                        exit_code,
                    ));
                }

                if wait_for_vs_build_tools_registration(30) {
                    let restart_suffix = if matches!(exit_code, Some(1641) | Some(3010)) {
                        " Windows requested a restart, but the compiler is already available."
                    } else {
                        ""
                    };

                    return DependencyInstallResult::verified(format!(
                        "Windows Build Tools installed successfully.{}",
                        restart_suffix
                    ));
                }

                if matches!(exit_code, Some(1641) | Some(3010)) {
                    DependencyInstallResult::failed("Windows requested a restart to finish the Build Tools installation. Restart Windows, reopen Foundry, and click Re-check.")
                } else {
                    DependencyInstallResult::failed("Build Tools installation finished, but Foundry could not verify the C++ workload afterwards. Restart Foundry and click Re-check.")
                }
            }
            Err(e) => DependencyInstallResult::failed(format!(
                "Could not launch the Build Tools installer: {}",
                e
            )),
        }
    }
}

/// On Windows, try well-known npm install locations after a fresh Node.js install.
#[cfg(target_os = "windows")]
fn resolve_npm_from_known_paths() -> Option<String> {
    let program_files = std::env::var("ProgramFiles").unwrap_or_default();
    let appdata = std::env::var("APPDATA").unwrap_or_default();

    let candidates = [
        std::path::PathBuf::from(&program_files)
            .join("nodejs")
            .join("npm.cmd"),
        std::path::PathBuf::from(&appdata)
            .join("npm")
            .join("npm.cmd"),
    ];

    for path in &candidates {
        if path.is_file() {
            return Some(path.to_string_lossy().to_string());
        }
    }
    None
}

fn ensure_npm() -> Result<String, String> {
    if let Some(npm) = resolve_npm_path() {
        return Ok(npm);
    }

    #[cfg(target_os = "windows")]
    {
        let install_result = run_winget_install("OpenJS.NodeJS.LTS", "Node.js LTS", &[]);
        if !install_result.success {
            return Err(install_result.message);
        }

        // Invalidate shell cache so new PATH entries are visible
        platform::invalidate_shell_cache();

        // Brief wait for PATH to settle after Windows install
        std::thread::sleep(std::time::Duration::from_secs(2));

        // Try standard resolution first, then known install paths
        if let Some(npm) = resolve_npm_path() {
            return Ok(npm);
        }
        if let Some(npm) = resolve_npm_from_known_paths() {
            return Ok(npm);
        }

        Err(
            "Node.js was installed but npm is not yet available. Please restart Foundry and try again."
                .to_string(),
        )
    }

    #[cfg(not(target_os = "windows"))]
    {
        // --- macOS path ---
        #[cfg(target_os = "macos")]
        {
            // Strategy 1: Install a managed Node.js (downloaded tarball into app support).
            // This works without Homebrew and is fully self-contained.
            if let Ok(npm) = install_managed_node() {
                return Ok(npm.to_string_lossy().to_string());
            }
        }

        // Strategy 2: Use Homebrew to install Node.js.
        // On a fresh Mac, brew may not be available, so we install it first.
        let brew = match resolve_brew_path() {
            Some(path) => path,
            None => {
                #[cfg(target_os = "macos")]
                {
                    // Fix: On macOS without Homebrew, install it first using the
                    // existing install_homebrew() helper (same approach used by
                    // install_cmake()). Without this, ensure_npm() would fail
                    // silently on fresh Macs, causing "node: No such file or
                    // directory" errors when installing Codex CLI.
                    info!("Homebrew not found — installing it first");
                    if let Err(e) = install_homebrew() {
                        return Err(format!(
                            "Could not install Node.js: Homebrew is required but not available. \
                             Attempted to install Homebrew but failed: {}. \
                             Please install Node.js manually from https://nodejs.org",
                            e
                        ));
                    }
                    // After installing Homebrew, give the shell a moment to settle
                    // and try resolving again.
                    platform::invalidate_shell_cache();
                    std::thread::sleep(std::time::Duration::from_secs(2));
                    resolve_brew_path().ok_or_else(|| {
                        "Homebrew was installed but could not be found on PATH. \
                         Please restart Foundry and try again."
                            .to_string()
                    })?
                }
                #[cfg(not(target_os = "macos"))]
                {
                    return Err(
                        "npm is not installed. Please install Node.js from https://nodejs.org."
                            .to_string(),
                    );
                }
            }
        };

        let result = silent_command(&brew)
            .args(["install", "node"])
            .output()
            .map_err(|e| format!("Failed to install Node.js: {}", e))?;

        if !result.status.success() {
            let stderr = String::from_utf8_lossy(&result.stderr);
            if !stderr.contains("already installed") {
                return Err(format!("Failed to install Node.js: {}", stderr.trim()));
            }
        }

        // Invalidate cache after installing Node
        platform::invalidate_shell_cache();

        let npm = resolve_npm_path()
            .ok_or_else(|| "Node.js installed but npm could not be found on PATH.".to_string())?;

        // Fix: Verify that `node` itself is resolvable (not just npm). The Codex
        // CLI shebang references `node` directly, so if only npm is on PATH but
        // node is not, Codex will fail at runtime with "node: No such file or
        // directory".
        let resolved_node = platform::resolve_command("node");
        if resolved_node == "node" {
            // node is not resolvable even though npm is — try brew node path directly
            #[cfg(target_os = "macos")]
            for node_candidate in &[
                "/opt/homebrew/bin/node",
                "/usr/local/bin/node",
            ] {
                if std::path::Path::new(node_candidate).is_file() {
                    return Ok(npm);
                }
            }
            // Also check managed node binary
            #[cfg(target_os = "macos")]
            if foundry_paths::managed_node_binary().is_file() {
                return Ok(npm);
            }
            warn!(
                "npm is resolvable ({}) but `node` is not on PATH. \
                 Codex CLI requires Node.js to be on PATH.",
                npm
            );
        }

        Ok(npm)
    }
}

fn npm_global_prefix(npm_path: &str) -> Result<String, String> {
    let output = silent_command(npm_path)
        .args(["prefix", "-g"])
        .output()
        .map_err(|e| format!("Failed to inspect npm prefix: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("npm prefix -g failed: {}", stderr.trim()));
    }

    let prefix = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if prefix.is_empty() {
        return Err("npm prefix -g returned an empty path.".into());
    }

    Ok(prefix)
}

fn provider_cli_from_prefix(prefix: &str, cli_name: &str) -> PathBuf {
    #[cfg(target_os = "windows")]
    {
        PathBuf::from(prefix).join(format!("{}.cmd", cli_name))
    }

    #[cfg(not(target_os = "windows"))]
    {
        PathBuf::from(prefix).join("bin").join(cli_name)
    }
}

fn expected_cli_path_from_npm(npm_path: &str, cli_name: &str) -> Option<String> {
    if let Ok(prefix) = npm_global_prefix(npm_path) {
        let candidate = provider_cli_from_prefix(&prefix, cli_name);
        info!(
            "Provider install npm prefix resolved: cli={} npm={} prefix={} expected={}",
            cli_name,
            npm_path,
            prefix,
            candidate.display()
        );
        return Some(candidate.to_string_lossy().to_string());
    }

    platform::global_cli_path_from_npm(npm_path, cli_name)
        .map(|path| path.to_string_lossy().to_string())
}

fn verified_provider_result(
    provider: ProviderCli,
    status: DependencyStatus,
    detected_path: String,
) -> DependencyInstallResult {
    let verification = if status.auth_required {
        DependencyInstallVerification::AuthRequired
    } else {
        DependencyInstallVerification::Verified
    };
    let message = if status.auth_required {
        format!(
            "{} installed. Sign in to continue.",
            provider.display_name()
        )
    } else {
        format!("{} installed successfully.", provider.display_name())
    };

    DependencyInstallResult {
        success: true,
        message,
        verification,
        status: Some(status),
        detected_path: Some(detected_path),
    }
}

fn provider_not_detected_result(
    provider: ProviderCli,
    last_detected_path: Option<String>,
) -> DependencyInstallResult {
    DependencyInstallResult {
        success: false,
        message: format!(
            "{} installer completed, but Foundry could not verify the CLI afterwards. Please try again or install {} manually.",
            provider.display_name(),
            provider.display_name()
        ),
        verification: DependencyInstallVerification::NotDetected,
        status: None,
        detected_path: last_detected_path,
    }
}

pub async fn verify_provider_install(
    preparation: ProviderInstallPreparation,
) -> Result<DependencyInstallResult, String> {
    // Fix: Increased from 15s to 30s. On fresh Macs, npm install can take longer
    // because Homebrew/managed Node.js may need to be installed first, and the
    // shell environment cache needs extra cycles to pick up new PATH entries.
    const VERIFY_TIMEOUT: Duration = Duration::from_secs(30);
    const VERIFY_INTERVAL: Duration = Duration::from_secs(1);

    info!(
        "Verifying provider install: provider={} installer={} npm_path={:?} expected_path={:?}",
        preparation.provider.command(),
        preparation.installer,
        preparation.npm_path,
        preparation.expected_path
    );

    let started_at = Instant::now();
    let mut last_detected_path = None;

    loop {
        platform::invalidate_shell_cache();

        // --- Strategy 1: Check the expected_path from the preparation struct ---
        let expected_candidate = preparation
            .expected_path
            .as_deref()
            .filter(|path| Path::new(path).is_file())
            .map(ToOwned::to_owned);

        // --- Strategy 2: Resolve via platform (shell env, known paths, overrides) ---
        let platform_candidate = match preparation.provider {
            ProviderCli::Claude => platform::resolve_claude_path(),
            ProviderCli::Codex => platform::resolve_codex_path(),
        };

        // --- Strategy 3: Direct npm prefix check (Fix for ghost installations) ---
        // After npm install, the binary lands in the npm global prefix bin dir.
        // The shell cache may not reflect this immediately, so we check the
        // filesystem directly using the npm prefix from the preparation struct.
        let npm_prefix_candidate = preparation.npm_path.as_deref().and_then(|npm_path| {
            npm_global_prefix(npm_path).ok().map(|prefix| {
                provider_cli_from_prefix(&prefix, preparation.provider.command())
                    .to_string_lossy()
                    .to_string()
            })
        }).filter(|path| Path::new(path).is_file());

        let detected_path = expected_candidate
            .clone()
            .or_else(|| platform_candidate.clone())
            .or_else(|| npm_prefix_candidate.clone());

        if let Some(path) = detected_path.clone() {
            last_detected_path = Some(path.clone());
            info!(
                "Provider install candidate detected: provider={} path={} source={}",
                preparation.provider.command(),
                path,
                if expected_candidate.as_deref() == Some(&path) { "expected_path" }
                else if platform_candidate.as_deref() == Some(&path) { "platform" }
                else { "npm_prefix" }
            );

            if let Some(status) =
                dependency_checker::provider_status(preparation.provider, Some(&path))?
            {
                foundry_paths::set_provider_path_override(preparation.provider.command(), &path)?;
                platform::invalidate_shell_cache();

                info!(
                    "Provider install verified: provider={} path={} auth_required={}",
                    preparation.provider.command(),
                    path,
                    status.auth_required
                );

                return Ok(verified_provider_result(preparation.provider, status, path));
            }
        }

        if started_at.elapsed() >= VERIFY_TIMEOUT {
            warn!(
                "Provider install verification timed out after {:?}: provider={} installer={} expected_path={:?} npm_prefix_candidate={:?} last_detected_path={:?}",
                started_at.elapsed(),
                preparation.provider.command(),
                preparation.installer,
                preparation.expected_path,
                npm_prefix_candidate,
                last_detected_path
            );

            return Ok(provider_not_detected_result(
                preparation.provider,
                last_detected_path,
            ));
        }

        tokio::time::sleep(VERIFY_INTERVAL).await;
    }
}

#[cfg(test)]
mod tests {
    use super::{
        provider_not_detected_result, verified_provider_result, provider_cli_from_prefix,
        user_local_cli_path, DependencyInstallVerification, DependencyStatus,
        DependencyResetItem, DependencyResetResult, DependencyResetStatus, ProviderCli,
    };

    #[test]
    fn verification_timeout_returns_not_detected() {
        let result = provider_not_detected_result(
            ProviderCli::Codex,
            Some("/opt/homebrew/bin/codex".into()),
        );

        assert!(!result.success);
        assert_eq!(
            result.verification,
            DependencyInstallVerification::NotDetected
        );
        assert_eq!(
            result.detected_path.as_deref(),
            Some("/opt/homebrew/bin/codex")
        );
        assert!(result
            .message
            .contains("could not verify the CLI afterwards"));
    }

    #[test]
    fn reset_summary_counts_removed_and_failed_items() {
        let result = DependencyResetResult {
            items: vec![
                DependencyResetItem {
                    name: "Claude Code CLI".into(),
                    status: DependencyResetStatus::Removed,
                    detail: "Removed.".into(),
                },
                DependencyResetItem {
                    name: "JUCE SDK".into(),
                    status: DependencyResetStatus::Failed,
                    detail: "Could not remove.".into(),
                },
            ],
            summary: "Dependency reset finished with 1 removal(s) and 1 failure(s).".into(),
        };

        assert!(result.summary.contains("1 removal"));
        assert!(result.summary.contains("1 failure"));
    }

    #[test]
    fn only_user_local_bins_are_treated_as_directly_removable() {
        let home = dirs::home_dir().unwrap();
        #[cfg(target_os = "windows")]
        let local_path = home.join(".local/bin/claude.cmd");
        #[cfg(not(target_os = "windows"))]
        let local_path = home.join(".local/bin/claude");

        #[cfg(target_os = "windows")]
        let homebrew_path = std::path::PathBuf::from("C:/Program Files/claude.cmd");
        #[cfg(not(target_os = "windows"))]
        let homebrew_path = std::path::PathBuf::from("/opt/homebrew/bin/claude");

        assert!(user_local_cli_path(
            local_path.to_string_lossy().as_ref(),
            "claude"
        ));
        assert!(!user_local_cli_path(
            homebrew_path.to_string_lossy().as_ref(),
            "claude"
        ));
    }

    /// Test that provider_not_detected_result includes clear guidance about
    /// next steps (ghost-installation fix: the error message should mention
    /// manual install as a fallback).
    #[test]
    fn not_detected_result_message_includes_manual_install_guidance() {
        let result = provider_not_detected_result(
            ProviderCli::Claude,
            None,
        );
        assert!(!result.success);
        assert!(
            result.message.contains("Claude Code manually")
                || result.message.contains("manually"),
            "message should mention manual install fallback: {}",
            result.message
        );
        assert_eq!(result.verification, DependencyInstallVerification::NotDetected);
    }

    /// Test that verified_provider_result correctly sets auth_required state.
    #[test]
    fn verified_result_with_auth_required() {
        let status = DependencyStatus {
            name: "Claude Code CLI".to_string(),
            installed: true,
            auth_required: true,
            detail: Some("1.0.0".to_string()),
            version: Some("1.0.0".to_string()),
        };
        let result = verified_provider_result(ProviderCli::Claude, status, "/usr/local/bin/claude".to_string());
        assert!(result.success);
        assert_eq!(result.verification, DependencyInstallVerification::AuthRequired);
        assert!(result.message.contains("Sign in"));
    }

    /// Test that provider_cli_from_prefix constructs the correct path.
    #[test]
    fn provider_cli_from_prefix_creates_correct_unix_path() {
        let path = provider_cli_from_prefix("/usr/local", "claude");
        #[cfg(target_os = "windows")]
        assert_eq!(path, std::path::PathBuf::from("/usr/local/claude.cmd"));
        #[cfg(not(target_os = "windows"))]
        assert_eq!(path, std::path::PathBuf::from("/usr/local/bin/claude"));
    }
}

/// Install Claude Code using the native installer (no Node.js required).
/// Falls back to winget on Windows, brew on macOS, and npm as last resort.
pub fn install_claude_code() -> DependencyInstallDispatchResult {
    if let Some(existing_path) = platform::resolve_claude_path() {
        info!("Claude Code already resolvable at {}", existing_path);
        return DependencyInstallDispatchResult::Provider(ProviderInstallPreparation {
            provider: ProviderCli::Claude,
            installer: "existing",
            npm_path: None,
            expected_path: Some(existing_path),
        });
    }

    // Try native installer first (recommended by Anthropic, no dependencies)
    #[cfg(target_os = "windows")]
    {
        info!("Installing Claude Code via winget");
        let winget_result = run_winget_install("Anthropic.ClaudeCode", "Claude Code", &[]);
        if winget_result.success {
            return DependencyInstallDispatchResult::Provider(ProviderInstallPreparation {
                provider: ProviderCli::Claude,
                installer: "winget",
                npm_path: None,
                expected_path: None,
            });
        }

        info!("Installing Claude Code via PowerShell installer");
        let ps_result = silent_command("powershell")
            .args([
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                "irm https://claude.ai/install.ps1 | iex",
            ])
            .output();

        match ps_result {
            Ok(output) if output.status.success() => {
                return DependencyInstallDispatchResult::Provider(ProviderInstallPreparation {
                    provider: ProviderCli::Claude,
                    installer: "powershell",
                    npm_path: None,
                    expected_path: None,
                });
            }
            Ok(output) => {
                let stderr = String::from_utf8_lossy(&output.stderr);
                warn!("Claude PowerShell installer failed: {}", stderr.trim());
            }
            Err(error) => warn!("Claude PowerShell installer failed to launch: {}", error),
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        info!("Installing Claude Code via shell installer");
        let curl_result = silent_command("/bin/bash")
            .args(["-c", "curl -fsSL https://claude.ai/install.sh | bash"])
            .output();

        match curl_result {
            Ok(output) if output.status.success() => {
                return DependencyInstallDispatchResult::Provider(ProviderInstallPreparation {
                    provider: ProviderCli::Claude,
                    installer: "shell",
                    npm_path: None,
                    expected_path: None,
                });
            }
            Ok(output) => {
                let stderr = String::from_utf8_lossy(&output.stderr);
                warn!("Claude shell installer failed: {}", stderr.trim());
            }
            Err(error) => warn!("Claude shell installer failed to launch: {}", error),
        }
    }

    let npm = match ensure_npm() {
        Ok(path) => path,
        Err(_) => {
            return DependencyInstallDispatchResult::Final(DependencyInstallResult::failed(
                "Could not install Claude Code. Please install it manually: https://code.claude.com/docs/setup",
            ));
        }
    };

    let expected_path = expected_cli_path_from_npm(&npm, ProviderCli::Claude.command());
    info!(
        "Installing Claude Code via npm: npm={} expected_path={:?}",
        npm, expected_path
    );
    let result = silent_command(&npm)
        .args(["install", "-g", "@anthropic-ai/claude-code"])
        .output();

    match result {
        Ok(output) if output.status.success() => {
            // Invalidate cache after install so the newly installed binary
            // becomes visible to the verification loop.
            platform::invalidate_shell_cache();

            DependencyInstallDispatchResult::Provider(ProviderInstallPreparation {
                provider: ProviderCli::Claude,
                installer: "npm",
                npm_path: Some(npm),
                expected_path,
            })
        }
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            DependencyInstallDispatchResult::Final(DependencyInstallResult::failed(format!(
                "Could not install Claude Code. {}",
                stderr.lines().last().unwrap_or("").trim()
            )))
        }
        Err(error) => DependencyInstallDispatchResult::Final(DependencyInstallResult::failed(
            format!("Could not install Claude Code: {}", error),
        )),
    }
}

/// Install Codex CLI using the native binary from GitHub releases (macOS).
/// Falls back to npm on non-macOS platforms or if the native install fails.
pub fn install_codex() -> DependencyInstallDispatchResult {
    if let Some(existing_path) = platform::resolve_codex_path() {
        info!("Codex already resolvable at {}", existing_path);
        return DependencyInstallDispatchResult::Provider(ProviderInstallPreparation {
            provider: ProviderCli::Codex,
            installer: "existing",
            npm_path: None,
            expected_path: Some(existing_path),
        });
    }

    // Strategy 1 (macOS): Download the official native binary from GitHub releases.
    #[cfg(target_os = "macos")]
    {
        match install_managed_codex() {
            Ok(managed_path) => {
                info!(
                    "Codex native install succeeded, expected path: {}",
                    managed_path.display()
                );
                return DependencyInstallDispatchResult::Provider(ProviderInstallPreparation {
                    provider: ProviderCli::Codex,
                    installer: "native",
                    npm_path: None,
                    expected_path: Some(managed_path.to_string_lossy().to_string()),
                });
            }
            Err(e) => {
                warn!("Codex native install failed: {}. Falling back to npm.", e);
            }
        }
    }

    // Strategy 2: Fall back to npm
    let npm = match ensure_npm() {
        Ok(path) => path,
        Err(error) => {
            return DependencyInstallDispatchResult::Final(DependencyInstallResult::failed(error));
        }
    };

    #[cfg(not(target_os = "windows"))]
    {
        let resolved_node = platform::resolve_command("node");
        if resolved_node == "node" {
            return DependencyInstallDispatchResult::Final(DependencyInstallResult::failed(
                "Node.js is required to run Codex but could not be found on PATH. \
                 Please install Node.js from https://nodejs.org or let Foundry install it automatically."
                    .to_string(),
            ));
        }
    }

    let expected_path = expected_cli_path_from_npm(&npm, ProviderCli::Codex.command());
    info!(
        "Installing Codex via npm: npm={} expected_path={:?}",
        npm, expected_path
    );

    platform::invalidate_shell_cache();

    let result = silent_command(&npm)
        .args(["install", "-g", "@openai/codex"])
        .output();

    match result {
        Ok(output) if output.status.success() => {
            platform::invalidate_shell_cache();

            DependencyInstallDispatchResult::Provider(ProviderInstallPreparation {
                provider: ProviderCli::Codex,
                installer: "npm",
                npm_path: Some(npm),
                expected_path,
            })
        }
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr);
            DependencyInstallDispatchResult::Final(DependencyInstallResult::failed(format!(
                "Could not install Codex. {}",
                stderr.lines().last().unwrap_or("").trim()
            )))
        }
        Err(error) => DependencyInstallDispatchResult::Final(DependencyInstallResult::failed(
            format!("Could not install Codex: {}", error),
        )),
    }
}
