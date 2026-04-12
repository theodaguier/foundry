//! Unified agent dispatcher.
//!
//! Routes `run` and `fix` calls to either `claude_code_service` or `codex_service`
//! based on the agent identifier, allowing the generation pipeline to be backend-agnostic.
//! 
//! Also provides sub-agent orchestration for the skill-based pipeline:
//! - Planner: analyzes brief and creates implementation plan
//! - Dsp: generates PluginProcessor.h/.cpp
//! - Ui: generates PluginEditor.h/.cpp and FoundryLookAndFeel.h
//! - Review: validates generated code
//! - BuildFix: fixes compilation errors

use crate::models::agent::{SkillId, SubagentRole, skills_for_plugin_type, skills_to_load};
use crate::services::{claude_code_service, codex_service};
pub use claude_code_service::{ClaudeEvent, RunResult};

/// Resolve the CLI path for the given agent.
pub fn resolve_agent_path(agent: &str) -> Option<String> {
    match normalized_agent(agent) {
        "codex" => codex_service::resolve_codex_path(),
        _ => claude_code_service::resolve_claude_path(),
    }
}

/// Human-readable agent name for log messages.
pub fn agent_display_name(agent: &str) -> &'static str {
    match normalized_agent(agent) {
        "codex" => "Codex",
        _ => "Claude Code",
    }
}

/// Run the agent CLI with the given prompt, dispatching to the correct backend.
///
/// For Codex, the AGENTS.md file is prepended to the prompt since Codex
/// doesn't read project files automatically (unlike Claude Code which reads
/// CLAUDE.md from the working directory).
#[allow(clippy::too_many_arguments)]
pub async fn run(
    agent: &str,
    cli_path: &str,
    prompt: &str,
    project_dir: &str,
    model_flag: &str,
    mode: &str,
    on_event: impl Fn(ClaudeEvent) + Send + 'static,
    cancel_rx: tokio::sync::watch::Receiver<bool>,
) -> RunResult {
    match normalized_agent(agent) {
        "codex" => {
            let enriched_prompt = enrich_prompt_for_codex(prompt, project_dir);
            codex_service::run(
                cli_path,
                &enriched_prompt,
                project_dir,
                model_flag,
                mode,
                on_event,
                cancel_rx,
            )
            .await
        }
        _ => {
            claude_code_service::run(
                cli_path,
                prompt,
                project_dir,
                model_flag,
                mode,
                on_event,
                cancel_rx,
            )
            .await
        }
    }
}

/// Prepend AGENTS.md content to the prompt so Codex has full context.
///
/// The content is clearly framed so the model knows it is the mission brief
/// and does not try to read CLAUDE.md (which contains the same content on disk).
fn enrich_prompt_for_codex(prompt: &str, project_dir: &str) -> String {
    let agents_md_path = std::path::Path::new(project_dir).join("AGENTS.md");
    match std::fs::read_to_string(&agents_md_path) {
        Ok(agents_md) => format!(
            "# MISSION BRIEF (your full spec — do not read CLAUDE.md, it is a duplicate)\n\n\
            {agents_md}\n\n\
            ---\n\n\
            # TASK\n\n\
            {prompt}",
            agents_md = agents_md,
            prompt = prompt,
        ),
        Err(_) => prompt.to_string(),
    }
}

/// Run a fix pass for build errors, dispatching to the correct backend.
#[allow(clippy::too_many_arguments)]
pub async fn fix(
    agent: &str,
    cli_path: &str,
    errors: &str,
    project_dir: &str,
    attempt: i32,
    model_flag: &str,
    on_event: impl Fn(ClaudeEvent) + Send + 'static,
    cancel_rx: tokio::sync::watch::Receiver<bool>,
) -> RunResult {
    match normalized_agent(agent) {
        "codex" => {
            codex_service::fix(
                cli_path,
                errors,
                project_dir,
                attempt,
                model_flag,
                on_event,
                cancel_rx,
            )
            .await
        }
        _ => {
            claude_code_service::fix(
                cli_path,
                errors,
                project_dir,
                attempt,
                model_flag,
                on_event,
                cancel_rx,
            )
            .await
        }
    }
}

/// Normalize agent identifier to a canonical form.
fn normalized_agent(agent: &str) -> &'static str {
    if agent.to_ascii_lowercase().contains("codex") {
        "codex"
    } else {
        "claude"
    }
}

/// Run a sub-agent with a specific role for the skill-based pipeline.
/// 
/// This is the core abstraction that enables identical behavior across Claude and Codex.
#[allow(clippy::too_many_arguments)]
pub async fn run_subagent(
    agent: &str,
    cli_path: &str,
    role: SubagentRole,
    prompt: &str,
    project_dir: &str,
    model_flag: &str,
    on_event: impl Fn(ClaudeEvent) + Send + 'static,
    cancel_rx: tokio::sync::watch::Receiver<bool>,
) -> RunResult {
    let mode = role.as_str();
    let full_prompt = format!(
        "{}\n\n## CONTEXT\nProject: {}\nRole: {}\nMax turns: {}",
        prompt,
        project_dir,
        role.system_instruction(),
        role.max_turns()
    );
    
    run(
        agent,
        cli_path,
        &full_prompt,
        project_dir,
        model_flag,
        mode,
        on_event,
        cancel_rx,
    )
    .await
}

/// Build the skills prompt section for a list of skills.
/// This prompt tells the agent which skills to load and apply.
pub fn build_skills_prompt(skills: &[SkillId], plugin_type: &str) -> String {
    let skill_names: Vec<&str> = skills_to_load(skills);
    let skill_list = skill_names.iter().map(|s| format!("- {}", s)).collect::<Vec<_>>().join("\n");
    
    format!(
        "## SKILLS TO LOAD\n\
        Load and apply the following Foundry skills:\n\
        {}\n\n\
        These skills provide expert knowledge for building this {} plugin.\n",
        skill_list, plugin_type
    )
}

/// Get the skills to load for a given plugin type.
pub fn get_skills_for_type(plugin_type: &str) -> Vec<SkillId> {
    skills_for_plugin_type(plugin_type)
}

/// Create a planner prompt that analyzes the user brief and creates an implementation plan.
pub fn build_planner_prompt(
    plugin_name: &str,
    plugin_type: &str,
    user_prompt: &str,
    skills: &[SkillId],
) -> String {
    let skills_section = build_skills_prompt(skills, plugin_type);
    
    format!(
        "# PLANNING PHASE\n\n\
        ## PLUGIN SPEC\n\
        Name: {}\n\
        Type: {}\n\
        User description: {}\n\n\
        {}\n\n\
        ## TASK\n\
        Create a detailed implementation plan:\n\
        1. Identify the required parameters and their types\n\
        2. Define the signal processing architecture\n\
        3. Design the UI layout approach\n\
        4. List any factory presets\n\
        Write the plan to `.foundry/contracts/plan.md` in the project directory.",
        plugin_name, plugin_type, user_prompt, skills_section
    )
}

/// Create a DSP generation prompt.
pub fn build_dsp_prompt(
    plugin_name: &str,
    plugin_type: &str,
    user_prompt: &str,
    plan_manifest: Option<&str>,
    skills: &[SkillId],
) -> String {
    let skills_section = build_skills_prompt(skills, plugin_type);
    let plan_ref = plan_manifest.map(|p| format!("\n## IMPLEMENTATION PLAN\n{}", p)).unwrap_or_default();
    
    format!(
        "# DSP GENERATION PHASE\n\n\
        ## PLUGIN SPEC\n\
        Name: {}\n\
        Type: {}\n\
        User description: {}{}\n\n\
        {}\n\n\
        ## TASK\n\
        Write Source/PluginProcessor.h and Source/PluginProcessor.cpp:\n\
        - Use APVTS for all parameters\n\
        - Implement smooth parameter changes with SmoothedValue\n\
        - Include all signal processing in processBlock\n\
        Write complete, compilable code. Do NOT use placeholders.",
        plugin_name, plugin_type, user_prompt, plan_ref, skills_section
    )
}

/// Create a UI generation prompt.
pub fn build_ui_prompt(
    plugin_name: &str,
    plugin_type: &str,
    user_prompt: &str,
    parameter_manifest: &str,
    skills: &[SkillId],
) -> String {
    let skills_section = build_skills_prompt(skills, plugin_type);
    
    format!(
        "# UI GENERATION PHASE\n\n\
        ## PLUGIN SPEC\n\
        Name: {}\n\
        Type: {}\n\
        User description: {}\n\n\
        ## PARAMETERS (from DSP phase)\n\
        {}\n\n\
        {}\n\n\
        ## TASK\n\
        Write Source/PluginEditor.h, Source/PluginEditor.cpp, and Source/FoundryLookAndFeel.h:\n\
        - Create controls bound to APVTS parameters\n\
        - Design a layout appropriate for the plugin purpose\n\
        - Use explicit setSize(width, height) with landscape dimensions\n\
        Write complete, usable code. Do NOT use placeholders.",
        plugin_name, plugin_type, user_prompt, parameter_manifest, skills_section
    )
}

/// Create a review prompt.
pub fn build_review_prompt(
    plugin_name: &str,
    validation_issues: &[String],
) -> String {
    let issues = if validation_issues.is_empty() {
        "No specific issues reported.".to_string()
    } else {
        validation_issues.iter().map(|i| format!("- {}", i)).collect::<Vec<_>>().join("\n")
    };
    
    format!(
        "# CODE REVIEW PHASE\n\n\
        ## PLUGIN\n\
        {}\n\n\
        ## ISSUES TO CHECK\n\
        {}\n\n\
        ## TASK\n\
        Review the generated Source/ files for:\n\
        - Correct APVTS usage and attachments\n\
        - Proper parameter smoothing\n\
        - Complete UI controls\n\
        - No placeholder code\n\
        Report findings to `.foundry/review/findings.md`.",
        plugin_name, issues
    )
}
