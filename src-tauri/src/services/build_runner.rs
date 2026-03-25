use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BuildFailureStage {
    EnvironmentConfig,
    CompileSource,
    SmokeTest,
}

pub struct BuildResult {
    pub success: bool,
    pub output: String,
    pub errors: String,
    pub failure_stage: Option<BuildFailureStage>,
}

/// Run CMake configure + build.
pub async fn build(project_dir: &Path, skip_configure: bool) -> Result<BuildResult, String> {
    let env = crate::platform::shell_environment();

    // Phase 1: Configure (skip on retries)
    if !skip_configure {
        let mut cmake_args: Vec<String> = vec!["-B".into(), "build".into()];
        cmake_args.extend(crate::platform::cmake_configure_args());
        let args_refs: Vec<&str> = cmake_args.iter().map(|s| s.as_str()).collect();

        let config_result = run_process("cmake", &args_refs, project_dir, &env, 60).await;

        if config_result.exit_code != 0 {
            let combined = format!("{}\n{}", config_result.stderr, config_result.stdout);
            return Ok(BuildResult {
                success: false,
                output: config_result.stdout,
                errors: format!("CMake configuration failed:\n{}", config_result.stderr),
                failure_stage: Some(classify_build_failure(&combined, true)),
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
    )
    .await;

    let success = build_result.exit_code == 0;
    let combined_output = format!("{}\n{}", build_result.stderr, build_result.stdout);
    let errors = if success {
        String::new()
    } else {
        parse_errors(&combined_output)
    };

    Ok(BuildResult {
        success,
        output: build_result.stdout,
        errors,
        failure_stage: if success {
            None
        } else {
            Some(classify_build_failure(&combined_output, false))
        },
    })
}

/// Check if plugin bundles exist in the build output.
pub fn smoke_test(project_dir: &Path) -> bool {
    let build_dir = project_dir.join("build");
    if !build_dir.exists() {
        return false;
    }

    // Walk the build dir looking for bundles with platform-appropriate extensions
    crate::platform::smoke_test_extensions()
        .iter()
        .any(|ext| find_bundle(&build_dir, ext))
}

fn find_bundle(dir: &Path, extension: &str) -> bool {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if path
                    .extension()
                    .map(|e| format!(".{}", e.to_string_lossy()))
                    == Some(extension.to_string())
                {
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
    let mappings = crate::platform::bundle_mappings();
    let ext = mappings
        .iter()
        .find(|m| m.format_label.eq_ignore_ascii_case(format))
        .map(|m| m.extension)?;
    find_bundle_path(build_dir, ext)
}

fn find_bundle_path(dir: &Path, extension: &str) -> Option<std::path::PathBuf> {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if path
                    .extension()
                    .map(|e| format!(".{}", e.to_string_lossy()))
                    == Some(extension.to_string())
                {
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
    let error_lines: Vec<&str> = lines
        .iter()
        .copied()
        .filter(|line| {
            line.contains("error:")
                || line.contains("Error:")
                || line.contains("fatal error")
                || line.contains("undefined reference")
                || line.contains("linker command failed")
        })
        .collect();

    if error_lines.is_empty() {
        lines
            .iter()
            .rev()
            .take(30)
            .rev()
            .copied()
            .collect::<Vec<_>>()
            .join("\n")
    } else {
        error_lines.join("\n")
    }
}

fn classify_build_failure(raw: &str, configure_phase: bool) -> BuildFailureStage {
    let lower = raw.to_lowercase();
    let environment_markers = [
        "add_subdirectory given source",
        "unknown cmake command \"juce_add_plugin\"",
        "juce_add_plugin",
        "not an existing directory",
        "cmake command not found",
        "xcode-select",
        "no cxx compiler could be found",
        "cmake error at cmakelists.txt",
        "unable to find utility",
        "could not find any instance of visual studio",
        "could not find a version of visual studio",
        "desktop c++ workload",
    ];

    if environment_markers
        .iter()
        .any(|marker| lower.contains(marker))
    {
        BuildFailureStage::EnvironmentConfig
    } else if configure_phase {
        BuildFailureStage::EnvironmentConfig
    } else {
        BuildFailureStage::CompileSource
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
    // Build the sync Command from platform, then convert to tokio for async execution
    let mut sync_cmd = crate::platform::create_command(cmd);
    sync_cmd
        .args(args)
        .current_dir(working_dir)
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());

    // Convert std::process::Command → tokio::process::Command
    let mut tokio_cmd = tokio::process::Command::from(sync_cmd);
    tokio_cmd.kill_on_drop(true);
    let child = tokio_cmd.spawn();

    let child = match child {
        Ok(c) => c,
        Err(e) => {
            return ProcessResult {
                exit_code: -1,
                stdout: String::new(),
                stderr: e.to_string(),
            }
        }
    };

    let result = tokio::time::timeout(
        std::time::Duration::from_secs(timeout_secs),
        child.wait_with_output(),
    )
    .await;

    match result {
        Ok(Ok(output)) => ProcessResult {
            exit_code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        },
        Ok(Err(e)) => ProcessResult {
            exit_code: -1,
            stdout: String::new(),
            stderr: e.to_string(),
        },
        Err(_) => ProcessResult {
            exit_code: -1,
            stdout: String::new(),
            stderr: "Process timed out".into(),
        },
    }
}
