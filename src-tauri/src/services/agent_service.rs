//! Unified agent dispatcher.
//!
//! Routes `run` and `fix` calls to either `claude_code_service` or `codex_service`
//! based on the agent identifier, allowing the generation pipeline to be backend-agnostic.

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
            codex_service::run(
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

/// Run a fix pass for build errors, dispatching to the correct backend.
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
