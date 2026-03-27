use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};

use serde::{Deserialize, Serialize};

use crate::platform;
use crate::services::auth_service::{SupabaseAuth, SUPABASE_ANON_KEY, SUPABASE_URL};

/// Global lock: only one install can run at a time.
static INSTALL_ACTIVE: AtomicBool = AtomicBool::new(false);

/// Create a Command that hides console windows on Windows.
fn silent_command(cmd: &str) -> Command {
    #[allow(unused_mut)]
    let mut c = Command::new(cmd);
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x08000000); // CREATE_NO_WINDOW
    }
    c
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

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct OnboardingState {
    pub completed: bool,
    pub completed_at: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DependencyInstallResult {
    pub success: bool,
    pub message: String,
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
        return DependencyInstallResult {
            success: false,
            message: "Xcode Command Line Tools are only available on macOS.".into(),
        };
    }

    #[cfg(target_os = "macos")]
    {
        let output = silent_command("xcode-select").args(["--install"]).output();

        match output {
            Ok(o) => {
                let stderr = String::from_utf8_lossy(&o.stderr);
                if stderr.contains("already installed") {
                    DependencyInstallResult {
                        success: true,
                        message: "Xcode Command Line Tools are already installed.".into(),
                    }
                } else {
                    DependencyInstallResult {
                    success: true,
                    message: "Xcode Command Line Tools installer launched. Please complete the installation in the popup window.".into(),
                }
                }
            }
            Err(e) => DependencyInstallResult {
                success: false,
                message: format!("Failed to launch installer: {}", e),
            },
        }
    }
}

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
            std::path::PathBuf::from(&program_files).join("nodejs").join("npm.cmd"),
            std::path::PathBuf::from(&appdata).join("npm").join("npm.cmd"),
        ] {
            if candidate.is_file() {
                return Some(candidate.to_string_lossy().to_string());
            }
        }

        return None;
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
                .trim_end_matches(|c: char| matches!(c, '-' | '\\' | '|' | '/' | ' '))
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
            return DependencyInstallResult {
                success: false,
                message: format!(
                    "winget is not available. Install {} manually, then click Re-check.",
                    display_name
                ),
            };
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
        Ok(output) if output.status.success() => DependencyInstallResult {
            success: true,
            message: format!("{} installed successfully.", display_name),
        },
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
                DependencyInstallResult {
                    success: true,
                    message: format!("{} is already installed.", display_name),
                }
            } else {
                let clean = sanitize_winget_output(&combined);
                DependencyInstallResult {
                    success: false,
                    message: format!("Could not install {}. {}", display_name, clean),
                }
            }
        }
        Err(error) => DependencyInstallResult {
            success: false,
            message: format!("Could not install {}: {}", display_name, error),
        },
    }
}

fn install_homebrew() -> Result<(), String> {
    #[cfg(not(target_os = "macos"))]
    {
        return Err("Homebrew installation is only supported on macOS.".into());
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

/// Install CMake via Homebrew (installs Homebrew first if needed).
pub fn install_cmake() -> DependencyInstallResult {
    let resolved = platform::resolve_command("cmake");
    if resolved != "cmake" {
        return DependencyInstallResult {
            success: true,
            message: "CMake is already installed.".into(),
        };
    }

    #[cfg(target_os = "windows")]
    {
        return run_winget_install("Kitware.CMake", "CMake", &[]);
    }

    let brew = match resolve_brew_path() {
        Some(path) => path,
        None => {
            if let Err(e) = install_homebrew() {
                return DependencyInstallResult {
                    success: false,
                    message: e,
                };
            }
            match resolve_brew_path() {
                Some(path) => path,
                None => {
                    return DependencyInstallResult {
                        success: false,
                        message: "Homebrew installed but could not be found on PATH.".into(),
                    }
                }
            }
        }
    };

    let result = silent_command(&brew).args(["install", "cmake"]).output();

    match result {
        Ok(o) if o.status.success() => DependencyInstallResult {
            success: true,
            message: "CMake installed successfully via Homebrew.".into(),
        },
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            let stdout = String::from_utf8_lossy(&o.stdout);
            if stderr.contains("already installed") || stdout.contains("already installed") {
                DependencyInstallResult {
                    success: true,
                    message: "CMake is already installed via Homebrew.".into(),
                }
            } else {
                DependencyInstallResult {
                    success: false,
                    message: format!("Failed to install CMake: {}", stderr.trim()),
                }
            }
        }
        Err(e) => DependencyInstallResult {
            success: false,
            message: format!("Failed to run brew: {}", e),
        },
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

/// Install Visual Studio Build Tools on Windows.
///
/// Uses the official Microsoft bootstrapper (vs_BuildTools.exe) with a GUI
/// installer — same pattern as Xcode CLT on macOS. The function downloads
/// the bootstrapper, launches it, and returns immediately. The frontend
/// polls with `check_dependencies` until vswhere detects the installation.
pub fn install_cpp_build_tools() -> DependencyInstallResult {
    #[cfg(not(target_os = "windows"))]
    {
        return DependencyInstallResult {
            success: false,
            message: "C++ Build Tools installation is only available on Windows.".into(),
        };
    }

    #[cfg(target_os = "windows")]
    {
        // Pre-check with vswhere
        if vs_build_tools_installed() {
            return DependencyInstallResult {
                success: true,
                message: "Windows Build Tools are already installed.".into(),
            };
        }

        // Download the official VS Build Tools bootstrapper
        let temp_dir = std::env::temp_dir();
        let bootstrapper_path = temp_dir.join("vs_BuildTools.exe");

        // Download using PowerShell (curl may not be available)
        let download = silent_command("powershell")
            .args([
                "-NoProfile",
                "-Command",
                &format!(
                    "Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_BuildTools.exe' -OutFile '{}'",
                    bootstrapper_path.display()
                ),
            ])
            .output();

        match download {
            Ok(o) if o.status.success() && bootstrapper_path.is_file() => {}
            _ => {
                return DependencyInstallResult {
                    success: false,
                    message: "Could not download the Build Tools installer. Check your internet connection and try again.".into(),
                };
            }
        }

        // Launch the bootstrapper with C++ workload — GUI mode so the user
        // can see progress. This returns immediately (non-blocking).
        let launch = silent_command(&bootstrapper_path.to_string_lossy())
            .args([
                "--add", "Microsoft.VisualStudio.Workload.VCTools",
                "--includeRecommended",
                "--passive",  // shows progress UI, no interaction needed
                "--norestart",
            ])
            .spawn();

        match launch {
            Ok(_) => DependencyInstallResult {
                success: true,
                message: "Build Tools installer launched. Please wait for it to complete.".into(),
            },
            Err(e) => DependencyInstallResult {
                success: false,
                message: format!("Could not launch the Build Tools installer: {}", e),
            },
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

        return Err(
            "Node.js was installed but npm is not yet available. Please restart Foundry and try again."
                .to_string(),
        );
    }

    #[cfg(not(target_os = "windows"))]
    {
        let brew = resolve_brew_path().ok_or_else(|| {
            "npm is not installed and Homebrew is not available. Please install Node.js from https://nodejs.org".to_string()
        })?;

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

        resolve_npm_path()
            .ok_or_else(|| "Node.js installed but npm could not be found on PATH.".to_string())
    }
}

/// Install Claude Code using the native installer (no Node.js required).
/// Falls back to winget on Windows, brew on macOS, and npm as last resort.
pub fn install_claude_code() -> DependencyInstallResult {
    let resolved = platform::resolve_command("claude");
    if resolved != "claude" {
        return DependencyInstallResult {
            success: true,
            message: "Claude Code is already installed.".into(),
        };
    }

    // Try native installer first (recommended by Anthropic, no dependencies)
    #[cfg(target_os = "windows")]
    {
        // Windows: try winget first (cleanest), then PowerShell native installer
        let winget_result = run_winget_install("Anthropic.ClaudeCode", "Claude Code", &[]);
        if winget_result.success {
            platform::invalidate_shell_cache();
            return winget_result;
        }

        // Fallback: PowerShell native installer
        let ps_result = silent_command("powershell")
            .args([
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-Command",
                "irm https://claude.ai/install.ps1 | iex",
            ])
            .output();

        match ps_result {
            Ok(o) if o.status.success() => {
                platform::invalidate_shell_cache();
                return DependencyInstallResult {
                    success: true,
                    message: "Claude Code installed successfully.".into(),
                };
            }
            _ => {}
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        // macOS/Linux: native installer via curl
        let curl_result = silent_command("/bin/bash")
            .args(["-c", "curl -fsSL https://claude.ai/install.sh | bash"])
            .output();

        match curl_result {
            Ok(o) if o.status.success() => {
                platform::invalidate_shell_cache();
                return DependencyInstallResult {
                    success: true,
                    message: "Claude Code installed successfully.".into(),
                };
            }
            _ => {}
        }
    }

    // Last resort: npm
    let npm = match ensure_npm() {
        Ok(path) => path,
        Err(_) => {
            return DependencyInstallResult {
                success: false,
                message: "Could not install Claude Code. Please install it manually: https://code.claude.com/docs/setup".into(),
            };
        }
    };

    let result = silent_command(&npm)
        .args(["install", "-g", "@anthropic-ai/claude-code"])
        .output();

    match result {
        Ok(o) if o.status.success() => {
            platform::invalidate_shell_cache();
            DependencyInstallResult {
                success: true,
                message: "Claude Code installed successfully.".into(),
            }
        }
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            DependencyInstallResult {
                success: false,
                message: format!("Could not install Claude Code. {}", stderr.lines().last().unwrap_or("").trim()),
            }
        }
        Err(e) => DependencyInstallResult {
            success: false,
            message: format!("Could not install Claude Code: {}", e),
        },
    }
}

/// Install Codex CLI via npm.
pub fn install_codex() -> DependencyInstallResult {
    let resolved = platform::resolve_command("codex");
    if resolved != "codex" {
        return DependencyInstallResult {
            success: true,
            message: "Codex CLI is already installed.".into(),
        };
    }

    let npm = match ensure_npm() {
        Ok(path) => path,
        Err(e) => {
            return DependencyInstallResult {
                success: false,
                message: e,
            }
        }
    };

    let result = silent_command(&npm)
        .args(["install", "-g", "@openai/codex"])
        .output();

    match result {
        Ok(o) if o.status.success() => DependencyInstallResult {
            success: true,
            message: "Codex installed successfully.".into(),
        },
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            DependencyInstallResult {
                success: false,
                message: format!("Could not install Codex. {}", stderr.lines().last().unwrap_or("").trim()),
            }
        }
        Err(e) => DependencyInstallResult {
            success: false,
            message: format!("Could not install Codex: {}", e),
        },
    }
}
