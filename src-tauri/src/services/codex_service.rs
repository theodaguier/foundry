use std::path::Path;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

use crate::services::claude_code_service::{ClaudeEvent, RunResult};

/// Resolved path of the `codex` CLI binary.
pub fn resolve_codex_path() -> Option<String> {
    crate::platform::resolve_codex_path()
}

/// Run Codex CLI with JSONL output, parsing events in real time.
///
/// The interface mirrors `claude_code_service::run` so the pipeline can
/// dispatch to either backend transparently.
pub async fn run(
    codex_path: &str,
    prompt: &str,
    project_dir: &str,
    model_flag: &str,
    mode: &str,
    on_event: impl Fn(ClaudeEvent) + Send + 'static,
    mut cancel_rx: tokio::sync::watch::Receiver<bool>,
) -> RunResult {
    const IDLE_HEARTBEAT_SECS: u64 = 60;

    // Codex has no --append-system-prompt, so we bake the system instructions
    // into the prompt itself.
    let system_instructions = mode_system_instructions(mode);
    let full_prompt = if system_instructions.is_empty() {
        prompt.to_string()
    } else {
        format!("{}\n\n---\n\n{}", system_instructions, prompt)
    };

    let max_turns = mode_max_turns(mode);

    // Build the codex exec command
    let mut args = vec![
        "exec".to_string(),
        full_prompt.clone(),
        "--json".to_string(),
        "--dangerously-bypass-approvals-and-sandbox".to_string(),
        "-C".to_string(),
        project_dir.to_string(),
        "-m".to_string(),
        model_flag.to_string(),
    ];

    // Codex doesn't have --max-turns, but we track turns ourselves
    // and kill the process if it exceeds the limit.
    let turn_limit: i64 = max_turns.parse().unwrap_or(50);

    // For generate modes, add --ephemeral to avoid session persistence
    if mode.starts_with("generate") || mode == "plan" {
        args.push("--ephemeral".to_string());
    }

    let env = crate::services::claude_code_service::shell_environment();

    // Codex hangs when stdin is /dev/null — it needs a pipe that closes immediately.
    let mut child = match Command::new(codex_path)
        .args(&args)
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            let msg = format!("Failed to launch Codex CLI: {}", e);
            on_event(ClaudeEvent::Error(msg.clone()));
            return RunResult {
                success: false,
                output: String::new(),
                error: Some(msg),
                input_tokens: None,
                output_tokens: None,
                cache_read_tokens: None,
                cost_usd: None,
                num_turns: None,
            };
        }
    };

    // Close stdin immediately so Codex gets EOF (it hangs on /dev/null)
    drop(child.stdin.take());

    on_event(ClaudeEvent::Text(format!(
        "MODEL SESSION · provider=codex · mode={} · model={} · max-turns={}",
        mode, model_flag, turn_limit
    )));

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();
    let mut stdout_reader = BufReader::new(stdout).lines();
    let mut stderr_reader = BufReader::new(stderr).lines();

    let mut all_output = String::new();
    let mut stderr_output = String::new();
    let mut stdout_done = false;
    let mut stderr_done = false;
    let mut last_activity = std::time::Instant::now();
    let mut last_heartbeat_second = 0;
    let mut saw_expected_outputs = expected_output_files_exist(project_dir, mode);
    let mut current_turns: i64 = 0;

    // Captured from turn.completed events
    let mut total_input_tokens: i64 = 0;
    let mut total_output_tokens: i64 = 0;
    let mut total_cached_tokens: i64 = 0;
    let mut final_success = true; // Codex doesn't have explicit success/failure in events
    let mut structured_error: Option<String> = None;

    let watchdog_secs: u64 = 1800;
    let no_write_timeout_secs: Option<u64> = None;
    let watchdog = tokio::time::sleep(std::time::Duration::from_secs(watchdog_secs));
    tokio::pin!(watchdog);
    let mut heartbeat = tokio::time::interval(std::time::Duration::from_secs(IDLE_HEARTBEAT_SECS));

    loop {
        if stdout_done && stderr_done {
            break;
        }

        tokio::select! {
            biased;

            _ = cancel_rx.changed() => {
                if *cancel_rx.borrow() {
                    let _ = child.kill().await;
                    return RunResult {
                        success: false, output: all_output, error: Some("Cancelled".into()),
                        input_tokens: None, output_tokens: None, cache_read_tokens: None, cost_usd: None, num_turns: None,
                    };
                }
            }

            _ = &mut watchdog => {
                on_event(ClaudeEvent::Error(format!(
                    "Process killed by {}s watchdog",
                    watchdog_secs
                )));
                let _ = child.kill().await;
                return RunResult {
                    success: false, output: all_output, error: Some("Watchdog timeout".into()),
                    input_tokens: None, output_tokens: None, cache_read_tokens: None, cost_usd: None, num_turns: None,
                };
            }

            _ = heartbeat.tick() => {
                let idle_for = last_activity.elapsed().as_secs();
                if idle_for >= IDLE_HEARTBEAT_SECS && idle_for != last_heartbeat_second {
                    last_heartbeat_second = idle_for;
                    on_event(ClaudeEvent::Text(format!(
                        "Heartbeat: no new Codex output for {}s. The model is likely drafting files or waiting for a tool result.",
                        idle_for
                    )));
                }
            }

            line = stdout_reader.next_line(), if !stdout_done => {
                match line {
                    Ok(Some(text)) => {
                        last_activity = std::time::Instant::now();
                        last_heartbeat_second = 0;
                        all_output.push_str(&text);
                        all_output.push('\n');

                        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                            match json["type"].as_str() {
                                Some("turn.failed") => {
                                    structured_error = json["error"]["message"]
                                        .as_str()
                                        .map(str::trim)
                                        .filter(|message| !message.is_empty())
                                        .map(ToOwned::to_owned)
                                        .or_else(|| structured_error.take());
                                }
                                Some("error") => {
                                    structured_error = json["message"]
                                        .as_str()
                                        .or_else(|| json["error"].as_str())
                                        .map(str::trim)
                                        .filter(|message| !message.is_empty())
                                        .map(ToOwned::to_owned)
                                        .or_else(|| structured_error.take());
                                }
                                _ => {}
                            }
                        }

                        for event in parse_codex_events(&text, &mut current_turns, &mut total_input_tokens, &mut total_output_tokens, &mut total_cached_tokens, &mut final_success) {
                            on_event(event);
                        }

                        if !saw_expected_outputs {
                            saw_expected_outputs = expected_output_files_exist(project_dir, mode);
                        }

                        // Kill if we've exceeded turn limit
                        if current_turns >= turn_limit {
                            on_event(ClaudeEvent::Text(format!(
                                "Turn limit reached ({}/{}), stopping Codex.",
                                current_turns, turn_limit
                            )));
                            let _ = child.kill().await;
                            stdout_done = true;
                            stderr_done = true;
                        }
                    }
                    Ok(None) => stdout_done = true,
                    Err(e) => {
                        last_activity = std::time::Instant::now();
                        stderr_output.push_str(&format!("Failed to read Codex stdout: {}\n", e));
                        stdout_done = true;
                    }
                }
            }

            line = stderr_reader.next_line(), if !stderr_done => {
                match line {
                    Ok(Some(text)) => {
                        last_activity = std::time::Instant::now();
                        last_heartbeat_second = 0;
                        stderr_output.push_str(&text);
                        stderr_output.push('\n');
                        let trimmed = text.trim();
                        if !trimmed.is_empty() {
                            on_event(ClaudeEvent::Stderr(trimmed.to_string()));
                        }
                    }
                    Ok(None) => stderr_done = true,
                    Err(e) => {
                        last_activity = std::time::Instant::now();
                        stderr_output.push_str(&format!("Failed to read Codex stderr: {}\n", e));
                        stderr_done = true;
                    }
                }
            }
        }
    }

    let status = child.wait().await;
    let exit_ok = status.map(|s| s.success()).unwrap_or(false);

    let error = if exit_ok && final_success {
        None
    } else if !stderr_output.trim().is_empty() {
        Some(stderr_output.trim().to_string())
    } else if let Some(message) = structured_error {
        Some(message)
    } else if !all_output.trim().is_empty() {
        Some("Codex CLI exited with error; see stdout for details".into())
    } else {
        Some("Codex CLI exited with error".into())
    };

    RunResult {
        success: exit_ok && final_success,
        output: all_output,
        error,
        input_tokens: if total_input_tokens > 0 {
            Some(total_input_tokens)
        } else {
            None
        },
        output_tokens: if total_output_tokens > 0 {
            Some(total_output_tokens)
        } else {
            None
        },
        cache_read_tokens: if total_cached_tokens > 0 {
            Some(total_cached_tokens)
        } else {
            None
        },
        cost_usd: None, // Codex JSONL doesn't report cost
        num_turns: Some(current_turns),
    }
}

/// Run Codex for a fix pass (build errors).
pub async fn fix(
    codex_path: &str,
    errors: &str,
    project_dir: &str,
    attempt: i32,
    model_flag: &str,
    on_event: impl Fn(ClaudeEvent) + Send + 'static,
    cancel_rx: tokio::sync::watch::Receiver<bool>,
) -> RunResult {
    let prompt = format!(
        "Build failed (attempt {}). Fix the errors below.\n\
        If files are missing, create them. If code has errors, fix them.\n\
        Read AGENTS.md for the full plugin spec. Only edit Source/ files. Do NOT touch CMakeLists.txt.\n\n\
        Errors:\n{}",
        attempt, errors
    );
    run(
        codex_path,
        &prompt,
        project_dir,
        model_flag,
        "refine",
        on_event,
        cancel_rx,
    )
    .await
}

// ---- Codex JSONL event parsing ----

/// Parse a single JSONL line from Codex and convert to ClaudeEvent(s).
///
/// Codex emits these event types:
/// - `thread.started` — session begins
/// - `turn.started` — new agent turn
/// - `item.started` — item in progress (command, file change)
/// - `item.completed` — item finished (agent_message, command_execution, file_change, reasoning, error)
/// - `turn.completed` — turn finished with usage stats
/// - `turn.failed` — turn failed
/// - `error` — general error
fn parse_codex_events(
    line: &str,
    current_turns: &mut i64,
    total_input_tokens: &mut i64,
    total_output_tokens: &mut i64,
    total_cached_tokens: &mut i64,
    final_success: &mut bool,
) -> Vec<ClaudeEvent> {
    if line.is_empty() {
        return vec![];
    }
    let json: serde_json::Value = match serde_json::from_str(line) {
        Ok(v) => v,
        Err(_) => return vec![],
    };

    let event_type = json["type"].as_str().unwrap_or("");
    let mut events = Vec::new();

    match event_type {
        "thread.started" => {
            let thread_id = json["thread_id"].as_str().unwrap_or("?");
            events.push(ClaudeEvent::Text(format!(
                "Codex session started · thread={}",
                &thread_id[..thread_id.len().min(12)]
            )));
        }

        "turn.started" => {
            *current_turns += 1;
            events.push(ClaudeEvent::Text(format!("Turn {} started", current_turns)));
        }

        // item.started — show in-progress commands and file changes
        "item.started" => {
            let item = &json["item"];
            let item_type = item["type"].as_str().unwrap_or("");

            match item_type {
                "command_execution" => {
                    if let Some(cmd) = item["command"].as_str() {
                        // Strip the shell wrapper to show the actual command
                        let display_cmd = cmd
                            .strip_prefix("/bin/zsh -lc ")
                            .or_else(|| cmd.strip_prefix("/bin/bash -lc "))
                            .unwrap_or(cmd)
                            .trim_matches('\'')
                            .trim_matches('"');
                        events.push(ClaudeEvent::ToolUse {
                            tool: "command".to_string(),
                            file_path: None,
                            detail: Some(truncate(display_cmd, 80)),
                        });
                    }
                }
                _ => {}
            }
        }

        // item.completed — the main event type for Codex output
        "item.completed" => {
            let item = &json["item"];
            let item_type = item["type"].as_str().unwrap_or("");

            match item_type {
                "agent_message" => {
                    if let Some(text) = item["text"].as_str() {
                        let trimmed = text.trim();
                        if !trimmed.is_empty() {
                            events.push(ClaudeEvent::Text(trimmed.to_string()));
                        }
                    }
                }

                "reasoning" => {
                    if let Some(text) = item["text"].as_str() {
                        let trimmed = text.trim();
                        if !trimmed.is_empty() {
                            events.push(ClaudeEvent::StreamingText(format!(
                                "[reasoning] {}",
                                trimmed
                            )));
                        }
                    }
                }

                "command_execution" => {
                    let cmd = item["command"].as_str().unwrap_or("command");
                    let display_cmd = cmd
                        .strip_prefix("/bin/zsh -lc ")
                        .or_else(|| cmd.strip_prefix("/bin/bash -lc "))
                        .unwrap_or(cmd)
                        .trim_matches('\'')
                        .trim_matches('"');
                    let exit_code = item["exit_code"].as_i64().unwrap_or(-1);
                    let output = item["aggregated_output"].as_str().unwrap_or("");

                    // Emit as ToolUse so the pipeline sees the activity
                    events.push(ClaudeEvent::ToolUse {
                        tool: "command".to_string(),
                        file_path: None,
                        detail: Some(format!(
                            "{} (exit {})",
                            truncate(display_cmd, 60),
                            exit_code
                        )),
                    });

                    if !output.is_empty() {
                        // Show truncated output
                        let output_preview = truncate(output.trim(), 200);
                        events.push(ClaudeEvent::ToolResult {
                            tool: "command".to_string(),
                            output: output_preview,
                        });
                    }
                }

                "file_change" => {
                    if let Some(changes) = item["changes"].as_array() {
                        for change in changes {
                            let path = change["path"].as_str().unwrap_or("unknown");
                            let kind = change["kind"].as_str().unwrap_or("modify");
                            let filename = path.rsplit('/').next().unwrap_or(path);

                            let tool_name = match kind {
                                "add" => "Write",
                                "delete" => "Delete",
                                _ => "Edit",
                            };

                            events.push(ClaudeEvent::ToolUse {
                                tool: tool_name.to_string(),
                                file_path: Some(path.to_string()),
                                detail: Some(format!("{} {}", kind, filename)),
                            });
                        }
                    }
                }

                "error" => {
                    let msg = item["text"]
                        .as_str()
                        .or_else(|| item["message"].as_str())
                        .unwrap_or("Unknown Codex error");
                    *final_success = false;
                    events.push(ClaudeEvent::Error(msg.to_string()));
                }

                _ => {
                    // Try to extract text from unknown item types
                    if let Some(text) = item["text"].as_str() {
                        let trimmed = text.trim();
                        if !trimmed.is_empty() {
                            events.push(ClaudeEvent::Text(trimmed.to_string()));
                        }
                    }
                }
            }
        }

        "turn.completed" => {
            if let Some(usage) = json.get("usage") {
                *total_input_tokens += usage["input_tokens"].as_i64().unwrap_or(0);
                *total_output_tokens += usage["output_tokens"].as_i64().unwrap_or(0);
                *total_cached_tokens += usage["cached_input_tokens"].as_i64().unwrap_or(0);
            }
            events.push(ClaudeEvent::Text(format!(
                "Done — {} turns, {}+{} tokens",
                current_turns, total_input_tokens, total_output_tokens
            )));
            events.push(ClaudeEvent::Result {
                success: *final_success,
            });
        }

        "turn.failed" => {
            *final_success = false;
            let msg = json["error"]["message"].as_str().unwrap_or("Turn failed");
            events.push(ClaudeEvent::Error(msg.to_string()));
            events.push(ClaudeEvent::Result { success: false });
        }

        "error" => {
            *final_success = false;
            let msg = json["message"]
                .as_str()
                .or_else(|| json["error"].as_str())
                .unwrap_or("Codex error");
            events.push(ClaudeEvent::Error(msg.to_string()));
        }

        _ => {}
    }

    events
}

fn truncate(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else {
        format!("{}…", &s[..max_len])
    }
}

fn expected_output_files_exist(project_dir: &str, mode: &str) -> bool {
    let required_files: &[&str] = match mode {
        "generate" => &[
            "Source/PluginProcessor.h",
            "Source/PluginProcessor.cpp",
            "Source/FoundryLookAndFeel.h",
            "Source/PluginEditor.h",
            "Source/PluginEditor.cpp",
        ],
        "generate_processor" => &["Source/PluginProcessor.h", "Source/PluginProcessor.cpp"],
        "generate_ui" => &[
            "Source/FoundryLookAndFeel.h",
            "Source/PluginEditor.h",
            "Source/PluginEditor.cpp",
        ],
        _ => &[],
    };

    if required_files.is_empty() {
        return false;
    }

    let root = Path::new(project_dir);
    required_files
        .iter()
        .all(|relative| root.join(relative).exists())
}

/// Minimal system instructions baked into the prompt for Codex.
/// The real context is in the AGENTS.md content prepended by agent_service.
fn mode_system_instructions(mode: &str) -> &'static str {
    match mode {
        "generate" => "Build a complete JUCE plugin. The prompt contains the full spec and expert knowledge. Write all Source/ files. Do NOT touch CMakeLists.txt.",
        "refine" => "Modify an existing JUCE plugin. Read the Source/ files, then apply targeted changes. Do NOT touch CMakeLists.txt.",
        _ => "Fix the errors in this JUCE plugin. Only edit Source/ files. Do NOT touch CMakeLists.txt.",
    }
}

/// Max turns for local enforcement (Codex has no --max-turns flag).
fn mode_max_turns(mode: &str) -> &'static str {
    match mode {
        "generate" => "8",
        "refine" => "6",
        _ => "6",
    }
}

#[cfg(test)]
mod tests {
    use super::expected_output_files_exist;

    fn make_temp_dir() -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("foundry-codex-test-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(dir.join("Source")).unwrap();
        dir
    }

    #[test]
    fn generate_processor_requires_both_processor_files() {
        let dir = make_temp_dir();
        std::fs::write(dir.join("Source/PluginProcessor.h"), "// header").unwrap();
        assert!(!expected_output_files_exist(
            dir.to_str().unwrap(),
            "generate_processor"
        ));

        std::fs::write(dir.join("Source/PluginProcessor.cpp"), "// source").unwrap();
        assert!(expected_output_files_exist(
            dir.to_str().unwrap(),
            "generate_processor"
        ));

        let _ = std::fs::remove_dir_all(dir);
    }
}
