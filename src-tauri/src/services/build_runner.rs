use std::path::Path;
use tokio::process::Command;

pub struct BuildResult {
    pub success: bool,
    pub output: String,
    pub errors: String,
}

/// Run CMake configure + build.
pub async fn build(project_dir: &Path, skip_configure: bool) -> Result<BuildResult, String> {
    let env = crate::services::claude_code_service::shell_environment();

    // Phase 1: Configure (skip on retries)
    if !skip_configure {
        let config_result = run_process(
            "cmake",
            &["-B", "build", "-DCMAKE_BUILD_TYPE=Debug", "-DCMAKE_OSX_ARCHITECTURES=arm64"],
            project_dir,
            &env,
            60,
        ).await;

        if config_result.exit_code != 0 {
            return Ok(BuildResult {
                success: false,
                output: config_result.stdout,
                errors: format!("CMake configuration failed:\n{}", config_result.stderr),
            });
        }
    }

    // Phase 2: Build
    let build_result = run_process(
        "cmake",
        &["--build", "build", "--config", "Debug", "--parallel"],
        project_dir,
        &env,
        120,
    ).await;

    let success = build_result.exit_code == 0;
    let errors = if success {
        String::new()
    } else {
        parse_errors(&format!("{}\n{}", build_result.stderr, build_result.stdout))
    };

    Ok(BuildResult {
        success,
        output: build_result.stdout,
        errors,
    })
}

/// Check if AU or VST3 bundles exist in the build output.
pub fn smoke_test(project_dir: &Path) -> bool {
    let build_dir = project_dir.join("build");
    if !build_dir.exists() { return false; }

    // Walk the build dir looking for .component or .vst3 bundles
    find_bundle(&build_dir, ".component") || find_bundle(&build_dir, ".vst3")
}

fn find_bundle(dir: &Path, extension: &str) -> bool {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if path.extension().map(|e| format!(".{}", e.to_string_lossy())) == Some(extension.to_string()) {
                    return true;
                }
                if find_bundle(&path, extension) {
                    return true;
                }
            }
        }
    }
    false
}

/// Locate the best bundle path for a given format.
pub fn locate_bundle(build_dir: &Path, format: &str) -> Option<std::path::PathBuf> {
    let ext = match format {
        "au" | "AU" => ".component",
        "vst3" | "VST3" => ".vst3",
        _ => return None,
    };
    find_bundle_path(build_dir, ext)
}

fn find_bundle_path(dir: &Path, extension: &str) -> Option<std::path::PathBuf> {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if path.extension().map(|e| format!(".{}", e.to_string_lossy())) == Some(extension.to_string()) {
                    return Some(path);
                }
                if let Some(found) = find_bundle_path(&path, extension) {
                    return Some(found);
                }
            }
        }
    }
    None
}

fn parse_errors(raw: &str) -> String {
    let lines: Vec<&str> = raw.lines().collect();
    let error_lines: Vec<&str> = lines.iter().copied().filter(|line| {
        line.contains("error:") || line.contains("Error:") ||
        line.contains("fatal error") || line.contains("undefined reference") ||
        line.contains("linker command failed")
    }).collect();

    if error_lines.is_empty() {
        lines.iter().rev().take(30).rev().copied().collect::<Vec<_>>().join("\n")
    } else {
        error_lines.join("\n")
    }
}

struct ProcessResult {
    exit_code: i32,
    stdout: String,
    stderr: String,
}

async fn run_process(
    cmd: &str,
    args: &[&str],
    working_dir: &Path,
    env: &[(String, String)],
    timeout_secs: u64,
) -> ProcessResult {
    let child = Command::new("/usr/bin/env")
        .arg(cmd)
        .args(args)
        .current_dir(working_dir)
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn();

    let child = match child {
        Ok(c) => c,
        Err(e) => return ProcessResult { exit_code: -1, stdout: String::new(), stderr: e.to_string() },
    };

    let result = tokio::time::timeout(
        std::time::Duration::from_secs(timeout_secs),
        async {
            let output = child.wait_with_output().await?;
            Ok::<_, std::io::Error>(output)
        },
    ).await;

    match result {
        Ok(Ok(output)) => ProcessResult {
            exit_code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        },
        Ok(Err(e)) => ProcessResult { exit_code: -1, stdout: String::new(), stderr: e.to_string() },
        Err(_) => {
            ProcessResult { exit_code: -1, stdout: String::new(), stderr: "Process timed out".into() }
        }
    }
}
