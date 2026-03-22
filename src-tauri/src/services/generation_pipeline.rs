use std::path::Path;
use tauri::{AppHandle, Emitter};

use crate::models::config::{GenerationConfig, RefineConfig};
use crate::models::plugin::{Plugin, PluginVersion, PluginFormat, InstallPaths};
use crate::services::{claude_code_service, project_assembler, build_runner, foundry_paths, plugin_manager};

#[derive(Clone, serde::Serialize)]
struct StepEvent { step: String }

#[derive(Clone, serde::Serialize)]
struct LogEvent { timestamp: String, message: String, style: Option<String> }

#[derive(Clone, serde::Serialize)]
struct NameEvent { name: String }

#[derive(Clone, serde::Serialize)]
struct ErrorEvent { message: String }

#[derive(Clone, serde::Serialize)]
struct CompleteEvent { plugin: Plugin }

#[derive(Clone, serde::Serialize)]
struct BuildAttemptEvent { attempt: i32 }

fn now_ts() -> String {
    chrono::Local::now().format("[%H:%M:%S]").to_string()
}

fn emit_step(app: &AppHandle, step: &str) {
    let _ = app.emit("pipeline:step", StepEvent { step: step.into() });
}

fn emit_log(app: &AppHandle, message: &str, style: Option<&str>) {
    let _ = app.emit("pipeline:log", LogEvent {
        timestamp: now_ts(),
        message: message.into(),
        style: style.map(|s| s.into()),
    });
}

pub async fn run_generation(
    config: GenerationConfig,
    app: AppHandle,
    cancel_rx: tokio::sync::oneshot::Receiver<()>,
) {
    // Convert oneshot to watch channel for multiple listeners
    let (cancel_tx, cancel_watch) = tokio::sync::watch::channel(false);
    tokio::spawn(async move {
        let _ = cancel_rx.await;
        let _ = cancel_tx.send(true);
    });

    match execute_generation(config, &app, cancel_watch).await {
        Ok(plugin) => {
            let _ = app.emit("pipeline:complete", CompleteEvent { plugin });
        }
        Err(e) => {
            if e != "Cancelled" {
                let _ = app.emit("pipeline:error", ErrorEvent { message: e });
            }
        }
    }
}

async fn execute_generation(
    config: GenerationConfig,
    app: &AppHandle,
    cancel_watch: tokio::sync::watch::Receiver<bool>,
) -> Result<Plugin, String> {
    // Resolve Claude CLI path
    let claude_path = claude_code_service::resolve_claude_path()
        .ok_or_else(|| "Claude Code CLI is not available. Open Setup and install it.".to_string())?;

    let model_flag = &config.model;

    // Step 1: Prepare project
    emit_step(app, "preparingProject");
    emit_log(app, "START: Preparing project...", Some("active"));

    // Load existing plugin names
    let existing_plugins = plugin_manager::load_plugins().unwrap_or_default();
    let existing_names: Vec<String> = existing_plugins.iter().map(|p| p.name.clone()).collect();

    // Generate plugin name
    let plugin_name = claude_code_service::generate_plugin_name(
        &claude_path,
        &config.prompt,
        &existing_names,
    ).await;

    let _ = app.emit("pipeline:name", NameEvent { name: plugin_name.clone() });

    check_cancelled(&cancel_watch)?;

    // Assemble project
    let project = project_assembler::assemble(
        &config.prompt,
        &plugin_name,
        &config.format,
        &config.channel_layout,
        config.preset_count,
        &config.model,
    )?;

    emit_log(app, "PREPARING PROJECT: Dependencies resolved.", Some("success"));

    check_cancelled(&cancel_watch)?;

    // Step 2: Generate DSP code
    emit_step(app, "generatingDSP");
    emit_log(app, "START: Generating DSP code...", Some("active"));

    let plugin_role = match project.plugin_type.as_str() {
        "instrument" => "playable instrument",
        "utility" => "utility or analysis tool",
        _ => "audio effect",
    };

    let gen_prompt = format!(
        "Build a JUCE {} plugin from scratch: {}\n\n\
        Read CLAUDE.md first — it is your mission brief and references the knowledge kit files\n\
        in juce-kit/. There are no existing source files — you create everything in Source/.\n\n\
        Start by reading CLAUDE.md now.",
        plugin_role, config.prompt
    );

    emit_log(app, &format!("── claude · {}: Code generation ──", model_flag), Some("active"));

    let app_clone = app.clone();
    let project_dir_str = project.directory.to_string_lossy().to_string();
    let gen_result = claude_code_service::run(
        &claude_path,
        &gen_prompt,
        &project_dir_str,
        model_flag,
        "generate",
        move |event| handle_claude_event(&app_clone, &event),
        cancel_watch.clone(),
    ).await;

    if is_infra_failure(&gen_result.error) {
        return Err(gen_result.error.unwrap_or_else(|| "Claude Code CLI is unavailable".into()));
    }

    // Check source files were created
    let processor_exists = project.directory.join("Source/PluginProcessor.cpp").exists();
    let editor_exists = project.directory.join("Source/PluginEditor.cpp").exists();
    if !processor_exists || !editor_exists {
        return Err("Claude did not create the required source files".into());
    }

    check_cancelled(&cancel_watch)?;

    emit_log(app, "GENERATING DSP: Audio kernel convergence complete.", Some("success"));

    // Step 3: Audit pass
    emit_step(app, "generatingUI");
    emit_log(app, "START: Audit pass...", Some("active"));

    let app_clone = app.clone();
    let _audit_result = claude_code_service::audit(
        &claude_path,
        &project_dir_str,
        &config.prompt,
        plugin_role,
        model_flag,
        move |event| handle_claude_event(&app_clone, &event),
        cancel_watch.clone(),
    ).await;

    check_cancelled(&cancel_watch)?;

    emit_log(app, "GENERATING UI: Interface layer committed.", Some("success"));

    // Step 4: Build loop
    emit_step(app, "compiling");
    emit_log(app, "START: Compiling plugin...", Some("active"));

    run_build_loop(
        &claude_path,
        &project.directory,
        model_flag,
        app,
        cancel_watch.clone(),
        None, // unlimited attempts
    ).await?;

    check_cancelled(&cancel_watch)?;

    emit_log(app, "COMPILING: Build artifacts ready.", Some("success"));

    // Step 5: Install
    emit_step(app, "installing");
    emit_log(app, "START: Installing plugin...", Some("active"));

    let formats = resolve_formats(&config.format);
    let install_paths = install_plugin(&project.directory, &plugin_name, &formats)?;

    emit_log(app, "INSTALLING: Plugin bundle staged.", Some("success"));

    // Archive build directory
    let plugin_id = uuid::Uuid::new_v4().to_string();
    let archived_dir = archive_build(&project.directory, &plugin_id, 1);

    // Build plugin object
    let colors = ["#C8C4BC", "#A8B4A0", "#B0A898", "#9CAAB8", "#B8A8B0", "#A0A8B0"];
    let icon_color = colors[rand_index(colors.len())].to_string();

    let version = PluginVersion {
        id: uuid::Uuid::new_v4().to_string(),
        plugin_id: plugin_id.clone(),
        version_number: 1,
        prompt: config.prompt.clone(),
        created_at: chrono::Utc::now().to_rfc3339(),
        build_directory: archived_dir.clone(),
        install_paths: install_paths.clone(),
        icon_color: icon_color.clone(),
        is_active: true,
        agent: None,
        model: None,
        telemetry_id: None,
    };

    let plugin = Plugin {
        id: plugin_id,
        name: plugin_name,
        plugin_type: match project.plugin_type.as_str() {
            "instrument" => crate::models::plugin::PluginType::Instrument,
            "utility" => crate::models::plugin::PluginType::Utility,
            _ => crate::models::plugin::PluginType::Effect,
        },
        prompt: config.prompt,
        created_at: chrono::Utc::now().to_rfc3339(),
        formats,
        install_paths,
        icon_color,
        logo_asset_path: None,
        status: crate::models::plugin::PluginStatus::Installed,
        build_directory: archived_dir,
        generation_log_path: None,
        agent: None,
        model: None,
        current_version: 1,
        versions: vec![version],
    };

    // Save plugin to library
    let mut plugins = plugin_manager::load_plugins().unwrap_or_default();
    plugins.insert(0, plugin.clone());
    plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;

    // Clean temp build dir
    let dir = project.directory.clone();
    tokio::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_secs(10)).await;
        let _ = std::fs::remove_dir_all(&dir);
    });

    Ok(plugin)
}

pub async fn run_refine(
    config: RefineConfig,
    app: AppHandle,
    cancel_rx: tokio::sync::oneshot::Receiver<()>,
) {
    let (cancel_tx, cancel_watch) = tokio::sync::watch::channel(false);
    tokio::spawn(async move {
        let _ = cancel_rx.await;
        let _ = cancel_tx.send(true);
    });

    match execute_refine(config, &app, cancel_watch).await {
        Ok(plugin) => {
            let _ = app.emit("pipeline:complete", CompleteEvent { plugin });
        }
        Err(e) => {
            if e != "Cancelled" {
                let _ = app.emit("pipeline:error", ErrorEvent { message: e });
            }
        }
    }
}

async fn execute_refine(
    config: RefineConfig,
    app: &AppHandle,
    cancel_watch: tokio::sync::watch::Receiver<bool>,
) -> Result<Plugin, String> {
    let claude_path = claude_code_service::resolve_claude_path()
        .ok_or_else(|| "Claude Code CLI is not available".to_string())?;

    let build_dir = config.plugin.build_directory.as_deref()
        .ok_or_else(|| "No build directory found - cannot refine this plugin".to_string())?;

    if !Path::new(build_dir).exists() {
        return Err(format!("Build directory no longer exists: {}", build_dir));
    }

    let project_dir = Path::new(build_dir);
    let model_flag = config.plugin.model.as_ref().map(|m| m.flag.as_str()).unwrap_or("sonnet");

    // Backup Source/
    let source_dir = project_dir.join("Source");
    let source_backup = project_dir.join("Source.backup");
    let _ = std::fs::remove_dir_all(&source_backup);
    if source_dir.exists() {
        copy_dir_all(&source_dir, &source_backup).ok();
    }

    // Lock CMakeLists.txt (set read-only)
    let cmake_path = project_dir.join("CMakeLists.txt");
    set_readonly(&cmake_path, true);

    let restore_backup = |project_dir: &Path| {
        let source_dir = project_dir.join("Source");
        let source_backup = project_dir.join("Source.backup");
        let cmake_path = project_dir.join("CMakeLists.txt");
        if source_backup.exists() {
            let _ = std::fs::remove_dir_all(&source_dir);
            let _ = std::fs::rename(&source_backup, &source_dir);
        }
        set_readonly(&cmake_path, false);
    };

    // Generate code
    emit_step(app, "generatingDSP");
    emit_log(app, "START: Modifying code...", Some("active"));

    let plugin_role = match config.plugin.plugin_type {
        crate::models::plugin::PluginType::Instrument => "playable instrument",
        crate::models::plugin::PluginType::Utility => "utility or analysis tool",
        _ => "audio effect",
    };

    let refine_prompt = format!(
        "You are refining an existing, working JUCE {} plugin called \"{}\".\n\
        The plugin already compiles and runs. Your job is to make a targeted modification — not rebuild it.\n\n\
        ## Rules\n\
        - Do NOT modify CMakeLists.txt — it is locked.\n\
        - Do NOT rename the plugin or change class names.\n\
        - Do NOT create new files — only edit existing Source/ files.\n\
        - Do NOT rewrite entire files — use Edit to change only what's needed.\n\n\
        ## Existing source files (read ALL of these first)\n\
        - Source/PluginProcessor.h\n\
        - Source/PluginProcessor.cpp\n\
        - Source/PluginEditor.h\n\
        - Source/PluginEditor.cpp\n\
        - Source/FoundryLookAndFeel.h\n\n\
        ## Requested modification\n\
        {}",
        plugin_role, config.plugin.name, config.modification
    );

    let app_clone = app.clone();
    let gen_result = claude_code_service::run(
        &claude_path,
        &refine_prompt,
        build_dir,
        model_flag,
        "refine",
        move |event| handle_claude_event(&app_clone, &event),
        cancel_watch.clone(),
    ).await;

    if is_infra_failure(&gen_result.error) {
        restore_backup(project_dir);
        return Err(gen_result.error.unwrap_or_else(|| "Claude Code CLI is unavailable".into()));
    }

    check_cancelled(&cancel_watch).map_err(|e| { restore_backup(project_dir); e })?;

    // Unlock CMakeLists.txt before build
    set_readonly(&cmake_path, false);

    // Invalidate stale CMake cache
    let cache_file = project_dir.join("build/CMakeCache.txt");
    if let Ok(cache_content) = std::fs::read_to_string(&cache_file) {
        if !cache_content.contains(&project_dir.to_string_lossy().to_string()) {
            let _ = std::fs::remove_dir_all(project_dir.join("build"));
        }
    }

    let can_skip_configure = cache_file.exists();

    // Build loop (capped at 3 attempts for refine)
    emit_step(app, "compiling");
    emit_log(app, "START: Compiling refined plugin...", Some("active"));

    if let Err(e) = run_build_loop_with_skip(
        &claude_path,
        project_dir,
        model_flag,
        app,
        cancel_watch.clone(),
        Some(3),
        can_skip_configure,
    ).await {
        restore_backup(project_dir);
        return Err(e);
    }

    check_cancelled(&cancel_watch).map_err(|e| { restore_backup(project_dir); e })?;

    // Install
    emit_step(app, "installing");
    emit_log(app, "START: Installing refined plugin...", Some("active"));

    let formats = config.plugin.formats.clone();
    let install_paths = install_plugin(project_dir, &config.plugin.name, &formats)
        .map_err(|e| { restore_backup(project_dir); e })?;

    // Clean backup
    let _ = std::fs::remove_dir_all(&source_backup);

    // Create new version
    let version_number = config.plugin.current_version + 1;
    let archived_dir = archive_build(project_dir, &config.plugin.id, version_number);

    let new_version = PluginVersion {
        id: uuid::Uuid::new_v4().to_string(),
        plugin_id: config.plugin.id.clone(),
        version_number,
        prompt: config.modification.clone(),
        created_at: chrono::Utc::now().to_rfc3339(),
        build_directory: archived_dir.clone(),
        install_paths: install_paths.clone(),
        icon_color: config.plugin.icon_color.clone(),
        is_active: true,
        agent: config.plugin.agent.clone(),
        model: config.plugin.model.clone(),
        telemetry_id: None,
    };

    let mut updated = config.plugin.clone();
    updated.install_paths = install_paths;
    updated.prompt = format!("{}\n-> {}", config.plugin.prompt, config.modification);
    updated.status = crate::models::plugin::PluginStatus::Installed;
    updated.build_directory = archived_dir;
    updated.current_version = version_number;

    let mut versions: Vec<PluginVersion> = updated.versions.iter().map(|v| {
        let mut copy = v.clone();
        copy.is_active = false;
        copy
    }).collect();
    versions.push(new_version);
    updated.versions = versions;

    // Save to library
    let mut plugins = plugin_manager::load_plugins().unwrap_or_default();
    if let Some(pos) = plugins.iter().position(|p| p.id == updated.id) {
        plugins[pos] = updated.clone();
    }
    plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;

    Ok(updated)
}

// ---- Build Loop ----

async fn run_build_loop(
    claude_path: &str,
    project_dir: &Path,
    model_flag: &str,
    app: &AppHandle,
    cancel_watch: tokio::sync::watch::Receiver<bool>,
    max_attempts: Option<i32>,
) -> Result<(), String> {
    run_build_loop_with_skip(claude_path, project_dir, model_flag, app, cancel_watch, max_attempts, false).await
}

async fn run_build_loop_with_skip(
    claude_path: &str,
    project_dir: &Path,
    model_flag: &str,
    app: &AppHandle,
    cancel_watch: tokio::sync::watch::Receiver<bool>,
    max_attempts: Option<i32>,
    initial_skip_configure: bool,
) -> Result<(), String> {
    let mut attempt = 0;

    loop {
        check_cancelled(&cancel_watch)?;

        attempt += 1;

        if let Some(max) = max_attempts {
            if attempt > max {
                return Err(format!("Build failed after {} attempts", max));
            }
        }

        let _ = app.emit("pipeline:build_attempt", BuildAttemptEvent { attempt });

        let skip = initial_skip_configure || attempt > 1;
        let result = build_runner::build(project_dir, skip).await
            .map_err(|e| e.to_string())?;

        if result.success {
            if build_runner::smoke_test(project_dir) {
                return Ok(());
            }

            // Smoke test failed — fix and retry
            emit_log(app, "Build succeeded but smoke test failed — fixing...", Some("active"));
            emit_step(app, "generatingDSP");

            let app_clone = app.clone();
            let project_dir_str = project_dir.to_string_lossy().to_string();
            claude_code_service::fix(
                claude_path,
                "Build succeeded but smoke test failed: plugin bundles are missing or invalid.",
                &project_dir_str,
                attempt,
                model_flag,
                move |event| handle_claude_event(&app_clone, &event),
                cancel_watch.clone(),
            ).await;

            emit_step(app, "compiling");
            continue;
        }

        // Build failed — fix and retry
        emit_log(app, &format!("Build attempt {} failed — fixing errors...", attempt), Some("active"));
        emit_step(app, "generatingDSP");

        let app_clone = app.clone();
        let project_dir_str = project_dir.to_string_lossy().to_string();
        claude_code_service::fix(
            claude_path,
            &result.errors,
            &project_dir_str,
            attempt,
            model_flag,
            move |event| handle_claude_event(&app_clone, &event),
            cancel_watch.clone(),
        ).await;

        emit_step(app, "compiling");
    }
}

// ---- Plugin Installation ----

fn install_plugin(
    build_dir: &Path,
    _plugin_name: &str,
    formats: &[PluginFormat],
) -> Result<InstallPaths, String> {
    let build_output = build_dir.join("build");
    let mut install_paths = InstallPaths { au: None, vst3: None };
    let mut commands = Vec::new();

    for format in formats {
        let (_ext, dest_dir, path_field_is_au) = match format {
            PluginFormat::Au => (".component", "/Library/Audio/Plug-Ins/Components", true),
            PluginFormat::Vst3 => (".vst3", "/Library/Audio/Plug-Ins/VST3", false),
        };

        let fmt_str = match format {
            PluginFormat::Au => "AU",
            PluginFormat::Vst3 => "VST3",
        };
        if let Some(bundle_path) = build_runner::locate_bundle(&build_output, fmt_str) {
            let bundle_name = bundle_path.file_name().unwrap().to_string_lossy();
            let dest = format!("{}/{}", dest_dir, bundle_name);

            commands.push(format!("rm -rf \"{}\"", dest));
            commands.push(format!("ditto \"{}\" \"{}\"", bundle_path.display(), dest));
            commands.push(format!("xattr -cr \"{}\"", dest));
            commands.push(format!("codesign --deep --force --sign - \"{}\"", dest));

            if path_field_is_au {
                install_paths.au = Some(dest);
            } else {
                install_paths.vst3 = Some(dest);
            }
        }
    }

    if commands.is_empty() {
        return Err("No plugin bundles found in build output".into());
    }

    // Add AudioComponentRegistrar refresh
    commands.push("killall -9 AudioComponentRegistrar 2>/dev/null || true".into());

    let script = commands.join(" && ");
    let apple_script = format!(
        "do shell script \"{}\" with administrator privileges",
        script.replace('\\', "\\\\").replace('"', "\\\"")
    );

    let output = std::process::Command::new("osascript")
        .args(["-e", &apple_script])
        .output()
        .map_err(|e| format!("Failed to run install script: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Installation failed: {}", stderr));
    }

    Ok(install_paths)
}

// ---- Helpers ----

fn handle_claude_event(app: &AppHandle, event: &claude_code_service::ClaudeEvent) {
    match event {
        claude_code_service::ClaudeEvent::ToolUse { tool, file_path, detail } => {
            let lower = tool.to_lowercase();
            let target = file_path.as_deref().unwrap_or("…");
            let suffix = detail.as_deref().map(|d| format!(" {}", d)).unwrap_or_default();

            if lower.contains("write") {
                emit_log(app, &format!("WRITE {}{}", target, suffix), None);
            } else if lower.contains("edit") || lower.contains("str_replace") {
                emit_log(app, &format!("EDIT {}{}", target, suffix), None);
            } else if lower.contains("read") {
                if let Some(name) = file_path.as_deref().and_then(|p| Path::new(p).file_name()) {
                    emit_log(app, &format!("READ {}", name.to_string_lossy()), None);
                }
            } else if lower.contains("bash") || lower.contains("execute") {
                if let Some(cmd) = detail.as_deref() {
                    emit_log(app, &format!("$ {}", cmd), None);
                }
            }
        }
        claude_code_service::ClaudeEvent::ToolResult { tool, output } => {
            let lower = tool.to_lowercase();
            if lower.contains("bash") || lower.contains("execute") {
                for line in output.lines().take(8) {
                    let trimmed = line.trim();
                    if !trimmed.is_empty() {
                        emit_log(app, trimmed, None);
                    }
                }
            }
        }
        claude_code_service::ClaudeEvent::Text(text) => {
            for line in text.lines() {
                let trimmed = line.trim();
                if trimmed.len() > 2 {
                    emit_log(app, trimmed, None);
                }
            }
        }
        claude_code_service::ClaudeEvent::Error(msg) => {
            emit_log(app, &format!("ERROR: {}", msg), Some("error"));
        }
        claude_code_service::ClaudeEvent::Result { success } => {
            if !*success {
                emit_log(app, "Agent run ended with errors", Some("active"));
            }
        }
    }
}

fn check_cancelled(cancel_watch: &tokio::sync::watch::Receiver<bool>) -> Result<(), String> {
    if *cancel_watch.borrow() {
        Err("Cancelled".into())
    } else {
        Ok(())
    }
}

fn resolve_formats(format: &str) -> Vec<PluginFormat> {
    match format.to_uppercase().as_str() {
        "AU" => vec![PluginFormat::Au],
        "VST3" => vec![PluginFormat::Vst3],
        _ => vec![PluginFormat::Au, PluginFormat::Vst3],
    }
}

fn archive_build(project_dir: &Path, plugin_id: &str, version: i32) -> Option<String> {
    let versions_dir = foundry_paths::application_support_dir()
        .join("PluginBuilds")
        .join(plugin_id)
        .join(format!("v{}", version));

    if let Err(e) = copy_dir_all(project_dir, &versions_dir) {
        log::error!("Failed to archive build: {}", e);
        return None;
    }

    Some(versions_dir.to_string_lossy().to_string())
}

fn copy_dir_all(src: &Path, dst: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        let dest = dst.join(entry.file_name());
        if ty.is_dir() {
            copy_dir_all(&entry.path(), &dest)?;
        } else {
            std::fs::copy(entry.path(), dest)?;
        }
    }
    Ok(())
}

fn set_readonly(path: &Path, readonly: bool) {
    if let Ok(metadata) = std::fs::metadata(path) {
        let mut perms = metadata.permissions();
        perms.set_readonly(readonly);
        let _ = std::fs::set_permissions(path, perms);
    }
}

fn is_infra_failure(error: &Option<String>) -> bool {
    if let Some(msg) = error {
        let lower = msg.to_lowercase();
        lower.contains("not available") || lower.contains("failed to launch") || lower.contains("command not found")
    } else {
        false
    }
}

fn rand_index(max: usize) -> usize {
    (uuid::Uuid::new_v4().as_bytes()[0] as usize) % max
}
