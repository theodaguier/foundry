use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::Path;
use tauri::{AppHandle, Emitter};

use crate::models::agent::{AgentModel, GenerationAgent};
use crate::models::config::{GenerationConfig, RefineConfig};
use crate::models::plugin::{InstallPaths, Plugin, PluginFormat, PluginVersion};
use crate::models::telemetry::TelemetryBuilder;
use crate::services::{
    agent_service, build_environment, build_runner, claude_code_service, foundry_paths,
    model_catalog, plugin_manager, project_assembler, telemetry_service,
};

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

#[derive(Clone, serde::Serialize)]
struct StreamingEvent {
    text: String,
}

#[derive(Clone, serde::Serialize)]
struct NameEvent {
    name: String,
}

#[derive(Clone, serde::Serialize)]
struct ErrorEvent {
    message: String,
}

#[derive(Clone, serde::Serialize)]
struct CompleteEvent {
    plugin: Plugin,
}

#[derive(Clone, serde::Serialize)]
struct BuildAttemptEvent {
    attempt: i32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct CreativeProfile {
    signature_interaction: &'static str,
    control_strategy: &'static str,
    ui_direction: &'static str,
    sonic_hook: &'static str,
    contrast_detail: &'static str,
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
            style: style.map(|s| s.into()),
        },
    );
}

fn emit_streaming(app: &AppHandle, text: &str) {
    let _ = app.emit("pipeline:streaming", StreamingEvent { text: text.into() });
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

    let telemetry_agent = config.agent.clone();
    let telemetry_model = config.model.clone();
    let mut tb = TelemetryBuilder::new(
        "generate",
        &config.prompt,
        &telemetry_agent,
        &telemetry_model,
    );
    tb.format = Some(config.format.clone());
    tb.channel_layout = Some(config.channel_layout.clone());

    match execute_generation(config, &app, cancel_watch, &mut tb).await {
        Ok(plugin) => {
            tb.plugin_id = Some(plugin.id.clone());
            tb.version_number = Some(1);
            let telemetry = tb.build();
            save_telemetry(&app, &telemetry);
            let plugin = sync_plugin_generation_metadata(
                &plugin.id,
                telemetry.version_number.unwrap_or(1),
                &telemetry.id,
                &telemetry_agent,
                &telemetry_model,
            )
            .unwrap_or(plugin);
            let _ = app.emit("pipeline:complete", CompleteEvent { plugin });
        }
        Err(e) => {
            if e == "Cancelled" {
                tb.cancel();
            } else {
                // failure_stage should already be set by execute_generation
                if tb.failure_stage.is_none() {
                    tb.fail("unknown", &e);
                }
                let _ = app.emit("pipeline:error", ErrorEvent { message: e });
            }
            let telemetry = tb.build();
            save_telemetry(&app, &telemetry);
        }
    }
}

async fn execute_generation(
    config: GenerationConfig,
    app: &AppHandle,
    cancel_watch: tokio::sync::watch::Receiver<bool>,
    tb: &mut TelemetryBuilder,
) -> Result<Plugin, String> {
    // Resolve agent CLI path (Claude Code or Codex)
    let agent_name = &config.agent;
    let agent_display = agent_service::agent_display_name(agent_name);
    let cli_path = agent_service::resolve_agent_path(agent_name).ok_or_else(|| {
        format!(
            "{} CLI is not available. Open Setup and install it.",
            agent_display
        )
    })?;

    let model_flag = &config.model;
    let environment = build_environment::prepare_build_environment(false, None).await?;
    if environment.state != "ready" {
        let message = build_environment::format_blocked_message(&environment);
        tb.fail("environment", &message);
        return Err(message);
    }
    let resolved_juce_path = environment
        .juce_path
        .clone()
        .ok_or_else(|| "Build environment is ready but JUCE path is missing.".to_string())?;
    tb.juce_version = Some(environment.juce_version.clone());

    // Step 1: Prepare project — name gen + assembly in parallel
    emit_step(app, "preparingProject");
    emit_log(app, "START: Preparing project...", Some("active"));

    let existing_plugins = plugin_manager::load_plugins().unwrap_or_default();
    let existing_names: Vec<String> = existing_plugins.iter().map(|p| p.name.clone()).collect();

    // Generate the plugin name locally so the UI can show it immediately.
    emit_log(app, "Generating plugin name...", None);
    let plugin_name = generate_local_plugin_name(&config.prompt, &existing_names);
    emit_log(app, &format!("Plugin name: {}", plugin_name), None);
    let _ = app.emit(
        "pipeline:name",
        NameEvent {
            name: plugin_name.clone(),
        },
    );

    emit_log(app, "Assembling project files...", None);
    let project = project_assembler::assemble(
        &config.prompt,
        &plugin_name,
        &config.format,
        &config.channel_layout,
        config.preset_count,
        &config.model,
        Path::new(&resolved_juce_path),
    )?;

    emit_log(
        app,
        "PREPARING PROJECT: Dependencies resolved.",
        Some("success"),
    );

    check_cancelled(&cancel_watch)?;

    // Step 2: Generate code in a single self-contained pass for speed.
    emit_step(app, "generatingDSP");
    emit_log(app, "START: Generating plugin code...", Some("active"));
    tb.start_generation();

    let plugin_type = &project.plugin_type;
    let plugin_role = match plugin_type.as_str() {
        "instrument" => "playable instrument",
        "utility" => "utility or analysis tool",
        _ => "audio effect",
    };

    let project_dir_str = project.directory.to_string_lossy().to_string();

    let creative_profile = infer_creative_profile(&plugin_name, plugin_type, &config.prompt);

    emit_log(
        app,
        &format!(
            "── {} · {}: DSP pass ──",
            agent_display.to_lowercase(),
            model_flag
        ),
        Some("active"),
    );
    let processor_prompt = build_fast_processor_prompt(
        &plugin_name,
        plugin_role,
        plugin_type,
        &config.prompt,
        &config.channel_layout,
        &creative_profile,
    );

    let app_clone = app.clone();
    let processor_result = agent_service::run(
        agent_name,
        &cli_path,
        &processor_prompt,
        &project_dir_str,
        model_flag,
        "generate_processor",
        move |event| handle_claude_event(&app_clone, &event),
        cancel_watch.clone(),
    )
    .await;

    tb.accumulate_run(&processor_result);

    if is_infra_failure(&processor_result.error) {
        tb.fail(
            "generation",
            processor_result
                .error
                .as_deref()
                .unwrap_or("CLI unavailable"),
        );
        return Err(processor_result
            .error
            .unwrap_or_else(|| "Claude Code CLI is unavailable".into()));
    }

    let mut processor_missing: Vec<&str> =
        ["Source/PluginProcessor.h", "Source/PluginProcessor.cpp"]
            .into_iter()
            .filter(|path| !project.directory.join(path).exists())
            .collect();

    if !processor_missing.is_empty() {
        emit_log(
            app,
            &format!(
                "DSP pass incomplete — attempting recovery before UI pass. Missing: {}",
                processor_missing.join(", ")
            ),
            Some("active"),
        );

        let repair_prompt = build_generation_repair_prompt(
            &plugin_name,
            plugin_role,
            &config.prompt,
            &config.channel_layout,
            &processor_missing,
            &[],
        );

        let app_clone = app.clone();
        let repair_result = agent_service::run(
            agent_name,
            &cli_path,
            &repair_prompt,
            &project_dir_str,
            model_flag,
            "repair_generation",
            move |event| handle_claude_event(&app_clone, &event),
            cancel_watch.clone(),
        )
        .await;

        tb.accumulate_run(&repair_result);

        if is_infra_failure(&repair_result.error) {
            tb.fail(
                "generation",
                repair_result.error.as_deref().unwrap_or("CLI unavailable"),
            );
            return Err(repair_result
                .error
                .unwrap_or_else(|| "Claude Code CLI is unavailable".into()));
        }

        processor_missing = ["Source/PluginProcessor.h", "Source/PluginProcessor.cpp"]
            .into_iter()
            .filter(|path| !project.directory.join(path).exists())
            .collect();
    }

    if !processor_missing.is_empty() {
        let message = format!(
            "DSP pass did not create processor files: {}",
            processor_missing.join(", ")
        );
        tb.fail("generation", &message);
        return Err(message);
    }

    check_cancelled(&cancel_watch)?;

    emit_step(app, "generatingUI");
    emit_log(
        app,
        &format!(
            "── {} · {}: UI pass ──",
            agent_display.to_lowercase(),
            model_flag
        ),
        Some("active"),
    );
    let parameter_manifest = extract_parameter_manifest(&project.directory);
    let ui_prompt = build_fast_ui_prompt(
        &plugin_name,
        plugin_role,
        plugin_type,
        &config.prompt,
        &config.channel_layout,
        &creative_profile,
        &parameter_manifest,
    );

    let app_clone = app.clone();
    let mut ui_result = agent_service::run(
        agent_name,
        &cli_path,
        &ui_prompt,
        &project_dir_str,
        model_flag,
        "generate_ui",
        move |event| handle_claude_event(&app_clone, &event),
        cancel_watch.clone(),
    )
    .await;

    if matches!(
        ui_result.error.as_deref(),
        Some(message) if message.contains("No write activity detected")
    ) {
        emit_log(
            app,
            "UI pass stalled before writing files — retrying with emergency prompt...",
            Some("active"),
        );

        let emergency_ui_prompt =
            build_emergency_ui_prompt(&plugin_name, &parameter_manifest, &creative_profile);
        let app_clone = app.clone();
        ui_result = agent_service::run(
            agent_name,
            &cli_path,
            &emergency_ui_prompt,
            &project_dir_str,
            model_flag,
            "generate_ui",
            move |event| handle_claude_event(&app_clone, &event),
            cancel_watch.clone(),
        )
        .await;
    }

    tb.accumulate_run(&ui_result);
    tb.end_generation();
    tb.plugin_type = Some(plugin_type.clone());

    if is_infra_failure(&ui_result.error) {
        tb.fail(
            "generation",
            ui_result.error.as_deref().unwrap_or("CLI unavailable"),
        );
        return Err(ui_result
            .error
            .unwrap_or_else(|| "Claude Code CLI is unavailable".into()));
    }

    let missing_files = missing_required_source_files(&project.directory);
    let validation_issues = validate_generated_source_tree(&project.directory, &plugin_name);

    if !missing_files.is_empty() || !validation_issues.is_empty() {
        emit_log(
            app,
            &format!(
                "Generation needs repair — missing files: {} · validation issues: {}",
                if missing_files.is_empty() {
                    "none".to_string()
                } else {
                    missing_files.join(", ")
                },
                if validation_issues.is_empty() {
                    "none".to_string()
                } else {
                    validation_issues.join(" | ")
                }
            ),
            Some("active"),
        );

        let repair_prompt = build_generation_repair_prompt(
            &plugin_name,
            plugin_role,
            &config.prompt,
            &config.channel_layout,
            &missing_files,
            &validation_issues,
        );

        let app_clone = app.clone();
        let repair_result = agent_service::run(
            agent_name,
            &cli_path,
            &repair_prompt,
            &project_dir_str,
            model_flag,
            "repair_generation",
            move |event| handle_claude_event(&app_clone, &event),
            cancel_watch.clone(),
        )
        .await;

        tb.accumulate_run(&repair_result);

        if is_infra_failure(&repair_result.error) {
            tb.fail(
                "generation",
                repair_result.error.as_deref().unwrap_or("CLI unavailable"),
            );
            return Err(repair_result
                .error
                .unwrap_or_else(|| "Claude Code CLI is unavailable".into()));
        }

        let missing_files = missing_required_source_files(&project.directory);
        let validation_issues = validate_generated_source_tree(&project.directory, &plugin_name);
        if !missing_files.is_empty() || !validation_issues.is_empty() {
            let message = format!(
                "Generated source tree is still invalid after recovery. Missing: {}. Validation: {}",
                if missing_files.is_empty() {
                    "none".to_string()
                } else {
                    missing_files.join(", ")
                },
                if validation_issues.is_empty() {
                    "none".to_string()
                } else {
                    validation_issues.join(" | ")
                }
            );
            tb.fail("generation", &message);
            return Err(message);
        }
    }

    check_cancelled(&cancel_watch)?;

    emit_log(
        app,
        "GENERATING: Code generation complete.",
        Some("success"),
    );

    // Step 3: Build loop (audit rules are now embedded in generation prompt)
    emit_step(app, "compiling");
    emit_log(app, "START: Compiling plugin...", Some("active"));
    tb.start_build();

    run_build_loop(
        agent_name,
        &cli_path,
        &project.directory,
        model_flag,
        app,
        tb,
        cancel_watch.clone(),
        None, // unlimited attempts
    )
    .await?;

    check_cancelled(&cancel_watch)?;

    tb.end_build();
    emit_log(app, "COMPILING: Build artifacts ready.", Some("success"));

    // Step 4: Install
    emit_step(app, "installing");
    emit_log(app, "START: Installing plugin...", Some("active"));
    tb.start_install();

    let formats = resolve_formats(&config.format);
    let install_paths = install_plugin(&project.directory, &plugin_name, &formats)?;

    tb.end_install();
    emit_log(app, "INSTALLING: Plugin bundle staged.", Some("success"));

    // Archive build directory
    let plugin_id = uuid::Uuid::new_v4().to_string();
    let archived_dir = archive_build(&project.directory, &plugin_id, 1);

    // Build plugin object
    let colors = [
        "#C8C4BC", "#A8B4A0", "#B0A898", "#9CAAB8", "#B8A8B0", "#A0A8B0",
    ];
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

    let refine_agent = preferred_plugin_agent_name(&config.plugin);
    let model_str = preferred_plugin_model_flag(&config.plugin);
    let mut tb = TelemetryBuilder::new("refine", &config.modification, &refine_agent, &model_str);
    tb.plugin_id = Some(config.plugin.id.clone());
    tb.version_number = Some(config.plugin.current_version + 1);

    match execute_refine(config, &app, cancel_watch, &mut tb).await {
        Ok(plugin) => {
            let telemetry = tb.build();
            save_telemetry(&app, &telemetry);
            let plugin = sync_plugin_generation_metadata(
                &plugin.id,
                telemetry.version_number.unwrap_or(plugin.current_version),
                &telemetry.id,
                &refine_agent,
                &model_str,
            )
            .unwrap_or(plugin);
            let _ = app.emit("pipeline:complete", CompleteEvent { plugin });
        }
        Err(e) => {
            if e == "Cancelled" {
                tb.cancel();
            } else if tb.failure_stage.is_none() {
                tb.fail("unknown", &e);
            }
            let telemetry = tb.build();
            save_telemetry(&app, &telemetry);
            if e != "Cancelled" {
                let _ = app.emit("pipeline:error", ErrorEvent { message: e });
            }
        }
    }
}

fn save_telemetry(app: &AppHandle, telemetry: &crate::models::telemetry::GenerationTelemetry) {
    use tauri::Manager;
    if let Some(state) = app.try_state::<crate::state::AppState>() {
        telemetry_service::save(telemetry, &state.auth);
    } else {
        // No state available — save locally only
        telemetry_service::save(
            telemetry,
            &crate::services::auth_service::SupabaseAuth::new(),
        );
    }
}

async fn execute_refine(
    config: RefineConfig,
    app: &AppHandle,
    cancel_watch: tokio::sync::watch::Receiver<bool>,
    tb: &mut TelemetryBuilder,
) -> Result<Plugin, String> {
    // Resolve agent CLI — refine uses the agent that built the original plugin
    let refine_agent = preferred_plugin_agent_name(&config.plugin);
    let refine_display = agent_service::agent_display_name(&refine_agent);
    let cli_path = agent_service::resolve_agent_path(&refine_agent)
        .ok_or_else(|| format!("{} CLI is not available", refine_display))?;

    let build_dir = config
        .plugin
        .build_directory
        .as_deref()
        .ok_or_else(|| "No build directory found - cannot refine this plugin".to_string())?;

    if !Path::new(build_dir).exists() {
        return Err(format!("Build directory no longer exists: {}", build_dir));
    }

    let project_dir = Path::new(build_dir);
    let model_flag = preferred_plugin_model_flag(&config.plugin);

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
    tb.start_generation();

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
    let gen_result = agent_service::run(
        &refine_agent,
        &cli_path,
        &refine_prompt,
        build_dir,
        &model_flag,
        "refine",
        move |event| handle_claude_event(&app_clone, &event),
        cancel_watch.clone(),
    )
    .await;

    tb.accumulate_run(&gen_result);
    tb.end_generation();

    if is_infra_failure(&gen_result.error) {
        tb.fail(
            "generation",
            gen_result.error.as_deref().unwrap_or("CLI unavailable"),
        );
        restore_backup(project_dir);
        return Err(gen_result
            .error
            .unwrap_or_else(|| "Claude Code CLI is unavailable".into()));
    }

    check_cancelled(&cancel_watch).map_err(|e| {
        restore_backup(project_dir);
        e
    })?;

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
    tb.start_build();

    if let Err(e) = run_build_loop_with_skip(
        &refine_agent,
        &cli_path,
        project_dir,
        &model_flag,
        app,
        tb,
        cancel_watch.clone(),
        Some(3),
        can_skip_configure,
    )
    .await
    {
        tb.end_build();
        if tb.failure_stage.is_none() {
            tb.fail("build", &e);
        }
        restore_backup(project_dir);
        return Err(e);
    }
    tb.end_build();

    check_cancelled(&cancel_watch).map_err(|e| {
        restore_backup(project_dir);
        e
    })?;

    // Install
    emit_step(app, "installing");
    emit_log(app, "START: Installing refined plugin...", Some("active"));
    tb.start_install();

    let formats = config.plugin.formats.clone();
    let install_paths =
        install_plugin(project_dir, &config.plugin.name, &formats).map_err(|e| {
            tb.fail("install", &e);
            restore_backup(project_dir);
            e
        })?;
    tb.end_install();

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

    let mut versions: Vec<PluginVersion> = updated
        .versions
        .iter()
        .map(|v| {
            let mut copy = v.clone();
            copy.is_active = false;
            copy
        })
        .collect();
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

fn preferred_plugin_agent_name(plugin: &Plugin) -> String {
    match &plugin.agent {
        Some(GenerationAgent::Codex) => "Codex".to_string(),
        Some(GenerationAgent::ClaudeCode) => "Claude Code".to_string(),
        None => plugin
            .model
            .as_ref()
            .map(|model| model.flag.to_ascii_lowercase())
            .filter(|flag| flag.contains("gpt") || flag.contains("codex"))
            .map(|_| "Codex".to_string())
            .unwrap_or_else(|| "Claude Code".to_string()),
    }
}

fn preferred_plugin_model_flag(plugin: &Plugin) -> String {
    plugin
        .model
        .as_ref()
        .map(|model| model.flag.clone())
        .unwrap_or_else(|| {
            if matches!(plugin.agent, Some(GenerationAgent::Codex)) {
                "gpt-5.4".to_string()
            } else {
                "sonnet".to_string()
            }
        })
}

fn canonical_agent_id(agent: &str) -> &'static str {
    if agent.to_ascii_lowercase().contains("codex") {
        "codex"
    } else {
        "claude-code"
    }
}

fn generation_agent_from_name(agent: &str) -> GenerationAgent {
    if canonical_agent_id(agent) == "codex" {
        GenerationAgent::Codex
    } else {
        GenerationAgent::ClaudeCode
    }
}

fn resolve_agent_model(agent: &str, model_flag: &str) -> AgentModel {
    let provider_id = canonical_agent_id(agent);
    if let Ok(catalog) = model_catalog::load_catalog() {
        if let Some(model) = catalog
            .into_iter()
            .find(|provider| provider.id == provider_id || provider.name == agent)
            .and_then(|provider| {
                provider
                    .models
                    .into_iter()
                    .find(|model| model.flag == model_flag || model.id == model_flag)
            })
        {
            return model;
        }
    }

    AgentModel {
        id: model_flag.to_string(),
        name: model_flag.to_string(),
        subtitle: String::new(),
        flag: model_flag.to_string(),
        default: None,
    }
}

fn sync_plugin_generation_metadata(
    plugin_id: &str,
    version_number: i32,
    telemetry_id: &str,
    agent: &str,
    model_flag: &str,
) -> Option<Plugin> {
    let resolved_agent = generation_agent_from_name(agent);
    let resolved_model = resolve_agent_model(agent, model_flag);

    let mut plugins = plugin_manager::load_plugins().ok()?;
    let plugin = plugins.iter_mut().find(|plugin| plugin.id == plugin_id)?;

    plugin.agent = Some(resolved_agent.clone());
    plugin.model = Some(resolved_model.clone());

    if let Some(version) = plugin
        .versions
        .iter_mut()
        .find(|version| version.version_number == version_number)
    {
        version.agent = Some(resolved_agent);
        version.model = Some(resolved_model);
        version.telemetry_id = Some(telemetry_id.to_string());
    }

    let updated = plugin.clone();
    plugin_manager::save_plugins(&plugins).ok()?;
    Some(updated)
}

// ---- Build Loop ----

async fn run_build_loop(
    agent: &str,
    cli_path: &str,
    project_dir: &Path,
    model_flag: &str,
    app: &AppHandle,
    tb: &mut TelemetryBuilder,
    cancel_watch: tokio::sync::watch::Receiver<bool>,
    max_attempts: Option<i32>,
) -> Result<(), String> {
    run_build_loop_with_skip(
        agent,
        cli_path,
        project_dir,
        model_flag,
        app,
        tb,
        cancel_watch,
        max_attempts,
        false,
    )
    .await
}

async fn run_build_loop_with_skip(
    agent: &str,
    cli_path: &str,
    project_dir: &Path,
    model_flag: &str,
    app: &AppHandle,
    tb: &mut TelemetryBuilder,
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
        if !skip {
            emit_log(app, "CMake: Configuring project...", None);
        }
        emit_log(
            app,
            &format!("CMake: Building (attempt {})...", attempt),
            None,
        );
        tb.start_build_attempt();

        let result = build_runner::build(project_dir, skip)
            .await
            .map_err(|e| e.to_string())?;

        if result.success {
            emit_log(app, "Build succeeded — running smoke test...", None);
            if build_runner::smoke_test(project_dir) {
                tb.end_build_attempt(attempt, true, None);
                emit_log(app, "Smoke test passed ✓", Some("success"));
                return Ok(());
            }

            // Smoke test failed — fix and retry
            tb.end_build_attempt(
                attempt,
                false,
                Some("Build succeeded but smoke test failed".into()),
            );
            emit_log(
                app,
                "Build succeeded but smoke test failed — fixing...",
                Some("active"),
            );
            emit_step(app, "generatingDSP");

            let app_clone = app.clone();
            let project_dir_str = project_dir.to_string_lossy().to_string();
            emit_log(
                app,
                "COMPILER CHECK · build finished but no usable plugin bundle was found",
                Some("error"),
            );

            let fix_result = agent_service::fix(
                agent,
                cli_path,
                "Build succeeded but smoke test failed: plugin bundles are missing or invalid.",
                &project_dir_str,
                attempt,
                model_flag,
                move |event| handle_claude_event(&app_clone, &event),
                cancel_watch.clone(),
            )
            .await;

            if let Some(error) = fix_result.error {
                return Err(error);
            }

            if !fix_result.success {
                return Err("Fix pass failed after smoke test failure".into());
            }

            emit_step(app, "compiling");
            continue;
        }

        // Build failed — surface compiler errors, then fix and retry
        tb.end_build_attempt(
            attempt,
            false,
            Some(summarize_error_snippet(&result.errors)),
        );
        if matches!(
            result.failure_stage,
            Some(build_runner::BuildFailureStage::EnvironmentConfig)
        ) {
            emit_log(
                app,
                "Build blocked by environment configuration — not sending this failure to Claude.",
                Some("error"),
            );
            emit_log(app, "COMPILER ERRORS ↓", Some("error"));
            for line in result.errors.lines().take(8) {
                let trimmed = line.trim();
                if !trimmed.is_empty() {
                    emit_log(app, &format!("  {}", trimmed), Some("error"));
                }
            }
            tb.fail("environment", &result.errors);
            return Err(result.errors);
        }
        emit_log(
            app,
            &format!("Build attempt {} failed — fixing errors...", attempt),
            Some("active"),
        );
        emit_log(app, "COMPILER ERRORS ↓", Some("error"));
        for line in result.errors.lines().take(8) {
            let trimmed = line.trim();
            if !trimmed.is_empty() {
                emit_log(app, &format!("  {}", trimmed), Some("error"));
            }
        }
        emit_step(app, "generatingDSP");

        let app_clone = app.clone();
        let project_dir_str = project_dir.to_string_lossy().to_string();
        let fix_result = agent_service::fix(
            agent,
            cli_path,
            &result.errors,
            &project_dir_str,
            attempt,
            model_flag,
            move |event| handle_claude_event(&app_clone, &event),
            cancel_watch.clone(),
        )
        .await;

        if let Some(error) = fix_result.error {
            return Err(error);
        }

        if !fix_result.success {
            return Err(format!("Fix pass failed after build attempt {}.", attempt));
        }

        emit_step(app, "compiling");
    }
}

// ---- Plugin Installation ----

fn install_plugin(
    build_dir: &Path,
    _plugin_name: &str,
    formats: &[PluginFormat],
) -> Result<InstallPaths, String> {
    use crate::platform;

    let build_output = build_dir.join("build");
    let mut install_paths = InstallPaths {
        au: None,
        vst3: None,
    };
    let mut operations = Vec::new();

    for format in formats {
        let fmt_str = match format {
            PluginFormat::Au => "AU",
            PluginFormat::Vst3 => "VST3",
        };

        if let Some(bundle_path) = build_runner::locate_bundle(&build_output, fmt_str) {
            let install_dir = platform::plugin_install_dir(format);
            let bundle_name = bundle_path.file_name().unwrap().to_string_lossy();
            let dest = install_dir.path.join(bundle_name.as_ref());

            operations.push(platform::types::InstallOperation {
                format: format.clone(),
                source: bundle_path,
                destination: dest.clone(),
            });

            let dest_str = dest.to_string_lossy().to_string();
            match format {
                PluginFormat::Au => install_paths.au = Some(dest_str),
                PluginFormat::Vst3 => install_paths.vst3 = Some(dest_str),
            }
        }
    }

    if operations.is_empty() {
        return Err("No plugin bundles found in build output".into());
    }

    platform::install_plugin_bundles(&operations)?;
    platform::post_install_refresh()?;

    Ok(install_paths)
}

// ---- Helpers ----

fn handle_claude_event(app: &AppHandle, event: &claude_code_service::ClaudeEvent) {
    fn display_target(file_path: Option<&str>) -> String {
        file_path
            .and_then(|p| {
                Path::new(p)
                    .file_name()
                    .map(|n| n.to_string_lossy().to_string())
            })
            .unwrap_or_else(|| "unknown-target".to_string())
    }

    match event {
        claude_code_service::ClaudeEvent::ToolUse {
            tool,
            file_path,
            detail,
        } => {
            emit_streaming(app, "");
            let lower = tool.to_lowercase();
            let target = display_target(file_path.as_deref());
            let suffix = detail
                .as_deref()
                .map(|d| format!(" · {}", d))
                .unwrap_or_default();

            if lower.contains("write") {
                emit_log(
                    app,
                    &format!("MODEL → WRITE {}{}", target, suffix),
                    Some("active"),
                );
            } else if lower.contains("edit")
                || lower.contains("str_replace")
                || lower.contains("multi_edit")
                || lower.contains("multiedit")
            {
                emit_log(
                    app,
                    &format!("MODEL → EDIT {}{}", target, suffix),
                    Some("active"),
                );
            } else if lower.contains("read") {
                emit_log(app, &format!("MODEL → READ {}{}", target, suffix), None);
            } else if lower.contains("bash") || lower.contains("execute") {
                if let Some(cmd) = detail.as_deref() {
                    emit_log(app, &format!("MODEL → RUN {}", cmd), Some("active"));
                } else {
                    emit_log(app, "MODEL → RUN shell command", Some("active"));
                }
            } else {
                emit_log(app, &format!("MODEL → TOOL {}{}", tool, suffix), None);
            }
        }
        claude_code_service::ClaudeEvent::ToolResult { tool, output } => {
            emit_streaming(app, "");
            let lower = tool.to_lowercase();
            let label = if lower.contains("bash") || lower.contains("execute") {
                "MODEL ← COMMAND OUTPUT"
            } else if lower.contains("read") {
                "MODEL ← READ RESULT"
            } else if lower.contains("write") {
                "MODEL ← WRITE RESULT"
            } else if lower.contains("edit")
                || lower.contains("str_replace")
                || lower.contains("multi_edit")
                || lower.contains("multiedit")
            {
                "MODEL ← EDIT RESULT"
            } else {
                "MODEL ← TOOL RESULT"
            };

            let style = if output.to_lowercase().contains("error")
                || output.to_lowercase().contains("failed")
            {
                Some("error")
            } else {
                None
            };

            emit_log(app, label, style);

            for line in output.lines().take(8) {
                let trimmed = line.trim();
                if !trimmed.is_empty() {
                    emit_log(app, &format!("  {}", trimmed), style);
                }
            }
        }
        claude_code_service::ClaudeEvent::StreamingText(text) => {
            if !text.is_empty() {
                emit_streaming(app, text);
            }
        }
        claude_code_service::ClaudeEvent::Text(text) => {
            let trimmed_text = text.trim();
            if trimmed_text.starts_with("MODEL SESSION") {
                emit_streaming(app, "");
                emit_log(app, trimmed_text, Some("active"));
                return;
            }

            if trimmed_text.starts_with("Heartbeat:") {
                emit_streaming(app, "");
                emit_log(
                    app,
                    &format!("MODEL STATUS · {}", trimmed_text),
                    Some("active"),
                );
                return;
            }

            if trimmed_text.starts_with("Done —") {
                emit_streaming(app, "");
                emit_log(
                    app,
                    &format!("MODEL RESULT · {}", trimmed_text),
                    Some("success"),
                );
                return;
            }

            if trimmed_text.contains("ready") {
                emit_streaming(app, "");
                emit_log(
                    app,
                    &format!("MODEL STATUS · {}", trimmed_text),
                    Some("success"),
                );
                return;
            }

            if !trimmed_text.is_empty() {
                emit_streaming(app, "");
            }

            for line in text.lines() {
                let trimmed = line.trim();
                if trimmed.len() <= 2 {
                    continue;
                }

                emit_log(app, &format!("MODEL: {}", trimmed), None);
            }
        }
        claude_code_service::ClaudeEvent::Stderr(msg) => {
            emit_streaming(app, "");
            emit_log(app, &format!("MODEL STDERR · {}", msg), Some("error"));
        }
        claude_code_service::ClaudeEvent::Error(msg) => {
            emit_streaming(app, "");
            emit_log(app, &format!("MODEL ERROR · {}", msg), Some("error"));
        }
        claude_code_service::ClaudeEvent::Result { success } => {
            emit_streaming(app, "");
            if *success {
                emit_log(
                    app,
                    "MODEL RESULT · completed successfully",
                    Some("success"),
                );
            } else {
                emit_log(app, "MODEL RESULT · run ended with errors", Some("error"));
            }
        }
    }
}

/// Build a self-contained generation prompt with all knowledge inlined.
/// This eliminates the need for Claude to read 7 files in Turn 1.
fn build_generation_prompt(
    plugin_name: &str,
    plugin_role: &str,
    plugin_type: &str,
    user_prompt: &str,
    channel_layout: &str,
    creative_profile: &CreativeProfile,
) -> String {
    let instrument_api = if plugin_type == "instrument" {
        "\n### Synthesiser + Voice (instruments only)\n\
        synth.addSound(new MySynthSound()); synth.addVoice(new MySynthVoice());\n\
        synth.setCurrentPlaybackSampleRate(sr); synth.renderNextBlock(buffer, midi, 0, numSamples);\n\
        Voice overrides: canPlaySound(), startNote(), stopNote(), renderNextBlock(), pitchWheelMoved(), controllerMoved().\n"
    } else {
        ""
    };

    format!(
        r#"Build a JUCE {role} plugin called "{name}": {prompt}

Channel layout: {channels}. Plugin type: {ptype}.

## FILES TO CREATE
- Source/PluginProcessor.h
- Source/PluginProcessor.cpp
- Source/PluginEditor.h
- Source/PluginEditor.cpp
- Source/FoundryLookAndFeel.h

## EXECUTION PLAN
Follow these phases so progress is visible in the logs:
1. First, briefly state your plan in 3-5 short lines: DSP architecture, parameter groups, interaction concept, UI structure.
2. Then create `Source/PluginProcessor.h` and `Source/PluginProcessor.cpp`.
3. Then create `Source/FoundryLookAndFeel.h`, `Source/PluginEditor.h`, and `Source/PluginEditor.cpp`.
4. If needed, make one final targeted Edit pass.

Do not wait to finish the entire plugin before using tools. Start writing files as soon as the plan is stated.

## CREATIVE PROFILE
- Signature interaction: {signature_interaction}
- Control strategy: {control_strategy}
- UI direction: {ui_direction}
- Sonic hook: {sonic_hook}
- Contrast detail: {contrast_detail}

## INTERACTION DIVERSITY
- Avoid a flat row of generic knobs.
- Give the plugin one hero interaction that changes the character immediately.
- Include at least 3 distinct interaction patterns chosen from: rotary controls, toggle buttons, mode selectors, macro blend controls, visual feedback elements, performance controls.
- Every control must map to real DSP behavior. No cosmetic-only widgets.
- The default patch/setting should feel alive and immediately demonstrable.

## JUCE API REFERENCE
- APVTS: auto layout = juce::AudioProcessorValueTreeState::ParameterLayout();
  layout.add(std::make_unique<juce::AudioParameterFloat>(juce::ParameterID("gain", 1), "Gain", juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.5f));
- Buffer: buffer.getNumChannels(); buffer.getNumSamples(); auto* data = buffer.getWritePointer(ch);
- DSP: juce::dsp::Gain<float>, Reverb, Chorus<float>, Phaser<float>, Compressor<float>, LadderFilter<float>, StateVariableTPTFilter<float>, DelayLine<float>, Oscillator<float>, WaveShaper<float>, Oversampling<float>
{instrument_api}
## UI WIRING
- slider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
- attachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(processor.apvts, "id", slider);
- resized(): auto bounds = getLocalBounds().reduced(20); area.removeFromTop/Left/Right/Bottom

## LOOK AND FEEL
- FoundryLookAndFeel : public juce::LookAndFeel_V4
- Set in constructor: setLookAndFeel(&lookAndFeel); Clear in destructor: setLookAndFeel(nullptr);
- Declare LookAndFeel BEFORE any sliders/buttons in the header
- Override drawRotarySlider() for custom knobs

## BUILD RULES
- Processor: {name}Processor, Editor: {name}Editor
- C++17, std::make_unique, no raw new
- EVERY JUCE type uses juce:: prefix
- Font: juce::Font(juce::FontOptions(float)) — NEVER juce::Font(float)
- .h/.cpp signatures must match exactly
- Include JuceHeader.h in every file
- Linker errors = source code errors, NOT CMakeLists.txt
- juce::dsp::Reverb not juce::Reverb
- No auto* in lambda captures
- No duplicate parameter IDs
- Check denominators for division by zero
- Use getSampleRate() not hardcoded rates

## AUDIT CHECKLIST (verify BEFORE writing)
- Every APVTS parameter has a matching UI control with Attachment
- Every UI control ID matches a parameter ID exactly
- .h and .cpp method signatures are identical
- LookAndFeel declared before components in header
- All juce:: prefixes present
- No `FoundryPlugin` placeholder text remains anywhere
- `FoundryLookAndFeel` is actually used by the editor
- Build something distinctive, not just "drive / tone / mix" unless the brief explicitly asks for it

Do NOT read any files.

You must make progress visible:
- Start with a short textual plan.
- Then write files in phases, beginning with the processor files.
- Do not hold all work until one giant final burst.
- Prefer early visible writes over a single opaque completion.
"#,
        name = plugin_name,
        role = plugin_role,
        prompt = user_prompt,
        channels = channel_layout,
        ptype = plugin_type,
        instrument_api = instrument_api,
        signature_interaction = creative_profile.signature_interaction,
        control_strategy = creative_profile.control_strategy,
        ui_direction = creative_profile.ui_direction,
        sonic_hook = creative_profile.sonic_hook,
        contrast_detail = creative_profile.contrast_detail,
    )
}

fn build_fast_processor_prompt(
    plugin_name: &str,
    plugin_role: &str,
    plugin_type: &str,
    user_prompt: &str,
    channel_layout: &str,
    creative_profile: &CreativeProfile,
) -> String {
    format!(
        r#"Build the DSP foundation for a JUCE {role} plugin called "{name}".

User brief: {prompt}
Plugin type: {plugin_type}
Channel layout: {channels}

Create only:
- Source/PluginProcessor.h
- Source/PluginProcessor.cpp

Creative targets:
- Signature interaction: {signature_interaction}
- Sonic hook: {sonic_hook}

Rules:
- Start with one short sentence, then write both files immediately.
- Implement APVTS parameters and a real processBlock path.
- No dead controls.
- Make the default state obviously useful and audible.
- Use juce:: prefixes everywhere.
- Include JuceHeader.h in both files.
- Class name must be exactly {name}Processor.
- Do not create editor files.
- Do not read files.
- Do not touch CMakeLists.txt.
"#,
        role = plugin_role,
        name = plugin_name,
        prompt = user_prompt,
        plugin_type = plugin_type,
        channels = channel_layout,
        signature_interaction = creative_profile.signature_interaction,
        sonic_hook = creative_profile.sonic_hook,
    )
}

fn build_fast_ui_prompt(
    plugin_name: &str,
    plugin_role: &str,
    plugin_type: &str,
    user_prompt: &str,
    channel_layout: &str,
    creative_profile: &CreativeProfile,
    parameter_manifest: &[String],
) -> String {
    let parameter_block = if parameter_manifest.is_empty() {
        "- Parameter IDs could not be extracted automatically. Reuse the processor's existing IDs exactly and do not invent new ones.".to_string()
    } else {
        parameter_manifest
            .iter()
            .map(|entry| format!("- {}", entry))
            .collect::<Vec<_>>()
            .join("\n")
    };

    format!(
        r#"Complete the UI for the existing JUCE {role} plugin "{name}".

User brief: {prompt}
Plugin type: {plugin_type}
Channel layout: {channels}

Then create only:
- Source/FoundryLookAndFeel.h
- Source/PluginEditor.h
- Source/PluginEditor.cpp

Processor contract:
- Processor class: {name}Processor
- Editor class: {name}Editor
- Use these parameter IDs exactly:
{parameter_block}

Creative targets:
- Control strategy: {control_strategy}
- UI direction: {ui_direction}
- Contrast detail: {contrast_detail}

Rules:
- Start with one short sentence, then write the three files immediately.
- Every visible control must map to a real parameter with an APVTS attachment.
- Use FoundryLookAndFeel in the editor.
- Avoid a flat row of generic knobs; create one hero interaction zone.
- Prefer showing the 8-12 most important parameters if the processor exposes many internals.
- Use a sane landscape editor size, typically around 760-920 px wide and 420-560 px tall.
- Build the layout from `getLocalBounds().reduced(...)` plus `removeFrom*`, or use `juce::Grid` / `juce::FlexBox`; do not scatter arbitrary overlapping coordinates.
- Keep outer padding around 20-28 px and internal gaps around 12-20 px.
- Keep rotary controls square and readable, labels aligned, and widgets away from the window edges.
- Make the interface clean and balanced before it is flashy.
- Keep class name exactly {name}Editor.
- Use juce:: prefixes everywhere.
- Do not read files.
- Do not touch CMakeLists.txt.
"#,
        role = plugin_role,
        name = plugin_name,
        prompt = user_prompt,
        plugin_type = plugin_type,
        channels = channel_layout,
        control_strategy = creative_profile.control_strategy,
        ui_direction = creative_profile.ui_direction,
        contrast_detail = creative_profile.contrast_detail,
        parameter_block = parameter_block,
    )
}

fn build_emergency_ui_prompt(
    plugin_name: &str,
    parameter_manifest: &[String],
    creative_profile: &CreativeProfile,
) -> String {
    let parameter_block = if parameter_manifest.is_empty() {
        "- Reuse the processor's existing parameter IDs exactly. Do not invent new IDs.".to_string()
    } else {
        parameter_manifest
            .iter()
            .take(12)
            .map(|entry| format!("- {}", entry))
            .collect::<Vec<_>>()
            .join("\n")
    };

    format!(
        r#"Emergency UI pass for JUCE plugin "{name}".

Write these files now:
- Source/FoundryLookAndFeel.h
- Source/PluginEditor.h
- Source/PluginEditor.cpp

Known contract:
- Processor class: {name}Processor
- Editor class: {name}Editor
- Visible controls must use only these parameter IDs:
{parameter_block}

UI direction:
- {ui_direction}
- {control_strategy}

Rules:
- One short sentence, then write files immediately.
- No reading.
- No analysis.
- No explanation after writing.
- Use FoundryLookAndFeel.
- Use APVTS attachments for every visible control.
- Use a landscape editor size with a clean, non-overlapping layout.
- Derive geometry from `getLocalBounds()` with consistent padding and gaps.
- Keep the UI compact, legible, and compile-safe.
"#,
        name = plugin_name,
        parameter_block = parameter_block,
        ui_direction = creative_profile.ui_direction,
        control_strategy = creative_profile.control_strategy,
    )
}

fn check_cancelled(cancel_watch: &tokio::sync::watch::Receiver<bool>) -> Result<(), String> {
    if *cancel_watch.borrow() {
        Err("Cancelled".into())
    } else {
        Ok(())
    }
}

fn missing_required_source_files(project_dir: &Path) -> Vec<&'static str> {
    [
        "Source/PluginProcessor.h",
        "Source/PluginProcessor.cpp",
        "Source/PluginEditor.h",
        "Source/PluginEditor.cpp",
        "Source/FoundryLookAndFeel.h",
    ]
    .into_iter()
    .filter(|path| !project_dir.join(path).exists())
    .collect()
}

fn infer_creative_profile(
    plugin_name: &str,
    plugin_type: &str,
    user_prompt: &str,
) -> CreativeProfile {
    let seed = stable_hash(&(plugin_name, plugin_type, user_prompt));

    let signature_interaction = choose_variant(
        seed,
        &[
            "a central macro that sweeps between restrained and extreme behavior",
            "a dual-engine blend that lets the user morph between two contrasting textures",
            "a movement control that drives rhythmic or spectral evolution over time",
            "a scene switcher with a clear A/B character contrast",
            "a focus control that shifts the plugin from clean/detail to wide/colored output",
        ],
    );

    let control_strategy = choose_variant(
        seed.rotate_left(7),
        &[
            "group controls into 3 purposeful sections with one obvious hero section",
            "use a left-to-right signal flow with a prominent macro area and smaller utility controls",
            "combine a hero control cluster with a compact detail strip for advanced shaping",
            "make the top half performative and the bottom half corrective or tonal",
        ],
    );

    let ui_direction = choose_variant(
        seed.rotate_left(13),
        &[
            "high-contrast premium hardware vibe with clear visual hierarchy",
            "sleek laboratory panel with focused meters and precise labels",
            "cinematic instrument panel with layered depth and a strong center focal point",
            "compact boutique plugin layout with one bold feature zone and restrained secondary controls",
        ],
    );

    let sonic_hook = match plugin_type {
        "instrument" => choose_variant(
            seed.rotate_left(17),
            &[
                "a polished default patch with width, motion, and a satisfying transient",
                "an immediately playable tone that already feels album-ready before tweaking",
                "a richer voice architecture than a bare demo synth, with musically useful modulation",
            ],
        ),
        "utility" => choose_variant(
            seed.rotate_left(17),
            &[
                "instant visual clarity so the user understands the tool within seconds",
                "a workflow shortcut that turns a technical process into one confident gesture",
                "helpful feedback that makes the utility feel active instead of passive",
            ],
        ),
        _ => choose_variant(
            seed.rotate_left(17),
            &[
                "an effect that is clearly audible at default settings without wrecking gain staging",
                "a strong character mode that makes the plugin memorable on first use",
                "a musical transformation that stays obvious even at conservative settings",
            ],
        ),
    };

    let contrast_detail = choose_variant(
        seed.rotate_left(23),
        &[
            "add one small delight control such as a mode switch, contour toggle, or texture selector",
            "make the visual feedback react to audio or parameter movement so the UI feels alive",
            "use at least one discrete choice control so interaction is not only continuous knobs",
            "reserve one control for tone-shaping extremes instead of keeping every range timid",
        ],
    );

    CreativeProfile {
        signature_interaction,
        control_strategy,
        ui_direction,
        sonic_hook,
        contrast_detail,
    }
}

fn stable_hash<T: Hash>(value: &T) -> u64 {
    let mut hasher = DefaultHasher::new();
    value.hash(&mut hasher);
    hasher.finish()
}

fn choose_variant<'a>(seed: u64, variants: &'a [&'a str]) -> &'a str {
    let index = (seed as usize) % variants.len();
    variants[index]
}

fn extract_parameter_manifest(project_dir: &Path) -> Vec<String> {
    let processor_cpp = read_project_file(project_dir, "Source/PluginProcessor.cpp");
    let mut parameters = Vec::new();
    let needle = "juce::ParameterID(\"";
    let mut start = 0;

    while let Some(found) = processor_cpp[start..].find(needle) {
        let id_start = start + found + needle.len();
        let remainder = &processor_cpp[id_start..];
        let Some(id_end) = remainder.find('"') else {
            break;
        };
        let id = &remainder[..id_end];
        if !id.is_empty() && !parameters.iter().any(|entry: &String| entry == id) {
            parameters.push(id.to_string());
        }
        start = id_start + id_end + 1;
    }

    parameters.into_iter().take(16).collect()
}

fn generate_local_plugin_name(prompt: &str, existing_names: &[String]) -> String {
    let lower = prompt.to_lowercase();
    let generic_pool = [
        "Swell", "Flux", "Bloom", "Drift", "Pulse", "Glint", "Contour", "Halo", "Axiom", "Velor",
        "Forge", "Prism",
    ];
    let instrument_pool = ["Astra", "Nova", "Vanta", "Luma", "Sonar", "Cinder"];
    let effect_pool = ["Bloom", "Drift", "Swell", "Smear", "Grit", "Shiver"];
    let utility_pool = ["Phase", "Vector", "Align", "Scope", "Meter", "Focus"];

    let mut pool: Vec<&str> = Vec::new();
    if lower.contains("synth")
        || lower.contains("instrument")
        || lower.contains("oscillator")
        || lower.contains("sampler")
    {
        pool.extend(instrument_pool);
    }
    if lower.contains("reverb")
        || lower.contains("delay")
        || lower.contains("chorus")
        || lower.contains("distortion")
        || lower.contains("effect")
    {
        pool.extend(effect_pool);
    }
    if lower.contains("utility")
        || lower.contains("meter")
        || lower.contains("analyzer")
        || lower.contains("scope")
        || lower.contains("phase")
    {
        pool.extend(utility_pool);
    }
    pool.extend(generic_pool);

    let taken: Vec<String> = existing_names
        .iter()
        .map(|name| name.to_lowercase())
        .collect();
    let seed = stable_hash(&prompt);

    for offset in 0..pool.len() {
        let candidate = pool[(seed as usize + offset) % pool.len()];
        if !taken.iter().any(|name| name == &candidate.to_lowercase()) {
            return candidate.to_string();
        }
    }

    format!("Mix{}", &uuid::Uuid::new_v4().to_string()[..4])
}

fn validate_generated_source_tree(project_dir: &Path, plugin_name: &str) -> Vec<String> {
    let mut issues = Vec::new();

    let required = [
        "Source/PluginProcessor.h",
        "Source/PluginProcessor.cpp",
        "Source/PluginEditor.h",
        "Source/PluginEditor.cpp",
        "Source/FoundryLookAndFeel.h",
    ];

    for relative in required {
        let path = project_dir.join(relative);
        let Ok(content) = std::fs::read_to_string(&path) else {
            continue;
        };

        let has_expected_include = if relative.ends_with(".h") {
            content.contains("JuceHeader.h")
        } else {
            let sibling_header = relative
                .rsplit_once('.')
                .map(|(stem, _)| format!("{}.h", stem))
                .and_then(|path| {
                    std::path::Path::new(&path)
                        .file_name()
                        .map(|name| name.to_string_lossy().to_string())
                })
                .unwrap_or_default();
            content.contains("JuceHeader.h") || content.contains(&sibling_header)
        };

        if !has_expected_include {
            issues.push(format!("{} must include JuceHeader.h", relative));
        }

        if content.contains("FoundryPlugin") {
            issues.push(format!(
                "{} still contains the placeholder plugin name",
                relative
            ));
        }
    }

    let processor_header = read_project_file(project_dir, "Source/PluginProcessor.h");
    if !processor_header.contains(&format!("class {}Processor", plugin_name)) {
        issues.push(format!(
            "PluginProcessor.h must declare class {}Processor",
            plugin_name
        ));
    }
    if !processor_header.contains("AudioProcessorValueTreeState")
        && !processor_header.contains("apvts")
    {
        issues.push("PluginProcessor.h must expose an APVTS-backed parameter state".into());
    }

    let editor_header = read_project_file(project_dir, "Source/PluginEditor.h");
    if !editor_header.contains(&format!("class {}Editor", plugin_name)) {
        issues.push(format!(
            "PluginEditor.h must declare class {}Editor",
            plugin_name
        ));
    }
    if !editor_header.contains("FoundryLookAndFeel")
        && !read_project_file(project_dir, "Source/PluginEditor.cpp").contains("FoundryLookAndFeel")
    {
        issues.push("Editor must use FoundryLookAndFeel".into());
    }

    let editor_source = read_project_file(project_dir, "Source/PluginEditor.cpp");
    if !editor_header.contains("Attachment") && !editor_source.contains("Attachment") {
        issues.push("Editor must create APVTS attachments for controls".into());
    }
    if let Some((width, height)) = extract_editor_size(&editor_source) {
        if !(640..=1200).contains(&width) || !(360..=900).contains(&height) {
            issues.push("Editor must use a reasonable fixed window size".into());
        }
        if width <= height {
            issues.push(
                "Editor should use a landscape window instead of a tall or square layout".into(),
            );
        }
    } else {
        issues.push("Editor must call setSize(...) with an explicit landscape window size".into());
    }
    if !uses_structured_editor_layout(&editor_source) {
        issues.push(
            "Editor must lay out controls from getLocalBounds() using reduced/removeFrom geometry, Grid, or FlexBox".into(),
        );
    }

    issues.sort();
    issues.dedup();
    issues
}

fn extract_editor_size(editor_source: &str) -> Option<(i32, i32)> {
    let set_size_index = editor_source.find("setSize")?;
    let after_call = &editor_source[set_size_index + "setSize".len()..];
    let open_paren = after_call.find('(')?;
    let args = &after_call[open_paren + 1..];
    let comma = args.find(',')?;
    let close_paren = args[comma + 1..].find(')')?;

    let width: String = args[..comma]
        .chars()
        .filter(|ch| ch.is_ascii_digit())
        .collect();
    let height: String = args[comma + 1..comma + 1 + close_paren]
        .chars()
        .filter(|ch| ch.is_ascii_digit())
        .collect();

    Some((width.parse().ok()?, height.parse().ok()?))
}

fn uses_structured_editor_layout(editor_source: &str) -> bool {
    let uses_bounds_flow = editor_source.contains("getLocalBounds()")
        && (editor_source.contains("reduced(") || editor_source.contains("removeFrom"));

    uses_bounds_flow
        || editor_source.contains("juce::Grid")
        || editor_source.contains("juce::FlexBox")
}

fn build_generation_repair_prompt(
    plugin_name: &str,
    plugin_role: &str,
    user_prompt: &str,
    channel_layout: &str,
    missing_files: &[&str],
    validation_issues: &[String],
) -> String {
    let missing_section = if missing_files.is_empty() {
        "- none".to_string()
    } else {
        missing_files
            .iter()
            .map(|path| format!("- {}", path))
            .collect::<Vec<_>>()
            .join("\n")
    };

    let validation_section = if validation_issues.is_empty() {
        "- none".to_string()
    } else {
        validation_issues
            .iter()
            .map(|issue| format!("- {}", issue))
            .collect::<Vec<_>>()
            .join("\n")
    };

    format!(
        r#"Repair an incomplete or inconsistent JUCE {role} plugin called "{name}".

User brief: {prompt}
Channel layout: {channels}

Missing files:
{missing}

Validation issues:
{validation}

Rules:
- Read existing Source/ files first if they exist so your class names and APIs stay consistent.
- Create or repair only the required Source/ files.
- Keep class names exactly `{name}Processor` and `{name}Editor`.
- Keep parameter IDs stable whenever possible.
- Every exposed control must have a matching APVTS attachment.
- Ensure FoundryLookAndFeel is implemented and used by the editor.
- UI must use a sane landscape editor size with consistent padding, spacing, and non-overlapping controls.
- UI layout must come from `getLocalBounds()` flow, `juce::Grid`, or `juce::FlexBox`, not arbitrary scattered coordinates.
- Remove any leftover `FoundryPlugin` placeholder text.
- Do not touch CMakeLists.txt.

Finish only when all required files exist and the source tree is consistent.
"#,
        role = plugin_role,
        name = plugin_name,
        prompt = user_prompt,
        channels = channel_layout,
        missing = missing_section,
        validation = validation_section,
    )
}

fn read_project_file(project_dir: &Path, relative: &str) -> String {
    std::fs::read_to_string(project_dir.join(relative)).unwrap_or_default()
}

fn summarize_error_snippet(errors: &str) -> String {
    errors
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .take(3)
        .collect::<Vec<_>>()
        .join(" | ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_temp_dir() -> std::path::PathBuf {
        let dir =
            std::env::temp_dir().join(format!("foundry-pipeline-test-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(dir.join("Source")).unwrap();
        dir
    }

    #[test]
    fn creative_profile_is_deterministic() {
        let a = infer_creative_profile("Flux", "effect", "Tape delay with wow and flutter");
        let b = infer_creative_profile("Flux", "effect", "Tape delay with wow and flutter");

        assert_eq!(a, b);
        assert!(!a.signature_interaction.is_empty());
        assert!(!a.ui_direction.is_empty());
    }

    #[test]
    fn local_plugin_name_avoids_taken_names() {
        let name = generate_local_plugin_name(
            "Warm analog polysynth with detuned oscillators",
            &[
                "Astra".into(),
                "Nova".into(),
                "Vanta".into(),
                "Luma".into(),
                "Sonar".into(),
            ],
        );

        assert!(!name.is_empty());
        assert_ne!(name, "Astra");
        assert_ne!(name, "Nova");
    }

    #[test]
    fn extract_parameter_manifest_reads_parameter_ids() {
        let dir = make_temp_dir();
        std::fs::write(
            dir.join("Source/PluginProcessor.cpp"),
            r#"
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID("cutoff", 1), "Cutoff", 20.0f, 20000.0f, 1200.0f));
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID("resonance", 1), "Resonance", 0.1f, 1.0f, 0.3f));
            "#,
        )
        .unwrap();

        let manifest = extract_parameter_manifest(&dir);

        assert_eq!(
            manifest,
            vec!["cutoff".to_string(), "resonance".to_string()]
        );

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn validation_allows_cpp_that_includes_its_header() {
        let dir = make_temp_dir();
        std::fs::write(
            dir.join("Source/PluginProcessor.h"),
            "#include <JuceHeader.h>\nclass FluxProcessor { public: juce::AudioProcessorValueTreeState apvts; };",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginProcessor.cpp"),
            "#include \"PluginProcessor.h\"\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginEditor.h"),
            "#include <JuceHeader.h>\nclass FluxEditor { class FoundryLookAndFeel* lnf; using SliderAttachment = juce::AudioProcessorValueTreeState::SliderAttachment; };",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginEditor.cpp"),
            "#include \"PluginEditor.h\"\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/FoundryLookAndFeel.h"),
            "#include <JuceHeader.h>\nclass FoundryLookAndFeel {};",
        )
        .unwrap();

        let issues = validate_generated_source_tree(&dir, "Flux");

        assert!(!issues
            .iter()
            .any(|issue| issue.contains("PluginEditor.cpp must include JuceHeader.h")));

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn validation_reports_placeholder_and_missing_wiring() {
        let dir = make_temp_dir();

        std::fs::write(
            dir.join("Source/PluginProcessor.h"),
            "#include <JuceHeader.h>\nclass FluxProcessor {};",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginProcessor.cpp"),
            "#include <JuceHeader.h>\n// FoundryPlugin placeholder\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginEditor.h"),
            "#include <JuceHeader.h>\nclass FluxEditor {};",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginEditor.cpp"),
            "#include <JuceHeader.h>\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/FoundryLookAndFeel.h"),
            "#include <JuceHeader.h>\n",
        )
        .unwrap();

        let issues = validate_generated_source_tree(&dir, "Flux");

        assert!(issues
            .iter()
            .any(|issue| issue.contains("placeholder plugin name")));
        assert!(issues
            .iter()
            .any(|issue| issue.contains("APVTS-backed parameter state")));
        assert!(issues
            .iter()
            .any(|issue| issue.contains("FoundryLookAndFeel")));
        assert!(issues.iter().any(|issue| issue.contains("attachments")));

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn extract_editor_size_reads_numeric_dimensions() {
        assert_eq!(extract_editor_size("setSize (820, 480);"), Some((820, 480)));
    }

    #[test]
    fn validation_reports_deformed_or_unstructured_ui() {
        let dir = make_temp_dir();

        std::fs::write(
            dir.join("Source/PluginProcessor.h"),
            "#include <JuceHeader.h>\nclass FluxProcessor { public: juce::AudioProcessorValueTreeState apvts; };",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginProcessor.cpp"),
            "#include \"PluginProcessor.h\"\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginEditor.h"),
            "#include <JuceHeader.h>\nclass FluxEditor { class FoundryLookAndFeel* lnf; using SliderAttachment = juce::AudioProcessorValueTreeState::SliderAttachment; };",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginEditor.cpp"),
            "#include \"PluginEditor.h\"\nvoid FluxEditor::resized() {}\nFluxEditor::FluxEditor() { setSize(320, 900); }\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/FoundryLookAndFeel.h"),
            "#include <JuceHeader.h>\nclass FoundryLookAndFeel {};",
        )
        .unwrap();

        let issues = validate_generated_source_tree(&dir, "Flux");

        assert!(issues
            .iter()
            .any(|issue| issue.contains("reasonable fixed window size")));
        assert!(issues
            .iter()
            .any(|issue| issue.contains("landscape window")));
        assert!(issues.iter().any(|issue| issue.contains("getLocalBounds")));

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn summarize_error_snippet_keeps_first_lines() {
        let summary =
            summarize_error_snippet("first error\n\nsecond error\nthird error\nfourth error");
        assert_eq!(summary, "first error | second error | third error");
    }
}

fn resolve_formats(format: &str) -> Vec<PluginFormat> {
    let requested = match format.to_uppercase().as_str() {
        "AU" => vec![PluginFormat::Au],
        "VST3" => vec![PluginFormat::Vst3],
        _ => vec![PluginFormat::Au, PluginFormat::Vst3],
    };

    let supported = crate::platform::available_plugin_formats();
    let resolved: Vec<PluginFormat> = requested
        .into_iter()
        .filter(|plugin_format| supported.contains(plugin_format))
        .collect();

    if resolved.is_empty() {
        supported
    } else {
        resolved
    }
}

fn archive_build(project_dir: &Path, plugin_id: &str, version: i32) -> Option<String> {
    let versions_dir = foundry_paths::application_support_dir()
        .join("PluginBuilds")
        .join(plugin_id)
        .join(format!("v{}", version));

    if versions_dir.exists() {
        let _ = std::fs::remove_dir_all(&versions_dir);
    }

    if let Some(parent) = versions_dir.parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            log::error!("Failed to prepare archive parent directory: {}", e);
            return None;
        }
    }

    if let Err(e) = clone_or_copy_dir(project_dir, &versions_dir) {
        log::error!("Failed to archive build: {}", e);
        return None;
    }

    Some(versions_dir.to_string_lossy().to_string())
}

fn clone_or_copy_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    #[cfg(target_os = "macos")]
    {
        let status = std::process::Command::new("/bin/cp")
            .args(["-cR", &src.to_string_lossy(), &dst.to_string_lossy()])
            .status();

        if let Ok(status) = status {
            if status.success() {
                return Ok(());
            }
        }
    }

    copy_dir_all(src, dst)
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
        lower.contains("not available")
            || lower.contains("failed to launch")
            || lower.contains("command not found")
    } else {
        false
    }
}

fn rand_index(max: usize) -> usize {
    (uuid::Uuid::new_v4().as_bytes()[0] as usize) % max
}
