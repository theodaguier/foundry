use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use chrono::Utc;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter};

use crate::platform;
use crate::services::foundry_paths;

const JUCE_DOWNLOAD_URL: &str =
    "https://github.com/juce-framework/JUCE/archive/refs/tags/8.0.12.zip";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BuildEnvironmentIssue {
    pub code: String,
    pub title: String,
    pub detail: String,
    pub recoverable: bool,
    pub action_label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BuildEnvironmentStatus {
    pub state: String,
    pub issues: Vec<BuildEnvironmentIssue>,
    pub juce_source: Option<String>,
    pub juce_path: Option<String>,
    pub juce_version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct EnvironmentConfig {
    managed_juce_version: Option<String>,
    juce_override_path: Option<String>,
    last_resolved_juce_path: Option<String>,
    last_validation_at: Option<String>,
}

#[derive(Clone, serde::Serialize)]
struct StepEvent {
    step: String,
}

#[derive(Clone, serde::Serialize)]
struct LogEvent {
    timestamp: String,
    message: String,
    style: Option<String>,
}

fn now_ts() -> String {
    chrono::Local::now().format("[%H:%M:%S]").to_string()
}

fn emit_step(app: &AppHandle, step: &str) {
    let _ = app.emit("pipeline:step", StepEvent { step: step.into() });
}

fn emit_log(app: &AppHandle, message: &str, style: Option<&str>) {
    let _ = app.emit(
        "pipeline:log",
        LogEvent {
            timestamp: now_ts(),
            message: message.into(),
            style: style.map(|value| value.into()),
        },
    );
}

pub async fn get_build_environment() -> Result<BuildEnvironmentStatus, String> {
    inspect_environment(false, None).await
}

pub async fn prepare_build_environment(
    auto_repair: bool,
    app: Option<&AppHandle>,
) -> Result<BuildEnvironmentStatus, String> {
    inspect_environment(auto_repair, app).await
}

pub async fn install_managed_juce() -> Result<BuildEnvironmentStatus, String> {
    inspect_environment(true, None).await
}

pub async fn set_juce_override_path(path: String) -> Result<BuildEnvironmentStatus, String> {
    let mut config = read_environment_config()?;
    config.juce_override_path = Some(path);
    write_environment_config(&config)?;
    inspect_environment(false, None).await
}

pub async fn clear_juce_override_path() -> Result<BuildEnvironmentStatus, String> {
    let mut config = read_environment_config()?;
    config.juce_override_path = None;
    write_environment_config(&config)?;
    inspect_environment(false, None).await
}

pub fn format_blocked_message(status: &BuildEnvironmentStatus) -> String {
    let details = status
        .issues
        .iter()
        .map(|issue| format!("{}: {}", issue.title, issue.detail))
        .collect::<Vec<_>>();

    if details.is_empty() {
        "Build environment is not ready.".to_string()
    } else {
        format!("Build environment is not ready.\n{}", details.join("\n"))
    }
}

async fn inspect_environment(
    auto_repair: bool,
    app: Option<&AppHandle>,
) -> Result<BuildEnvironmentStatus, String> {
    if let Some(app_handle) = app {
        emit_step(app_handle, "preparingEnvironment");
        emit_log(
            app_handle,
            "START: Preparing build environment...",
            Some("active"),
        );
        emit_log(app_handle, "Checking required tools...", None);
    }

    let mut config = read_environment_config()?;
    let mut issues = collect_dependency_issues();
    let mut blocked = !issues.is_empty();
    let mut juce_source = None;
    let mut juce_path = None;

    if let Some(app_handle) = app {
        emit_log(app_handle, "Checking JUCE...", None);
    }

    if let Some(override_path) = config.juce_override_path.clone() {
        let override_path_buf = PathBuf::from(&override_path);
        match validate_juce_directory(&override_path_buf) {
            Ok(()) => {
                juce_source = Some("override".to_string());
                juce_path = Some(override_path_buf);
            }
            Err(detail) => issues.push(BuildEnvironmentIssue {
                code: "juce_override_invalid".into(),
                title: "JUCE override is invalid".into(),
                detail: format!("{} ({})", detail, override_path),
                recoverable: true,
                action_label: Some("Use Managed Copy".into()),
            }),
        }
    }

    if juce_path.is_none() {
        let managed_path =
            foundry_paths::managed_juce_dir(&foundry_paths::DEFAULT_MANAGED_JUCE_VERSION);
        match validate_juce_directory(&managed_path) {
            Ok(()) => {
                juce_source = Some("managed".to_string());
                juce_path = Some(managed_path);
            }
            Err(detail) if auto_repair => {
                if let Some(app_handle) = app {
                    emit_log(
                        app_handle,
                        &format!(
                            "Downloading JUCE {} from the official release...",
                            foundry_paths::DEFAULT_MANAGED_JUCE_VERSION
                        ),
                        Some("active"),
                    );
                }

                match download_and_install_managed_juce(app).await {
                    Ok(installed_path) => {
                        juce_source = Some("managed".to_string());
                        juce_path = Some(installed_path);
                    }
                    Err(install_error) => {
                        blocked = true;
                        issues.push(BuildEnvironmentIssue {
                            code: "juce_install_failed".into(),
                            title: "JUCE installation failed".into(),
                            detail: install_error,
                            recoverable: true,
                            action_label: Some("Retry JUCE Install".into()),
                        });
                    }
                }
            }
            Err(detail) => {
                blocked = true;
                issues.push(BuildEnvironmentIssue {
                    code: "juce_missing".into(),
                    title: "JUCE is not installed".into(),
                    detail,
                    recoverable: true,
                    action_label: Some("Install JUCE".into()),
                });
            }
        }
    }

    if juce_path.is_none() {
        blocked = true;
    }

    if let Some(path) = &juce_path {
        config.managed_juce_version = Some(foundry_paths::DEFAULT_MANAGED_JUCE_VERSION.to_string());
        config.last_resolved_juce_path = Some(path.to_string_lossy().to_string());
        config.last_validation_at = Some(Utc::now().to_rfc3339());
        write_environment_config(&config)?;

        if let Some(app_handle) = app {
            emit_log(app_handle, "Validating JUCE installation...", None);
        }
    } else {
        config.last_resolved_juce_path = None;
        config.last_validation_at = Some(Utc::now().to_rfc3339());
        write_environment_config(&config)?;
    }

    let status = BuildEnvironmentStatus {
        state: if blocked {
            "blocked".into()
        } else {
            "ready".into()
        },
        issues,
        juce_source,
        juce_path: juce_path.map(|path| path.to_string_lossy().to_string()),
        juce_version: foundry_paths::DEFAULT_MANAGED_JUCE_VERSION.to_string(),
    };

    if let Some(app_handle) = app {
        if status.state == "ready" {
            emit_log(app_handle, "Environment ready.", Some("success"));
        } else {
            emit_log(app_handle, "Build environment is blocked.", Some("error"));
        }
    }

    Ok(status)
}

fn collect_dependency_issues() -> Vec<BuildEnvironmentIssue> {
    platform::required_dependencies()
        .into_iter()
        .filter_map(|spec| {
            if platform::check_dependency(&spec).is_some() {
                return None;
            }

            let (code, detail, action_label) = match spec.name {
                "Xcode Command Line Tools" => (
                    "xcode_clt_missing",
                    "Install Xcode Command Line Tools with `xcode-select --install`.",
                    Some("Install Xcode CLT"),
                ),
                "CMake" => (
                    "cmake_missing",
                    "CMake is required before Foundry can configure JUCE projects.",
                    Some("Install CMake"),
                ),
                "C++ Build Tools" => (
                    "cpp_build_tools_missing",
                    "Install Visual Studio 2022 Build Tools with the Desktop C++ workload.",
                    Some("Install Build Tools"),
                ),
                "Ninja" => (
                    "ninja_missing",
                    "Ninja is required before Foundry can build JUCE projects.",
                    Some("Install Ninja"),
                ),
                "Claude Code CLI" => (
                    "claude_cli_missing",
                    "Claude Code CLI is required before Foundry can generate code.",
                    Some("Install Claude CLI"),
                ),
                "Codex CLI" => {
                    // Codex is optional — don't block the build environment
                    return None;
                }
                _ => (
                    "dependency_missing",
                    "A required build dependency is missing.",
                    None,
                ),
            };

            Some(BuildEnvironmentIssue {
                code: code.into(),
                title: format!("{} missing", spec.name),
                detail: detail.into(),
                recoverable: false,
                action_label: action_label.map(str::to_string),
            })
        })
        .collect()
}

async fn download_and_install_managed_juce(app: Option<&AppHandle>) -> Result<PathBuf, String> {
    let managed_root = foundry_paths::managed_juce_root_dir();
    let final_path = foundry_paths::managed_juce_dir(&foundry_paths::DEFAULT_MANAGED_JUCE_VERSION);
    let temp_root = foundry_paths::application_support_dir().join("tmp");
    let extract_root = temp_root.join(format!("juce-extract-{}", uuid::Uuid::new_v4().simple()));
    let archive_path = temp_root.join(format!(
        "juce-{}-{}.zip",
        foundry_paths::DEFAULT_MANAGED_JUCE_VERSION,
        uuid::Uuid::new_v4().simple()
    ));

    fs::create_dir_all(&managed_root).map_err(|error| error.to_string())?;
    fs::create_dir_all(&temp_root).map_err(|error| error.to_string())?;

    let cleanup = |archive: &Path, extract: &Path| {
        let _ = fs::remove_file(archive);
        let _ = fs::remove_dir_all(extract);
    };

    let response = reqwest::get(JUCE_DOWNLOAD_URL)
        .await
        .map_err(|error| error.to_string())?
        .error_for_status()
        .map_err(|error| error.to_string())?;
    let body = response.bytes().await.map_err(|error| error.to_string())?;
    tokio::fs::write(&archive_path, body)
        .await
        .map_err(|error| error.to_string())?;

    if let Some(app_handle) = app {
        emit_log(app_handle, "Extracting JUCE archive...", None);
    }

    fs::create_dir_all(&extract_root).map_err(|error| error.to_string())?;
    extract_zip_archive(&archive_path, &extract_root).inspect_err(|_| {
        cleanup(&archive_path, &extract_root);
    })?;

    let extracted_path = find_extracted_juce_root(&extract_root)?.ok_or_else(|| {
        "The JUCE archive was extracted, but the JUCE root directory could not be found."
            .to_string()
    })?;

    if let Some(app_handle) = app {
        emit_log(app_handle, "Validating JUCE installation...", None);
    }

    validate_juce_directory(&extracted_path)?;

    if final_path.exists() {
        fs::remove_dir_all(&final_path).map_err(|error| error.to_string())?;
    }

    fs::rename(&extracted_path, &final_path).map_err(|error| error.to_string())?;
    cleanup(&archive_path, &extract_root);

    Ok(final_path)
}

fn extract_zip_archive(archive_path: &Path, extract_root: &Path) -> Result<(), String> {
    let file = fs::File::open(archive_path).map_err(|error| error.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|error| error.to_string())?;

    for index in 0..archive.len() {
        let mut entry = archive.by_index(index).map_err(|error| error.to_string())?;
        let Some(relative_path) = entry.enclosed_name().map(|path| path.to_path_buf()) else {
            continue;
        };
        let output_path = extract_root.join(relative_path);

        if entry.is_dir() {
            fs::create_dir_all(&output_path).map_err(|error| error.to_string())?;
            continue;
        }

        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }

        let mut output = fs::File::create(&output_path).map_err(|error| error.to_string())?;
        io::copy(&mut entry, &mut output).map_err(|error| error.to_string())?;

        #[cfg(unix)]
        if let Some(mode) = entry.unix_mode() {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&output_path, fs::Permissions::from_mode(mode));
        }
    }

    Ok(())
}

fn find_extracted_juce_root(extract_root: &Path) -> Result<Option<PathBuf>, String> {
    let expected = extract_root.join(format!(
        "JUCE-{}",
        foundry_paths::DEFAULT_MANAGED_JUCE_VERSION
    ));
    if expected.exists() {
        return Ok(Some(expected));
    }

    let entries = fs::read_dir(extract_root).map_err(|error| error.to_string())?;
    for entry in entries {
        let entry = entry.map_err(|error| error.to_string())?;
        let path = entry.path();
        if path.is_dir() && validate_juce_directory(&path).is_ok() {
            return Ok(Some(path));
        }
    }

    Ok(None)
}

fn validate_juce_directory(path: &Path) -> Result<(), String> {
    if !path.exists() {
        return Err(format!("Directory does not exist: {}", path.display()));
    }
    if !path.join("CMakeLists.txt").exists() {
        return Err("Missing JUCE CMakeLists.txt".into());
    }
    if !path.join("modules/juce_core/juce_core.h").exists() {
        return Err("Missing modules/juce_core/juce_core.h".into());
    }
    if !path.join("modules").exists() && !path.join("extras/Build").exists() {
        return Err("Missing JUCE modules directory".into());
    }
    Ok(())
}

fn read_environment_config() -> Result<EnvironmentConfig, String> {
    let path = foundry_paths::environment_config_path();
    if !path.exists() {
        return Ok(EnvironmentConfig::default());
    }

    let content = fs::read_to_string(&path).map_err(|error| error.to_string())?;
    serde_json::from_str(&content).or_else(|error| {
        log::warn!(
            "Failed to parse {}: {}. Falling back to default build environment config.",
            path.display(),
            error
        );
        Ok(EnvironmentConfig::default())
    })
}

fn write_environment_config(config: &EnvironmentConfig) -> Result<(), String> {
    let app_support = foundry_paths::application_support_dir();
    fs::create_dir_all(&app_support).map_err(|error| error.to_string())?;

    let content = serde_json::to_string_pretty(config).map_err(|error| error.to_string())?;
    fs::write(foundry_paths::environment_config_path(), content).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::validate_juce_directory;
    use std::fs;

    #[test]
    fn validate_juce_directory_accepts_expected_layout() {
        let root = std::env::temp_dir().join(format!("foundry-juce-test-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(root.join("modules/juce_core")).unwrap();
        fs::create_dir_all(root.join("extras/Build")).unwrap();
        fs::write(
            root.join("CMakeLists.txt"),
            "cmake_minimum_required(VERSION 3.22)",
        )
        .unwrap();
        fs::write(root.join("modules/juce_core/juce_core.h"), "// header").unwrap();

        assert!(validate_juce_directory(&root).is_ok());

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn validate_juce_directory_rejects_missing_core_header() {
        let root = std::env::temp_dir().join(format!("foundry-juce-test-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(root.join("modules")).unwrap();
        fs::write(
            root.join("CMakeLists.txt"),
            "cmake_minimum_required(VERSION 3.22)",
        )
        .unwrap();

        let error = validate_juce_directory(&root).unwrap_err();
        assert!(error.contains("juce_core"));

        let _ = fs::remove_dir_all(root);
    }
}
