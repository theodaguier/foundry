use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Emitter, Manager};

use crate::models::agent::{AgentModel, GenerationAgent};
use crate::models::config::{GenerationConfig, GenerationDebugContext, RefineConfig};
use crate::models::plugin::{
    InstallPaths, Plugin, PluginFormat, PluginStatus, PluginType, PluginVersion,
    SavedGenerationConfig,
};
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
struct RegisteredEvent {
    plugin: Plugin,
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
    sound_design_focus: &'static str,
    visualization_focus: &'static str,
    control_palette: &'static str,
    anti_template_warning: &'static str,
    editor_width: i32,
    editor_height: i32,
}

fn now_ts() -> String {
    chrono::Local::now().format("[%H:%M:%S]").to_string()
}

fn active_debug_context(config: &GenerationConfig) -> Option<&GenerationDebugContext> {
    if config.debug_pipeline {
        config.debug_context.as_ref()
    } else {
        None
    }
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
            if let Some(plugin_id) = tb.plugin_id.clone() {
                let failure_message = if e == "Cancelled" {
                    "Generation was cancelled.".to_string()
                } else {
                    e.clone()
                };
                let _ = mark_plugin_generation_failed(&plugin_id, &failure_message);
            }

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

    clear_active_build(&app);
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
    let existing_names: Vec<String> = existing_plugins
        .iter()
        .filter(|plugin| Some(plugin.id.as_str()) != config.resume_plugin_id.as_deref())
        .map(|plugin| plugin.name.clone())
        .collect();

    // Generate the plugin name locally so the UI can show it immediately.
    emit_log(app, "Generating plugin name...", None);
    let plugin_name = config
        .resume_plugin_name
        .clone()
        .unwrap_or_else(|| generate_local_plugin_name(&config.prompt, &existing_names));
    emit_log(app, &format!("Plugin name: {}", plugin_name), None);
    let _ = app.emit(
        "pipeline:name",
        NameEvent {
            name: plugin_name.clone(),
        },
    );

    let build_entry = register_generation_build(&config, &plugin_name).map_err(|e| e.to_string())?;
    tb.plugin_id = Some(build_entry.id.clone());
    tb.version_number = Some(1);
    let _ = app.emit(
        "pipeline:registered",
        RegisteredEvent {
            plugin: build_entry.clone(),
        },
    );

    let project = if let Some(existing_dir) = reusable_build_directory(&build_entry) {
        emit_log(
            app,
            "Resuming from the previous failed workspace...",
            Some("active"),
        );
        project_assembler::AssembledProject {
            directory: existing_dir,
            plugin_name: plugin_name.clone(),
            plugin_type: plugin_type_to_str(&build_entry.plugin_type).to_string(),
        }
    } else {
        emit_log(app, "Assembling project files...", None);
        let project = project_assembler::assemble(
            &config.prompt,
            &plugin_name,
            config.plugin_type.as_deref(),
            &config.format,
            &config.channel_layout,
            config.preset_count,
            &config.model,
            Path::new(&resolved_juce_path),
        )?;
        persist_plugin_build_directory(&build_entry.id, &project.directory).map_err(|e| e.to_string())?;
        project
    };

    emit_log(
        app,
        "PREPARING PROJECT: Dependencies resolved.",
        Some("success"),
    );

    let plugin_type = &project.plugin_type;
    let plugin_role = match plugin_type.as_str() {
        "instrument" => "playable instrument",
        "utility" => "utility or analysis tool",
        _ => "audio effect",
    };
    let plugin_type_source = if config.plugin_type.is_some() {
        "Selected plugin type"
    } else {
        "Inferred plugin type"
    };
    let project_dir_str = project.directory.to_string_lossy().to_string();
    let creative_profile = infer_creative_profile(&plugin_name, plugin_type, &config.prompt);
    let debug_context = active_debug_context(&config);

    check_cancelled(&cancel_watch)?;

    if let Some(debug_context) = debug_context {
        emit_log(
            app,
            "DEBUG PIPELINE: replaying the last failure context before regeneration.",
            Some("active"),
        );

        if !debug_context.previous_error.trim().is_empty() {
            emit_log(
                app,
                &format!(
                    "DEBUG TARGET · {}",
                    summarize_error_snippet(&debug_context.previous_error)
                ),
                Some("error"),
            );
        }

        let debug_prompt = build_debug_retry_plan_prompt(
            &plugin_name,
            plugin_role,
            plugin_type,
            &config.prompt,
            &config.channel_layout,
            &creative_profile,
            debug_context,
        );

        let app_clone = app.clone();
        let debug_result = agent_service::run(
            agent_name,
            &cli_path,
            &debug_prompt,
            &project_dir_str,
            model_flag,
            "plan",
            move |event| handle_claude_event(&app_clone, &event),
            cancel_watch.clone(),
        )
        .await;

        tb.accumulate_run(&debug_result);

        if is_infra_failure(&debug_result.error) {
            tb.fail(
                "generation",
                debug_result.error.as_deref().unwrap_or("CLI unavailable"),
            );
            return Err(debug_result
                .error
                .unwrap_or_else(|| "Claude Code CLI is unavailable".into()));
        }

        if let Some(error) = debug_result.error {
            emit_log(
                app,
                &format!("DEBUG PLAN WARNING · {}", error),
                Some("error"),
            );
        } else {
            emit_log(
                app,
                "DEBUG PIPELINE: diagnostic pass complete.",
                Some("success"),
            );
        }

        check_cancelled(&cancel_watch)?;
    }

    // Step 2: Generate code in a single self-contained pass for speed.
    emit_step(app, "generatingDSP");
    emit_log(app, "START: Generating plugin code...", Some("active"));
    tb.start_generation();
    emit_log(
        app,
        &format!("{plugin_type_source}: {plugin_type}"),
        Some("active"),
    );

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
        debug_context,
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
            &creative_profile,
            debug_context,
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
        debug_context,
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

        let emergency_ui_prompt = build_emergency_ui_prompt(
            &plugin_name,
            &parameter_manifest,
            &creative_profile,
            debug_context,
        );
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
    if normalize_generated_editor_size(&project.directory, &plugin_name, &creative_profile) {
        emit_log(
            app,
            "Normalized editor setSize(...) to explicit landscape literals.",
            Some("active"),
        );
    }
    let validation_issues =
        validate_generated_source_tree(&project.directory, &plugin_name, &creative_profile);

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

        let repair_prompt = if should_run_ui_recovery(&missing_files, &validation_issues) {
            build_ui_recovery_prompt(
                &plugin_name,
                plugin_role,
                &config.prompt,
                &config.channel_layout,
                &creative_profile,
                &parameter_manifest,
                debug_context,
                &missing_files,
                &validation_issues,
            )
        } else {
            build_generation_repair_prompt(
                &plugin_name,
                plugin_role,
                &config.prompt,
                &config.channel_layout,
                &creative_profile,
                debug_context,
                &missing_files,
                &validation_issues,
            )
        };

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
        if normalize_generated_editor_size(&project.directory, &plugin_name, &creative_profile) {
            emit_log(
                app,
                "Normalized editor setSize(...) after recovery.",
                Some("active"),
            );
        }
        let validation_issues =
            validate_generated_source_tree(&project.directory, &plugin_name, &creative_profile);
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
    let plugin_id = build_entry.id.clone();
    let archived_dir = archive_build(&project.directory, &plugin_id, 1);

    let version = PluginVersion {
        id: uuid::Uuid::new_v4().to_string(),
        plugin_id: plugin_id.clone(),
        version_number: 1,
        prompt: config.prompt.clone(),
        created_at: chrono::Utc::now().to_rfc3339(),
        build_directory: archived_dir.clone(),
        install_paths: install_paths.clone(),
        icon_color: build_entry.icon_color.clone(),
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
        prompt: config.prompt.clone(),
        created_at: build_entry.created_at.clone(),
        formats,
        install_paths,
        icon_color: build_entry.icon_color.clone(),
        logo_asset_path: build_entry.logo_asset_path.clone(),
        status: PluginStatus::Installed,
        build_directory: archived_dir,
        generation_log_path: None,
        agent: build_entry.agent.clone(),
        model: build_entry.model.clone(),
        generation_config: build_entry.generation_config.clone(),
        last_error_message: None,
        current_version: 1,
        versions: vec![version],
    };

    // Save plugin to library
    let mut plugins = plugin_manager::load_plugins().unwrap_or_default();
    if let Some(pos) = plugins.iter().position(|item| item.id == plugin.id) {
        plugins[pos] = plugin.clone();
    } else {
        plugins.insert(0, plugin.clone());
    }
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

    clear_active_build(&app);
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

fn plugin_type_from_config(config: &GenerationConfig) -> PluginType {
    match config
        .plugin_type
        .clone()
        .unwrap_or_else(|| project_assembler::infer_plugin_type(&config.prompt))
        .as_str()
    {
        "instrument" => PluginType::Instrument,
        "utility" => PluginType::Utility,
        _ => PluginType::Effect,
    }
}

fn saved_generation_config(config: &GenerationConfig) -> SavedGenerationConfig {
    SavedGenerationConfig {
        prompt: config.prompt.clone(),
        plugin_type: config.plugin_type.clone(),
        format: config.format.clone(),
        channel_layout: config.channel_layout.clone(),
        preset_count: config.preset_count,
        agent: config.agent.clone(),
        model: config.model.clone(),
    }
}

fn plugin_type_to_str(plugin_type: &PluginType) -> &'static str {
    match plugin_type {
        PluginType::Instrument => "instrument",
        PluginType::Utility => "utility",
        PluginType::Effect => "effect",
    }
}

fn random_icon_color() -> String {
    let colors = [
        "#C8C4BC", "#A8B4A0", "#B0A898", "#9CAAB8", "#B8A8B0", "#A0A8B0",
    ];
    colors[rand_index(colors.len())].to_string()
}

fn register_generation_build(config: &GenerationConfig, plugin_name: &str) -> Result<Plugin, String> {
    let mut plugins = plugin_manager::load_plugins().unwrap_or_default();
    let plugin_type = plugin_type_from_config(config);
    let formats = resolve_formats(&config.format);
    let resolved_agent = generation_agent_from_name(&config.agent);
    let resolved_model = resolve_agent_model(&config.agent, &config.model);
    let saved_config = saved_generation_config(config);

    if let Some(plugin_id) = config.resume_plugin_id.as_deref() {
        if let Some(existing) = plugins.iter_mut().find(|plugin| plugin.id == plugin_id) {
            if existing.current_version <= 0 && existing.versions.is_empty() {
                let reusable_build_dir = existing
                    .build_directory
                    .clone()
                    .filter(|path| Path::new(path).exists());
                existing.name = plugin_name.to_string();
                existing.plugin_type = plugin_type;
                existing.prompt = config.prompt.clone();
                existing.formats = formats.clone();
                existing.install_paths = InstallPaths::default();
                existing.status = PluginStatus::Building;
                existing.build_directory = reusable_build_dir;
                existing.generation_log_path = None;
                existing.agent = Some(resolved_agent.clone());
                existing.model = Some(resolved_model.clone());
                existing.generation_config = Some(saved_config.clone());
                existing.last_error_message = None;
                existing.current_version = 0;

                let updated = existing.clone();
                plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;
                return Ok(updated);
            }
        }
    }

    let requested_id = config.resume_plugin_id.as_deref();
    let can_reuse_requested_id = requested_id.is_some()
        && requested_id
            .map(|plugin_id| plugins.iter().all(|plugin| plugin.id != plugin_id))
            .unwrap_or(false);
    let plugin_id = if can_reuse_requested_id {
        requested_id.unwrap().to_string()
    } else {
        uuid::Uuid::new_v4().to_string()
    };

    let plugin = Plugin {
        id: plugin_id,
        name: plugin_name.to_string(),
        plugin_type,
        prompt: config.prompt.clone(),
        created_at: chrono::Utc::now().to_rfc3339(),
        formats,
        install_paths: InstallPaths::default(),
        icon_color: random_icon_color(),
        logo_asset_path: None,
        status: PluginStatus::Building,
        build_directory: None,
        generation_log_path: None,
        agent: Some(resolved_agent),
        model: Some(resolved_model),
        generation_config: Some(saved_config),
        last_error_message: None,
        current_version: 0,
        versions: vec![],
    };

    plugins.insert(0, plugin.clone());
    plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;
    Ok(plugin)
}

fn reusable_build_directory(plugin: &Plugin) -> Option<PathBuf> {
    plugin
        .build_directory
        .as_ref()
        .map(PathBuf::from)
        .filter(|path| path.exists())
}

fn persist_plugin_build_directory(plugin_id: &str, build_directory: &Path) -> Result<Plugin, String> {
    let mut plugins = plugin_manager::load_plugins().map_err(|e| e.to_string())?;
    let plugin = plugins
        .iter_mut()
        .find(|plugin| plugin.id == plugin_id)
        .ok_or_else(|| format!("Plugin not found while saving build workspace: {}", plugin_id))?;
    plugin.build_directory = Some(build_directory.to_string_lossy().to_string());

    let updated = plugin.clone();
    plugin_manager::save_plugins(&plugins).map_err(|e| e.to_string())?;
    Ok(updated)
}

fn mark_plugin_generation_failed(plugin_id: &str, message: &str) -> Option<Plugin> {
    let mut plugins = plugin_manager::load_plugins().ok()?;
    let plugin = plugins.iter_mut().find(|plugin| plugin.id == plugin_id)?;
    plugin.status = PluginStatus::Failed;
    plugin.last_error_message = Some(message.to_string());

    let updated = plugin.clone();
    plugin_manager::save_plugins(&plugins).ok()?;
    Some(updated)
}

fn clear_active_build(app: &AppHandle) {
    if let Some(state) = app.try_state::<crate::state::AppState>() {
        if let Ok(mut token) = state.build_cancel_token.lock() {
            *token = None;
        }
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
    plugin.last_error_message = None;

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

fn build_fast_processor_prompt(
    plugin_name: &str,
    plugin_role: &str,
    plugin_type: &str,
    user_prompt: &str,
    channel_layout: &str,
    creative_profile: &CreativeProfile,
    debug_context: Option<&GenerationDebugContext>,
) -> String {
    let type_rules = plugin_type_prompt_rules(plugin_type);
    let debug_context_section = render_debug_context_section(debug_context);

    format!(
        r#"
Build the DSP foundation for a JUCE {role} plugin called "{name}".

User brief: {prompt}
Plugin type: {plugin_type}
Channel layout: {channels}
{debug_context_section}

Create only:
- Source/PluginProcessor.h
- Source/PluginProcessor.cpp

Creative targets:
- Signature interaction: {signature_interaction}
- Sonic hook: {sonic_hook}
- Sound design focus: {sound_design_focus}
- Contrast detail: {contrast_detail}

Rules:
- Implement APVTS parameters and a real processBlock path.
- No dead controls.
- Make the default state obviously useful and audible.
- Make the parameter list reflect the brief; do not fall back to the same stock plugin vocabulary for every build.
- Prefer at least one discrete mode/state parameter or routable behavior when the brief supports it, so the UI can offer more than cloned knobs.
- Expose musically meaningful ranges, timbral extremes, and customization that changes the result clearly.
- Respect these type-specific constraints:
{type_rules}
- Use juce:: prefixes everywhere.
- Include JuceHeader.h in both files.
- Class name must be exactly {name}Processor.
- Do not create editor files.
- Do not read any project source files before writing.
- Do not touch CMakeLists.txt.
"#,
        role = plugin_role,
        name = plugin_name,
        prompt = user_prompt,
        plugin_type = plugin_type,
        channels = channel_layout,
        debug_context_section = debug_context_section,
        type_rules = type_rules,
        signature_interaction = creative_profile.signature_interaction,
        sonic_hook = creative_profile.sonic_hook,
        sound_design_focus = creative_profile.sound_design_focus,
        contrast_detail = creative_profile.contrast_detail,
    )
}

fn plugin_type_prompt_rules(plugin_type: &str) -> &'static str {
    match plugin_type {
        "instrument" => {
            "- This is a playable instrument, not an insert effect or utility.\n\
            - Generate sound from MIDI note events and make the default preset playable even with silent audio input.\n\
            - Use `juce::Synthesiser` plus voices or an equivalent per-note voice engine.\n\
            - Do not build the processor as a pass-through chain with only metering, width, or gain utilities."
        }
        "utility" => {
            "- Prioritize metering, analysis, routing, correction, or gain utility workflows.\n\
            - Do not add fake synth voices, MIDI-note playback, or a decorative wet/dry FX chain unless the brief explicitly asks for it.\n\
            - If the plugin changes audio, keep the processing technical, transparent, and purpose-driven."
        }
        _ => {
            "- This is an audio effect, so process incoming audio in `processBlock`.\n\
            - Do not require MIDI-note playback or build a synth voice architecture unless the brief explicitly asks for it.\n\
            - A clear input -> effect -> output signal path is the default expectation."
        }
    }
}

fn build_fast_ui_prompt(
    plugin_name: &str,
    plugin_role: &str,
    plugin_type: &str,
    user_prompt: &str,
    channel_layout: &str,
    creative_profile: &CreativeProfile,
    parameter_manifest: &[String],
    debug_context: Option<&GenerationDebugContext>,
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
    let debug_context_section = render_debug_context_section(debug_context);

    format!(
        r#"
Complete the UI for the existing JUCE {role} plugin "{name}".

User brief: {prompt}
Plugin type: {plugin_type}
Channel layout: {channels}
{debug_context_section}

Skeleton files already exist in Source/. Do NOT create them from scratch — overwrite them with complete implementations:
- Source/FoundryLookAndFeel.h  (new file — write fresh)
- Source/PluginEditor.h        (skeleton exists — replace with full implementation)
- Source/PluginEditor.cpp      (skeleton exists — replace with full implementation)

The skeleton already has the correct structure. Your job: replace it with the full design.
The skeleton's `setSize(820, 520)` and `getLocalBounds()`-based `resized()` are correct — keep that pattern.

Processor contract:
- Processor class: {name}Processor
- Editor class: {name}Editor
- Use these parameter IDs exactly:
{parameter_block}

Creative targets:
- Control strategy: {control_strategy}
- UI direction: {ui_direction}
- Contrast detail: {contrast_detail}
- Visualization focus: {visualization_focus}
- Control palette: {control_palette}
- Anti-template warning: {anti_template_warning}

Rules:
- Every visible control must map to a real parameter with an APVTS attachment.
- Use FoundryLookAndFeel in the editor.
- Avoid a flat row of generic knobs; create one hero interaction zone.
- Prefer showing the 8-12 most important parameters if the processor exposes many internals.
- Use a generous landscape editor size that fits the whole design without scroll, around {editor_width}x{editor_height} unless the brief strongly justifies another explicit numeric size.
- Build the layout from `getLocalBounds().reduced(...)` plus `removeFrom*`, or use `juce::Grid` / `juce::FlexBox`; do not scatter arbitrary overlapping coordinates.
- Keep outer padding around 20-28 px and internal gaps around 12-20 px.
- Keep rotary controls square and readable, labels aligned, and widgets away from the window edges.
- Make the interface clean and balanced before it is flashy, but do not make it anonymous or interchangeable.
- Use at least 3 control families across the editor, chosen from rotary knobs, linear sliders/faders, buttons/toggles, combo boxes/selectors, XY or macro pads, meters, scopes, or curve displays.
- Choose control types by meaning: knobs for macro sweeps, sliders/faders for ranges and balance, toggles/buttons for states, selectors for algorithms or routing, curves/graphs for time/frequency shaping.
- Treat any GUI section in the user brief as inspiration, not a literal panel blueprint, unless the user explicitly asks for an exact replica or pixel-perfect clone.
- Never expose more than about 24 primary controls on one page. If the design needs more, use tabs, page buttons, compact subsections, or mode views. Never use scrolling as the solution.
- If the processor exposes many parameters, prioritize the hero controls and organize the rest into compact sections, tabs, or a footer strip. Never use scrolling as the solution.
- Do not use `juce::Viewport`, `juce::ScrollBar`, or any scroll-only layout. Everything important must fit in one window at 100% scale.
- Build a multi-zone layout with a header/display strip, a hero control region, and secondary sections across the width. Avoid a single vertical column of controls.
- If the brief implies envelopes, EQ, compression, filtering, modulation, sequencing, or analysis, draw a matching curve, graph, meter, or motion component instead of only numeric labels.
- In `PluginEditor.cpp`, the constructor must contain an explicit numeric call such as `setSize({editor_width}, {editor_height});`.
- Do not use named constants, helper variables, or portrait dimensions for that `setSize(...)` call.
- Keep class name exactly {name}Editor.
- Use juce:: prefixes everywhere.
- Do not read any project source files before writing.
- Do not touch CMakeLists.txt.
"#,
        role = plugin_role,
        name = plugin_name,
        prompt = user_prompt,
        plugin_type = plugin_type,
        channels = channel_layout,
        debug_context_section = debug_context_section,
        control_strategy = creative_profile.control_strategy,
        ui_direction = creative_profile.ui_direction,
        contrast_detail = creative_profile.contrast_detail,
        visualization_focus = creative_profile.visualization_focus,
        control_palette = creative_profile.control_palette,
        anti_template_warning = creative_profile.anti_template_warning,
        editor_width = creative_profile.editor_width,
        editor_height = creative_profile.editor_height,
        parameter_block = parameter_block,
    )
}

fn build_emergency_ui_prompt(
    plugin_name: &str,
    parameter_manifest: &[String],
    creative_profile: &CreativeProfile,
    debug_context: Option<&GenerationDebugContext>,
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
    let debug_context_section = render_debug_context_section(debug_context);

    format!(
        r#"
Emergency UI pass for JUCE plugin "{name}".
{debug_context_section}

Skeleton files already exist in Source/. Overwrite them with complete implementations:
- Source/FoundryLookAndFeel.h  (write fresh)
- Source/PluginEditor.h        (skeleton exists — complete it)
- Source/PluginEditor.cpp      (skeleton exists — complete it)

The skeleton already has correct `setSize(820, 520)` and `getLocalBounds()` layout. Keep that structure.

Known contract:
- Processor class: {name}Processor
- Editor class: {name}Editor
- Visible controls must use only these parameter IDs:
{parameter_block}

UI direction:
- {ui_direction}
- {control_strategy}
- {visualization_focus}
- {control_palette}

Rules:
- One short sentence, then write files immediately.
- No analysis.
- No explanation after writing.
- Use FoundryLookAndFeel.
- Use APVTS attachments for every visible control.
- Use a generous landscape editor size with a clean, non-overlapping multi-zone layout.
- In `PluginEditor.cpp`, call `setSize({editor_width}, {editor_height});` or another explicit numeric landscape size in the constructor.
- Do not use named constants, helper variables, or portrait dimensions for that `setSize(...)` call.
- Derive geometry from `getLocalBounds()` with consistent padding and gaps.
- Do not treat GUI details from the brief as a literal wireframe unless the user explicitly requested an exact replica.
- If the editor needs more than about 24 primary controls, use tabs, pages, or compact alternate views instead of one giant surface.
- Do not use `juce::Viewport`, `juce::ScrollBar`, or a single long column that would require scrolling.
- Use more than one control family and include a meaningful display, graph, scope, or meter when the plugin brief warrants it.
- Keep the UI compact, legible, and compile-safe.
"#,
        name = plugin_name,
        debug_context_section = debug_context_section,
        parameter_block = parameter_block,
        ui_direction = creative_profile.ui_direction,
        control_strategy = creative_profile.control_strategy,
        visualization_focus = creative_profile.visualization_focus,
        control_palette = creative_profile.control_palette,
        editor_width = creative_profile.editor_width,
        editor_height = creative_profile.editor_height,
    )
}

fn build_debug_retry_plan_prompt(
    plugin_name: &str,
    plugin_role: &str,
    plugin_type: &str,
    user_prompt: &str,
    channel_layout: &str,
    creative_profile: &CreativeProfile,
    debug_context: &GenerationDebugContext,
) -> String {
    let debug_context_section = render_debug_context_section(Some(debug_context));

    format!(
        r#"
Debug retry for JUCE {role} plugin "{name}".

User brief: {prompt}
Plugin type: {plugin_type}
Channel layout: {channels}

Creative targets:
- Signature interaction: {signature_interaction}
- Control strategy: {control_strategy}
- Visualization focus: {visualization_focus}
- Target editor size: {editor_width}x{editor_height}

{debug_context_section}
Task:
- Do not read or write files.
- Produce 4-6 short bullets only.
- Cover: likely root cause, DSP file strategy, UI layout strategy, control/display strategy, and validation traps to avoid.
- If the last failure mentioned missing files, invalid editor layout, scroll, or a single vertical stack, say exactly how this retry will avoid that.
- Keep the plan concrete to this plugin instead of giving generic advice.
"#,
        role = plugin_role,
        name = plugin_name,
        prompt = user_prompt,
        plugin_type = plugin_type,
        channels = channel_layout,
        signature_interaction = creative_profile.signature_interaction,
        control_strategy = creative_profile.control_strategy,
        visualization_focus = creative_profile.visualization_focus,
        editor_width = creative_profile.editor_width,
        editor_height = creative_profile.editor_height,
        debug_context_section = debug_context_section,
    )
}

fn render_debug_context_section(debug_context: Option<&GenerationDebugContext>) -> String {
    let Some(debug_context) = debug_context else {
        return String::new();
    };

    let previous_error = if debug_context.previous_error.trim().is_empty() {
        "- none captured".to_string()
    } else {
        format!(
            "- {}",
            truncate_debug_prompt_line(&debug_context.previous_error, 420)
        )
    };

    let recent_logs = if debug_context.recent_logs.is_empty() {
        "- none captured".to_string()
    } else {
        debug_context
            .recent_logs
            .iter()
            .take(8)
            .map(|line| format!("- {}", truncate_debug_prompt_line(line, 180)))
            .collect::<Vec<_>>()
            .join("\n")
    };

    format!(
        r#"
## DEBUG RETRY CONTEXT
- Trigger: {}
Previous failure:
{}
Recent pipeline logs:
{}
- Address these failure symptoms directly in this run. Do not repeat the same missing files, scroll-heavy UI, or invalid layout pattern.
"#,
        debug_context.trigger, previous_error, recent_logs
    )
}

fn truncate_debug_prompt_line(input: &str, max_len: usize) -> String {
    let compact = input.split_whitespace().collect::<Vec<_>>().join(" ");
    if compact.chars().count() <= max_len {
        compact
    } else {
        format!("{}…", compact.chars().take(max_len).collect::<String>())
    }
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
    let lower = user_prompt.to_lowercase();
    let (editor_width, editor_height) = infer_editor_size(plugin_type, &lower);

    let signature_interaction = if prompt_mentions_any(
        &lower,
        &[
            "eq",
            "filter",
            "shelf",
            "compressor",
            "multiband",
            "dynamics",
        ],
    ) {
        choose_variant(
            seed.rotate_left(3),
            &[
                "a hero shaping zone where one gesture audibly moves the response curve or transfer behavior",
                "a central response-shaping control that flips the plugin between gentle polish and hard sculpting",
                "a graph-led macro that makes the tone-shaping intent obvious in one move",
            ],
        )
    } else if prompt_mentions_any(
        &lower,
        &[
            "lfo",
            "modulation",
            "sequencer",
            "gate",
            "tremolo",
            "arpeggio",
            "step",
        ],
    ) {
        choose_variant(
            seed.rotate_left(3),
            &[
                "a movement section that can swing from locked grooves to unstable evolving motion",
                "a performance lane that pushes the plugin between disciplined rhythm and chaotic drift",
                "a time-shaping macro that makes motion feel playable instead of hidden in submenus",
            ],
        )
    } else if prompt_mentions_any(
        &lower,
        &[
            "granular", "reverb", "delay", "shimmer", "space", "echo", "freeze",
        ],
    ) {
        choose_variant(
            seed.rotate_left(3),
            &[
                "a space-time macro that pulls the plugin between tight focus and huge atmospheric bloom",
                "a central diffusion gesture that opens the sound from intimate to cinematic",
                "a freeze-or-bloom interaction that gives the effect an immediate dramatic personality",
            ],
        )
    } else if prompt_mentions_any(
        &lower,
        &[
            "utility", "meter", "analyzer", "stereo", "tuner", "lufs", "phase",
        ],
    ) {
        choose_variant(
            seed.rotate_left(3),
            &[
                "a confidence control area that makes the technical task obvious in one glance",
                "a measurement-first interaction that turns technical feedback into a single decisive gesture",
                "a clear control focus that lets the user solve the task without hunting through identical widgets",
            ],
        )
    } else if prompt_mentions_any(
        &lower,
        &["fm", "wavetable", "digital", "glitch", "spectral"],
    ) {
        choose_variant(
            seed.rotate_left(3),
            &[
                "a macro that pushes the engine between clean digital precision and aggressive animated character",
                "a contrast control that swings the engine from glassy focus to unstable digital violence",
                "a hero morph interaction that makes the synthetic identity obvious immediately",
            ],
        )
    } else {
        choose_variant(
            seed,
            &[
                "a central macro that sweeps between restrained and extreme behavior",
                "a dual-engine blend that lets the user morph between two contrasting textures",
                "a movement control that drives rhythmic or spectral evolution over time",
                "a scene switcher with a clear A/B character contrast",
                "a focus control that shifts the plugin from clean/detail to wide/colored output",
            ],
        )
    };

    let control_strategy = if prompt_mentions_any(
        &lower,
        &[
            "eq",
            "filter",
            "compressor",
            "multiband",
            "analyzer",
            "meter",
        ],
    ) {
        choose_variant(
            seed.rotate_left(7),
            &[
                "use a graph-first layout with a large display band, a hero shaping row, and a compact precision strip",
                "make the upper half a measurement display and the lower half a compact correction deck",
                "anchor the interface around one large response view with sidecar precision controls",
            ],
        )
    } else if prompt_mentions_any(
        &lower,
        &[
            "granular",
            "modulation",
            "sequencer",
            "lfo",
            "glitch",
            "wavetable",
            "fm",
        ],
    ) {
        choose_variant(
            seed.rotate_left(7),
            &[
                "split the editor into a bold performative zone, a motion/curve zone, and a tighter detail bank",
                "use a center performance surface with sidecar motion tools and a compact detail footer",
                "organize the interface as a hero engine, a live modulation display, and a restrained utility strip",
            ],
        )
    } else if plugin_type == "instrument" {
        choose_variant(
            seed.rotate_left(7),
            &[
                "make the center performative, the sides tonal, and reserve a lower strip for motion or envelope shaping",
                "use a strong central performance cluster with asymmetric oscillator and contour wings",
                "build a playable core flanked by focused color and motion zones",
            ],
        )
    } else {
        choose_variant(
            seed.rotate_left(7),
            &[
                "group controls into 3 purposeful sections with one obvious hero section",
                "use a left-to-right signal flow with a prominent macro area and smaller utility controls",
                "combine a hero control cluster with a compact detail strip for advanced shaping",
                "make the top half performative and the bottom half corrective or tonal",
            ],
        )
    };

    let ui_direction = if prompt_mentions_any(
        &lower,
        &[
            "analog", "warm", "vintage", "tape", "spring", "organ", "tube",
        ],
    ) {
        choose_variant(
            seed.rotate_left(13),
            &[
                "a tactile studio-rack faceplate with bold labeling, asymmetrical massing, and obvious hero hardware",
                "a cream-and-charcoal vintage console with disciplined spacing and a strong center of gravity",
                "a Japanese-synth-inspired panel with color-blocked sections, bold faders, and a clear performance focus",
                "a brushed-metal instrument slab with restrained glow, strong labels, and chunky control contrast",
            ],
        )
    } else if prompt_mentions_any(
        &lower,
        &[
            "fm",
            "wavetable",
            "digital",
            "glitch",
            "spectral",
            "granular",
        ],
    ) {
        choose_variant(
            seed.rotate_left(13),
            &[
                "a futuristic digital instrument panel with crisp displays, motion cues, and non-uniform control sizing",
                "a kinetic lab interface with display-led sections and sharp geometric control islands",
                "a bold cybernetic panel with asymmetric blocks, animated displays, and deliberate density shifts",
                "a high-tech performance console with screen-led hierarchy and minimal ornamental hardware cues",
            ],
        )
    } else if prompt_mentions_any(
        &lower,
        &[
            "compressor",
            "eq",
            "meter",
            "analyzer",
            "tuner",
            "utility",
            "phase",
            "stereo",
        ],
    ) {
        choose_variant(
            seed.rotate_left(13),
            &[
                "a graph-led precision workstation with strong measurement surfaces and purposeful color restraint",
                "a mastering-lab panel with dense readouts, ruler-like spacing, and a dominant measurement band",
                "a surgical analysis desk with oscilloscope energy and compact technical controls",
                "a disciplined engineering workstation with bold data displays and no decorative excess",
            ],
        )
    } else if plugin_type == "instrument" {
        choose_variant(
            seed.rotate_left(13),
            &[
                "a performance-focused synth panel with an expressive center and supporting modulation wings",
                "a dramatic instrument deck with a playable core and smaller contour stations around it",
                "a boutique live-synth layout with one dominant feature zone and a disciplined supporting cast",
            ],
        )
    } else {
        choose_variant(
            seed.rotate_left(13),
            &[
                "high-contrast premium hardware vibe with clear visual hierarchy",
                "sleek laboratory panel with focused meters and precise labels",
                "cinematic instrument panel with layered depth and a strong center focal point",
                "compact boutique plugin layout with one bold feature zone and restrained secondary controls",
            ],
        )
    };

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

    let contrast_detail = if prompt_mentions_any(
        &lower,
        &[
            "compressor",
            "eq",
            "filter",
            "envelope",
            "lfo",
            "curve",
            "shape",
        ],
    ) {
        "let one graph or curve become the star so the plugin communicates shape instead of only numbers"
    } else {
        choose_variant(
            seed.rotate_left(23),
            &[
                "add one small delight control such as a mode switch, contour toggle, or texture selector",
                "make the visual feedback react to audio or parameter movement so the UI feels alive",
                "use at least one discrete choice control so interaction is not only continuous knobs",
                "reserve one control for tone-shaping extremes instead of keeping every range timid",
            ],
        )
    };

    let sound_design_focus = infer_sound_design_focus(plugin_type, &lower, seed.rotate_left(29));
    let visualization_focus = infer_visualization_focus(plugin_type, &lower, seed.rotate_left(31));
    let control_palette = infer_control_palette(plugin_type, &lower, seed.rotate_left(37));
    let anti_template_warning =
        infer_anti_template_warning(plugin_type, &lower, seed.rotate_left(41));

    CreativeProfile {
        signature_interaction,
        control_strategy,
        ui_direction,
        sonic_hook,
        contrast_detail,
        sound_design_focus,
        visualization_focus,
        control_palette,
        anti_template_warning,
        editor_width,
        editor_height,
    }
}

fn prompt_mentions_any(lower_prompt: &str, keywords: &[&str]) -> bool {
    keywords
        .iter()
        .any(|keyword| lower_prompt.contains(keyword))
}

fn infer_editor_size(plugin_type: &str, lower_prompt: &str) -> (i32, i32) {
    let mut complexity = match plugin_type {
        "instrument" => 2,
        "utility" => 1,
        _ => 1,
    };

    if prompt_mentions_any(
        lower_prompt,
        &[
            "granular",
            "sequencer",
            "matrix",
            "modulation",
            "multiband",
            "compressor",
            "eq",
            "curve",
            "envelope",
            "lfo",
            "wavetable",
            "fm",
            "spectrum",
            "analyzer",
            "meter",
            "stereo",
            "shimmer",
            "convolution",
            "drum",
            "sampler",
        ],
    ) {
        complexity += 1;
    }

    if prompt_mentions_any(
        lower_prompt,
        &[
            "simple",
            "minimal",
            "focused",
            "one knob",
            "two knobs",
            "three knobs",
            "macro",
            "single control",
        ],
    ) {
        complexity -= 1;
    }

    complexity = complexity.clamp(0, 3);

    match complexity {
        0 => (860, 560),
        1 => (920, 600),
        2 => (980, 640),
        _ => (1100, 700),
    }
}

fn infer_sound_design_focus(plugin_type: &str, lower_prompt: &str, seed: u64) -> &'static str {
    if prompt_mentions_any(
        lower_prompt,
        &[
            "analog", "warm", "vintage", "tape", "spring", "tube", "felt",
        ],
    ) {
        "prioritize nonlinear character, drift, damping, and pleasing saturation so the plugin does not feel sterile"
    } else if prompt_mentions_any(
        lower_prompt,
        &["fm", "wavetable", "digital", "glitch", "spectral", "ring"],
    ) {
        "lean into distinctive digital motion, sharp transients, and contrast between clean and extreme states"
    } else if prompt_mentions_any(
        lower_prompt,
        &[
            "granular", "shimmer", "reverb", "delay", "ambient", "drone", "freeze",
        ],
    ) {
        "make the time-domain behavior rich and evolving, with defaults that bloom immediately instead of sounding half-finished"
    } else if prompt_mentions_any(
        lower_prompt,
        &[
            "compressor",
            "eq",
            "filter",
            "utility",
            "meter",
            "analyzer",
            "stereo",
            "phase",
        ],
    ) {
        "make every technical parameter meaningful, confident, and obvious at useful settings instead of timid placeholder ranges"
    } else if plugin_type == "instrument" {
        "make the default patch feel playable, wide, and production-ready on the very first note"
    } else {
        choose_variant(
            seed,
            &[
                "bias the default state toward a memorable tone immediately, not a neutral placeholder",
                "build in one strong character option so the plugin has identity before fine-tuning",
                "prefer musically obvious movement and customization over technically correct but timid defaults",
            ],
        )
    }
}

fn infer_visualization_focus(plugin_type: &str, lower_prompt: &str, seed: u64) -> &'static str {
    if prompt_mentions_any(
        lower_prompt,
        &[
            "eq",
            "filter",
            "compressor",
            "multiband",
            "envelope",
            "transient",
        ],
    ) {
        "draw a live curve, response graph, or transfer display that makes the shaping visible and interactive"
    } else if prompt_mentions_any(
        lower_prompt,
        &[
            "lfo",
            "modulation",
            "sequencer",
            "gate",
            "tremolo",
            "step",
            "arpeggio",
        ],
    ) {
        "show motion with an LFO curve, pattern lane, or modulation path so time-based behavior has a visual soul"
    } else if prompt_mentions_any(
        lower_prompt,
        &[
            "wavetable",
            "oscillator",
            "fm",
            "synth",
            "instrument",
            "voice",
            "drum",
        ],
    ) {
        "show a waveform, envelope, or voice-motion display so the instrument feels alive before the user even tweaks a control"
    } else if prompt_mentions_any(
        lower_prompt,
        &[
            "meter", "analyzer", "lufs", "tuner", "stereo", "phase", "scope",
        ],
    ) {
        "make metering a first-class surface with a spectrum, correlation view, tuner needle, oscilloscope, or loudness bridge as appropriate"
    } else if prompt_mentions_any(
        lower_prompt,
        &[
            "delay", "reverb", "shimmer", "granular", "echo", "space", "freeze",
        ],
    ) {
        "show diffusion, delay taps, grain density, or decay movement so the space-making behavior is legible"
    } else if plugin_type == "utility" {
        "include a meter or technical feedback element so the tool feels active instead of passive"
    } else {
        choose_variant(
            seed,
            &[
                "add a focused display strip that reacts to audio or parameter movement",
                "include one custom-drawn graph or scope that anchors the interface",
                "use a compact live display so the plugin communicates its state visually instead of only with labels",
            ],
        )
    }
}

fn infer_control_palette(plugin_type: &str, lower_prompt: &str, seed: u64) -> &'static str {
    if prompt_mentions_any(
        lower_prompt,
        &[
            "eq",
            "filter",
            "compressor",
            "multiband",
            "utility",
            "analyzer",
        ],
    ) {
        "mix hero knobs with precise vertical sliders or faders, state buttons, selectors, and draggable graph interaction"
    } else if prompt_mentions_any(
        lower_prompt,
        &[
            "granular",
            "modulation",
            "sequencer",
            "wavetable",
            "fm",
            "glitch",
        ],
    ) {
        "mix macro knobs, at least one slider or fader, discrete mode switches, and a custom motion display instead of same-sized controls"
    } else if plugin_type == "instrument" {
        "use a performance macro, rotary timbre controls, at least one envelope or balance slider, and a mode or algorithm selector"
    } else {
        choose_variant(
            seed,
            &[
                "combine a hero knob cluster with a short fader strip, a mode switch, and a compact display",
                "mix rotary controls, one or two linear controls, and at least one discrete selector so interaction feels composed",
                "use different control sizes and types to establish hierarchy instead of cloning the same dial repeatedly",
            ],
        )
    }
}

fn infer_anti_template_warning(plugin_type: &str, lower_prompt: &str, seed: u64) -> &'static str {
    if prompt_mentions_any(
        lower_prompt,
        &[
            "digital",
            "fm",
            "wavetable",
            "glitch",
            "granular",
            "spectral",
        ],
    ) {
        "avoid turning this into the same dark boutique pedal face; it should feel intentionally digital and animated"
    } else if prompt_mentions_any(
        lower_prompt,
        &["utility", "meter", "analyzer", "tuner", "phase", "stereo"],
    ) {
        "avoid hiding a technical tool behind decorative chrome; clarity and graph hierarchy should drive the design"
    } else if plugin_type == "instrument" {
        "avoid a generic FX pedal layout; instruments need a playable center of gravity and richer control variety"
    } else {
        choose_variant(
            seed,
            &[
                "do not ship another anonymous black box with one centered knob row",
                "avoid equal-sized widgets on a flat strip; vary hierarchy and control language",
                "do not solve the brief with the same premium-hardware template if the sound concept asks for something more specific",
            ],
        )
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

fn validate_generated_source_tree(
    project_dir: &Path,
    plugin_name: &str,
    creative_profile: &CreativeProfile,
) -> Vec<String> {
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
    let editor_combined = format!("{}\n{}", editor_header, editor_source);
    if !editor_header.contains("Attachment") && !editor_source.contains("Attachment") {
        issues.push("Editor must create APVTS attachments for controls".into());
    }
    if let Some((width, height)) = extract_editor_size(&editor_source) {
        if !(820..=1400).contains(&width) || !(520..=900).contains(&height) {
            issues.push("Editor must use a reasonable fixed window size".into());
        }
        if width <= height {
            issues.push(
                "Editor should use a landscape window instead of a tall or square layout".into(),
            );
        }
        if width < creative_profile.editor_width || height < creative_profile.editor_height {
            issues.push(format!(
                "Editor should be large enough to fit the design without scroll (target at least {}x{})",
                creative_profile.editor_width, creative_profile.editor_height
            ));
        }
    } else {
        issues.push("Editor must call setSize(...) with an explicit landscape window size".into());
    }
    if !uses_structured_editor_layout(&editor_source) {
        issues.push(
            "Editor must lay out controls from getLocalBounds() using reduced/removeFrom geometry, Grid, or FlexBox".into(),
        );
    }
    if !uses_multi_zone_editor_layout(&editor_source) {
        issues.push(
            "Editor should use a multi-zone landscape layout instead of a single vertical stack"
                .into(),
        );
    }
    if visible_control_count(&editor_source) > 24 && !uses_control_paging(&editor_combined) {
        issues.push(
            "High-density editors must use tabs, pages, or alternate views instead of exposing every control on one surface"
                .into(),
        );
    }
    if uses_scrolling_ui(&editor_combined) {
        issues.push(
            "Editor must not rely on Viewport or scroll bars; everything should fit in one window"
                .into(),
        );
    }

    issues.sort();
    issues.dedup();
    issues
}

fn editor_size_is_valid(width: i32, height: i32) -> bool {
    (820..=1400).contains(&width) && (520..=900).contains(&height) && width > height
}

fn normalize_generated_editor_size(
    project_dir: &Path,
    plugin_name: &str,
    creative_profile: &CreativeProfile,
) -> bool {
    let path = project_dir.join("Source/PluginEditor.cpp");
    let Ok(editor_source) = std::fs::read_to_string(&path) else {
        return false;
    };

    if extract_editor_size(&editor_source)
        .map(|(width, height)| editor_size_is_valid(width, height))
        .unwrap_or(false)
    {
        return false;
    }

    let Some(normalized) = rewrite_editor_size(&editor_source, plugin_name, creative_profile)
    else {
        return false;
    };

    if normalized == editor_source {
        return false;
    }

    std::fs::write(path, normalized).is_ok()
}

fn rewrite_editor_size(
    editor_source: &str,
    plugin_name: &str,
    creative_profile: &CreativeProfile,
) -> Option<String> {
    let default_editor_size_call = format!(
        "setSize({}, {});",
        creative_profile.editor_width, creative_profile.editor_height
    );

    if let Some(updated) = replace_first_set_size_call(editor_source, &default_editor_size_call) {
        return Some(updated);
    }

    let constructor_needle = format!("{name}Editor::{name}Editor", name = plugin_name);
    let constructor_index = editor_source.find(&constructor_needle)?;
    let after_constructor = &editor_source[constructor_index + constructor_needle.len()..];
    let open_brace = after_constructor.find('{')?;
    let insert_at = constructor_index + constructor_needle.len() + open_brace + 1;
    let trailing_break = if editor_source[insert_at..].starts_with('\n') {
        ""
    } else {
        "\n"
    };

    Some(format!(
        "{}\n    {}{}{}",
        &editor_source[..insert_at],
        default_editor_size_call,
        trailing_break,
        &editor_source[insert_at..]
    ))
}

fn replace_first_set_size_call(editor_source: &str, replacement: &str) -> Option<String> {
    let call_start = editor_source.find("setSize")?;
    let open_paren = editor_source[call_start..].find('(')? + call_start;
    let mut depth = 0;
    let mut close_paren = None;

    for (offset, ch) in editor_source[open_paren..].char_indices() {
        match ch {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if depth == 0 {
                    close_paren = Some(open_paren + offset);
                    break;
                }
            }
            _ => {}
        }
    }

    let mut call_end = close_paren? + 1;
    if editor_source[call_end..].starts_with(';') {
        call_end += 1;
    }

    Some(format!(
        "{}{}{}",
        &editor_source[..call_start],
        replacement,
        &editor_source[call_end..]
    ))
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

fn uses_multi_zone_editor_layout(editor_source: &str) -> bool {
    let uses_horizontal_split =
        editor_source.contains("removeFromLeft") || editor_source.contains("removeFromRight");
    let uses_layout_system = editor_source.contains("juce::Grid")
        || editor_source.contains("juce::FlexBox")
        || editor_source.contains("juce::TabbedComponent");

    uses_horizontal_split || uses_layout_system
}

fn uses_scrolling_ui(editor_source: &str) -> bool {
    editor_source.contains("juce::Viewport")
        || editor_source.contains("juce::ScrollBar")
        || editor_source.contains("setViewedComponent")
        || editor_source.contains("setScrollBarsShown")
        || editor_source.contains("setScrollBarThickness")
}

fn visible_control_count(editor_source: &str) -> usize {
    [
        "setupKnob",
        "setupVSlider",
        "setupHSlider",
        "setupCombo",
        "setupButton",
        "addAndMakeVisible",
    ]
    .iter()
    .map(|needle| editor_source.matches(needle).count())
    .sum()
}

fn uses_control_paging(editor_source: &str) -> bool {
    editor_source.contains("juce::TabbedComponent")
        || editor_source.contains("juce::ButtonBar")
        || editor_source.contains("juce::StackedLayout")
        || editor_source.contains("juce::ConcertinaPanel")
        || editor_source.contains("page")
        || editor_source.contains("tab")
        || editor_source.contains("viewMode")
        || editor_source.contains("currentPage")
}

fn should_run_ui_recovery(missing_files: &[&str], validation_issues: &[String]) -> bool {
    missing_files
        .iter()
        .any(|path| path.contains("PluginEditor") || path.contains("FoundryLookAndFeel"))
        || validation_issues.iter().any(|issue| {
            issue.contains("Editor")
                || issue.contains("FoundryLookAndFeel")
                || issue.contains("Viewport")
                || issue.contains("multi-zone")
                || issue.contains("single vertical stack")
                || issue.contains("High-density editors")
        })
}

fn build_ui_recovery_prompt(
    plugin_name: &str,
    plugin_role: &str,
    user_prompt: &str,
    channel_layout: &str,
    creative_profile: &CreativeProfile,
    parameter_manifest: &[String],
    debug_context: Option<&GenerationDebugContext>,
    missing_files: &[&str],
    validation_issues: &[String],
) -> String {
    let parameter_block = if parameter_manifest.is_empty() {
        "- Read the processor files and reuse the existing parameter IDs exactly. Do not invent new IDs."
            .to_string()
    } else {
        parameter_manifest
            .iter()
            .map(|entry| format!("- {}", entry))
            .collect::<Vec<_>>()
            .join("\n")
    };

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
    let debug_context_section = render_debug_context_section(debug_context);

    format!(
        r#"
Rebuild the UI for an existing JUCE {role} plugin called "{name}".

User brief: {prompt}
Channel layout: {channels}
{debug_context_section}

Read these files first:
- Source/PluginProcessor.h
- Source/PluginProcessor.cpp
- Source/PluginEditor.h (if it exists)
- Source/PluginEditor.cpp (if it exists)
- Source/FoundryLookAndFeel.h (if it exists)

Then repair only these files:
- Source/FoundryLookAndFeel.h
- Source/PluginEditor.h
- Source/PluginEditor.cpp

Keep the processor intact unless a tiny UI-wiring fix is absolutely required for parameter ID alignment.

Known parameter IDs:
{parameter_block}

Missing files:
{missing}

Validation issues:
{validation}

Creative direction:
- UI direction: {ui_direction}
- Control strategy: {control_strategy}
- Visualization focus: {visualization_focus}
- Control palette: {control_palette}
- Anti-template warning: {anti_template_warning}

Rules:
- Start with one short sentence, then read the processor files immediately.
- Rebuild the UI from the real DSP and parameter manifest, not from a generic synth template.
- Treat UI/layout details in the brief as inspiration, not a literal wireframe, unless the user explicitly asked for an exact replica.
- Every visible control must map to a real APVTS parameter and attachment.
- All three UI files must exist when you finish.
- In `PluginEditor.cpp`, the constructor must contain `setSize({editor_width}, {editor_height});` or another explicit numeric landscape size of similar generosity.
- Do not use named constants, helper variables, or portrait dimensions for `setSize(...)`.
- Use `getLocalBounds()` flow, `juce::Grid`, or `juce::FlexBox`.
- Build a multi-zone landscape editor. Do not use `juce::Viewport`, `juce::ScrollBar`, or a single tall control column.
- If there are many controls, use tabs, pages, or alternate views instead of a giant one-page surface.
- Use a meaningful graph, meter, scope, waveform, or curve display whenever the DSP suggests one.
- Keep class names exactly `{name}Processor` and `{name}Editor`.
- Do not touch CMakeLists.txt.

Finish only when the UI source tree is complete and valid.
"#,
        role = plugin_role,
        name = plugin_name,
        prompt = user_prompt,
        channels = channel_layout,
        debug_context_section = debug_context_section,
        parameter_block = parameter_block,
        missing = missing_section,
        validation = validation_section,
        ui_direction = creative_profile.ui_direction,
        control_strategy = creative_profile.control_strategy,
        visualization_focus = creative_profile.visualization_focus,
        control_palette = creative_profile.control_palette,
        anti_template_warning = creative_profile.anti_template_warning,
        editor_width = creative_profile.editor_width,
        editor_height = creative_profile.editor_height,
    )
}

fn build_generation_repair_prompt(
    plugin_name: &str,
    plugin_role: &str,
    user_prompt: &str,
    channel_layout: &str,
    creative_profile: &CreativeProfile,
    debug_context: Option<&GenerationDebugContext>,
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
    let debug_context_section = render_debug_context_section(debug_context);

    format!(
        r#"
Repair an incomplete or inconsistent JUCE {role} plugin called "{name}".

User brief: {prompt}
Channel layout: {channels}
{debug_context_section}

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
- Keep the creative direction specific:
  - UI direction: {ui_direction}
  - Visualization focus: {visualization_focus}
  - Control palette: {control_palette}
  - Anti-template warning: {anti_template_warning}
- UI must use a generous landscape editor size with consistent padding, spacing, non-overlapping controls, and no scrolling.
- In `PluginEditor.cpp`, the constructor must contain an explicit numeric call like `setSize({editor_width}, {editor_height});`.
- Do not use named constants, helper variables, or portrait dimensions for that `setSize(...)` call.
- UI layout must come from `getLocalBounds()` flow, `juce::Grid`, or `juce::FlexBox`, not arbitrary scattered coordinates.
- Do not use `juce::Viewport`, `juce::ScrollBar`, or a single tall control column. The editor must feel like a composed multi-zone instrument panel.
- Use more than one control family when the brief allows it, and draw a curve, graph, meter, scope, or motion display when the DSP implies one.
- Remove any leftover `FoundryPlugin` placeholder text.
- Do not touch CMakeLists.txt.

Finish only when all required files exist and the source tree is consistent.
"#,
        role = plugin_role,
        name = plugin_name,
        prompt = user_prompt,
        channels = channel_layout,
        debug_context_section = debug_context_section,
        ui_direction = creative_profile.ui_direction,
        visualization_focus = creative_profile.visualization_focus,
        control_palette = creative_profile.control_palette,
        anti_template_warning = creative_profile.anti_template_warning,
        editor_width = creative_profile.editor_width,
        editor_height = creative_profile.editor_height,
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
        assert!(a.editor_width >= 860);
        assert!(a.editor_height >= 560);
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

        let creative_profile = infer_creative_profile("Flux", "effect", "Wide chorus");
        let issues = validate_generated_source_tree(&dir, "Flux", &creative_profile);

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

        let creative_profile = infer_creative_profile("Flux", "effect", "Wide chorus");
        let issues = validate_generated_source_tree(&dir, "Flux", &creative_profile);

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

        let creative_profile = infer_creative_profile("Flux", "effect", "Wide chorus");
        let issues = validate_generated_source_tree(&dir, "Flux", &creative_profile);

        assert!(issues
            .iter()
            .any(|issue| issue.contains("reasonable fixed window size")));
        assert!(issues
            .iter()
            .any(|issue| issue.contains("landscape window")));
        assert!(issues.iter().any(|issue| issue.contains("getLocalBounds")));
        assert!(issues
            .iter()
            .any(|issue| issue.contains("multi-zone landscape layout")));

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn normalize_editor_size_repairs_non_literal_or_portrait_sizes() {
        let dir = make_temp_dir();
        let creative_profile = infer_creative_profile("Flux", "effect", "Wide chorus");

        std::fs::write(
            dir.join("Source/PluginEditor.cpp"),
            "#include \"PluginEditor.h\"\nFluxEditor::FluxEditor() : audioProcessor(processor) { setSize(editorWidth, editorHeight); }\n",
        )
        .unwrap();

        assert!(normalize_generated_editor_size(
            &dir,
            "Flux",
            &creative_profile
        ));

        let repaired = std::fs::read_to_string(dir.join("Source/PluginEditor.cpp")).unwrap();
        assert!(repaired.contains("setSize(920, 600);"));
        assert_eq!(extract_editor_size(&repaired), Some((920, 600)));

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn ui_prompts_require_explicit_numeric_landscape_size() {
        let creative_profile = infer_creative_profile("Flux", "effect", "Wide chorus");
        let parameter_manifest = vec!["mix".to_string()];

        let fast_ui = build_fast_ui_prompt(
            "Flux",
            "audio effect",
            "effect",
            "Wide chorus",
            "stereo",
            &creative_profile,
            &parameter_manifest,
            None,
        );
        let emergency_ui =
            build_emergency_ui_prompt("Flux", &parameter_manifest, &creative_profile, None);
        let repair = build_generation_repair_prompt(
            "Flux",
            "audio effect",
            "Wide chorus",
            "stereo",
            &creative_profile,
            None,
            &[],
            &["Editor must call setSize(...) with an explicit landscape window size".into()],
        );

        for prompt in [fast_ui, emergency_ui, repair] {
            assert!(prompt.contains("setSize(920, 600);"));
            assert!(prompt.contains("named constants"));
            assert!(prompt.contains("juce::Viewport"));
        }
    }

    #[test]
    fn phase_prompts_load_foundry_kit_skills() {
        let creative_profile = infer_creative_profile("Flux", "effect", "Wide chorus");
        let parameter_manifest = vec!["mix".to_string()];

        let processor = build_fast_processor_prompt(
            "Flux",
            "audio effect",
            "effect",
            "Wide chorus",
            "stereo",
            &creative_profile,
            None,
        );
        let ui = build_fast_ui_prompt(
            "Flux",
            "audio effect",
            "effect",
            "Wide chorus",
            "stereo",
            &creative_profile,
            &parameter_manifest,
            None,
        );

        // Skills are inlined into CLAUDE.md via include_str!() — no Read instructions needed
        assert!(!processor.contains("Before writing any code, read `foundry-kit"));
        assert!(!ui.contains("Before writing any code, read `foundry-kit"));
    }

    #[test]
    fn ui_recovery_prompt_reads_processor_and_repairs_ui_only() {
        let creative_profile = infer_creative_profile("Flux", "effect", "Wide chorus");
        let prompt = build_ui_recovery_prompt(
            "Flux",
            "audio effect",
            "Wide chorus",
            "stereo",
            &creative_profile,
            &["mix".to_string(), "depth".to_string()],
            None,
            &["Source/PluginEditor.cpp"],
            &["Editor must call setSize(...) with an explicit landscape window size".into()],
        );

        assert!(prompt.contains("Source/PluginProcessor.h"));
        assert!(prompt.contains("Source/PluginProcessor.cpp"));
        assert!(prompt.contains("Then repair only these files:"));
        assert!(prompt.contains("Source/PluginEditor.cpp"));
        assert!(prompt.contains("Rebuild the UI from the real DSP"));
    }

    #[test]
    fn debug_retry_prompts_include_previous_failure_context() {
        let creative_profile = infer_creative_profile("Flux", "effect", "Wide chorus");
        let debug_context = GenerationDebugContext {
            trigger: "retry-after-failure".into(),
            previous_error: "Generated source tree is still invalid after recovery".into(),
            recent_logs: vec![
                "[12:00:01] Generation needs repair".into(),
                "[12:00:02] Missing: Source/PluginEditor.cpp".into(),
            ],
        };

        let prompt = build_debug_retry_plan_prompt(
            "Flux",
            "audio effect",
            "effect",
            "Wide chorus",
            "stereo",
            &creative_profile,
            &debug_context,
        );

        assert!(prompt.contains("## DEBUG RETRY CONTEXT"));
        assert!(prompt.contains("Generated source tree is still invalid after recovery"));
        assert!(prompt.contains("Source/PluginEditor.cpp"));
        assert!(prompt.contains("single vertical stack"));
    }

    #[test]
    fn validation_reports_scroll_based_editors() {
        let dir = make_temp_dir();
        let creative_profile = infer_creative_profile("Flux", "effect", "Wide chorus");

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
            "#include <JuceHeader.h>\nclass FluxEditor { class FoundryLookAndFeel* lnf; using SliderAttachment = juce::AudioProcessorValueTreeState::SliderAttachment; juce::Viewport viewport; };",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/PluginEditor.cpp"),
            "#include \"PluginEditor.h\"\nFluxEditor::FluxEditor() { setSize(920, 600); viewport.setViewedComponent(nullptr, false); }\nvoid FluxEditor::resized() { auto bounds = getLocalBounds().reduced(24); auto hero = bounds.removeFromTop(240); auto side = bounds.removeFromRight(220); }\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/FoundryLookAndFeel.h"),
            "#include <JuceHeader.h>\nclass FoundryLookAndFeel {};",
        )
        .unwrap();

        let issues = validate_generated_source_tree(&dir, "Flux", &creative_profile);

        assert!(issues
            .iter()
            .any(|issue| issue.contains("must not rely on Viewport or scroll bars")));

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn validation_reports_dense_single_surface_editors() {
        let dir = make_temp_dir();
        let creative_profile = infer_creative_profile("Flux", "effect", "Huge synth workstation");

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
            "#include \"PluginEditor.h\"\nFluxEditor::FluxEditor() { setSize(1100, 700); setupKnob(a,b,\"1\"); setupKnob(c,d,\"2\"); setupKnob(e,f,\"3\"); setupKnob(g,h,\"4\"); setupKnob(i,j,\"5\"); setupKnob(k,l,\"6\"); setupKnob(m,n,\"7\"); setupKnob(o,p,\"8\"); setupKnob(q,r,\"9\"); setupKnob(s,t,\"10\"); setupKnob(u,v,\"11\"); setupKnob(w,x,\"12\"); setupKnob(y,z,\"13\"); setupVSlider(a1,b1,\"14\"); setupVSlider(a2,b2,\"15\"); setupVSlider(a3,b3,\"16\"); setupVSlider(a4,b4,\"17\"); setupVSlider(a5,b5,\"18\"); setupCombo(c1,d1,\"19\"); setupCombo(c2,d2,\"20\"); setupCombo(c3,d3,\"21\"); setupButton(btn1,\"22\"); setupButton(btn2,\"23\"); setupButton(btn3,\"24\"); setupButton(btn4,\"25\"); }\nvoid FluxEditor::resized() { auto bounds = getLocalBounds().reduced(24); auto left = bounds.removeFromLeft(300); auto mid = bounds.removeFromLeft(300); auto right = bounds; }\n",
        )
        .unwrap();
        std::fs::write(
            dir.join("Source/FoundryLookAndFeel.h"),
            "#include <JuceHeader.h>\nclass FoundryLookAndFeel {};",
        )
        .unwrap();

        let issues = validate_generated_source_tree(&dir, "Flux", &creative_profile);

        assert!(issues
            .iter()
            .any(|issue| issue
                .contains("High-density editors must use tabs, pages, or alternate views")));

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
