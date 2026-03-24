use std::process::Command;

use serde::{Deserialize, Serialize};

use crate::platform;
use crate::services::auth_service::{SupabaseAuth, SUPABASE_ANON_KEY, SUPABASE_URL};

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
    let output = Command::new("xcode-select").args(["--install"]).output();

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
    let resolved = platform::resolve_command("npm");
    if resolved != "npm" {
        return Some(resolved);
    }
    for path in &["/opt/homebrew/bin/npm", "/usr/local/bin/npm"] {
        if std::path::Path::new(path).is_file() {
            return Some(path.to_string());
        }
    }
    None
}

fn install_homebrew() -> Result<(), String> {
    let result = Command::new("/bin/bash")
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

/// Install CMake via Homebrew (installs Homebrew first if needed).
pub fn install_cmake() -> DependencyInstallResult {
    let resolved = platform::resolve_command("cmake");
    if resolved != "cmake" {
        return DependencyInstallResult {
            success: true,
            message: "CMake is already installed.".into(),
        };
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

    let result = Command::new(&brew).args(["install", "cmake"]).output();

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

fn ensure_npm() -> Result<String, String> {
    if let Some(npm) = resolve_npm_path() {
        return Ok(npm);
    }

    let brew = resolve_brew_path().ok_or_else(|| {
        "npm is not installed and Homebrew is not available. Please install Node.js from https://nodejs.org".to_string()
    })?;

    let result = Command::new(&brew)
        .args(["install", "node"])
        .output()
        .map_err(|e| format!("Failed to install Node.js: {}", e))?;

    if !result.status.success() {
        let stderr = String::from_utf8_lossy(&result.stderr);
        if !stderr.contains("already installed") {
            return Err(format!("Failed to install Node.js: {}", stderr.trim()));
        }
    }

    resolve_npm_path()
        .ok_or_else(|| "Node.js installed but npm could not be found on PATH.".to_string())
}

/// Install Claude Code CLI via npm.
pub fn install_claude_code() -> DependencyInstallResult {
    let resolved = platform::resolve_command("claude");
    if resolved != "claude" {
        return DependencyInstallResult {
            success: true,
            message: "Claude Code CLI is already installed.".into(),
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

    let result = Command::new(&npm)
        .args(["install", "-g", "@anthropic-ai/claude-code"])
        .output();

    match result {
        Ok(o) if o.status.success() => DependencyInstallResult {
            success: true,
            message: "Claude Code CLI installed successfully.".into(),
        },
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            DependencyInstallResult {
                success: false,
                message: format!("Failed to install Claude Code CLI: {}", stderr.trim()),
            }
        }
        Err(e) => DependencyInstallResult {
            success: false,
            message: format!("Failed to run npm: {}", e),
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

    let result = Command::new(&npm)
        .args(["install", "-g", "@openai/codex"])
        .output();

    match result {
        Ok(o) if o.status.success() => DependencyInstallResult {
            success: true,
            message: "Codex CLI installed successfully.".into(),
        },
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            DependencyInstallResult {
                success: false,
                message: format!("Failed to install Codex CLI: {}", stderr.trim()),
            }
        }
        Err(e) => DependencyInstallResult {
            success: false,
            message: format!("Failed to run npm: {}", e),
        },
    }
}
