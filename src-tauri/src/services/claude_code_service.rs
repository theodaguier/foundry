use std::process::Stdio;
#[cfg(target_os = "windows")]
use std::path::Path;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

/// Resolved path of the `claude` CLI binary.
pub fn resolve_claude_path() -> Option<String> {
    crate::platform::resolve_claude_path()
}

/// Shell environment inherited by subprocesses.
pub fn shell_environment() -> Vec<(String, String)> {
    crate::platform::shell_environment()
}

#[derive(Debug, Clone)]
pub enum ClaudeEvent {
    ToolUse {
        tool: String,
        file_path: Option<String>,
        detail: Option<String>,
    },
    ToolResult {
        tool: String,
        output: String,
    },
    Text(String),
    StreamingText(String),
    Stderr(String),
    Result {
        success: bool,
    },
    Error(String),
}

pub struct RunResult {
    pub success: bool,
    pub output: String,
    pub error: Option<String>,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub cache_read_tokens: Option<i64>,
    pub cost_usd: Option<f64>,
    pub num_turns: Option<i64>,
}

/// Run Claude Code CLI with stream-json output, parsing events in real time.
pub async fn run(
    claude_path: &str,
    prompt: &str,
    project_dir: &str,
    model_flag: &str,
    mode: &str, // "generate" or "refine"
    on_event: impl Fn(ClaudeEvent) + Send + 'static,
    mut cancel_rx: tokio::sync::watch::Receiver<bool>,
) -> RunResult {
    const IDLE_HEARTBEAT_SECS: u64 = 60;

    // Minimal system prompts — the real context lives in CLAUDE.md and the
    // prompt itself.  The agent is good enough to manage its own workflow;
    // we just set the right intent.
    let (system_prompt, max_turns) = match mode {
        "generate" => (
            "Build a complete JUCE plugin. The prompt and CLAUDE.md contain everything you need. Write all Source/ files. Do NOT touch CMakeLists.txt.",
            "8",
        ),
        "refine" => (
            "Modify an existing JUCE plugin. Read the Source/ files, then apply targeted changes. Do NOT touch CMakeLists.txt.",
            "6",
        ),
        // Build-error fix pass (called by the build loop with compiler errors)
        _ => (
            "Fix the build errors in this JUCE plugin. Only edit Source/ files. Do NOT touch CMakeLists.txt.",
            "6",
        ),
    };

    // Disable tools the agent should never use in an automated subprocess.
    // Read/Write/Edit are always allowed — the agent decides when to use them.
    let disallowed = "Bash,Grep,Glob,WebSearch,WebFetch,NotebookEdit,Skill,EnterPlanMode,ExitPlanMode,EnterWorktree,ExitWorktree,CronCreate,CronDelete,CronList,Task,TaskCreate,TaskGet,TaskUpdate,TaskList,TaskOutput,TaskStop,AskUserQuestion,ToolSearch,Agent,TodoRead,TodoWrite,RemoteTrigger,mcp__remote,computer";

    let args = vec![
        "-p".to_string(),
        prompt.to_string(),
        "--dangerously-skip-permissions".to_string(),
        "--output-format".to_string(),
        "stream-json".to_string(),
        "--include-partial-messages".to_string(),
        "--verbose".to_string(),
        "--max-turns".to_string(),
        max_turns.to_string(),
        "--model".to_string(),
        model_flag.to_string(),
        "--strict-mcp-config".to_string(),
        "--disallowedTools".to_string(),
        disallowed.to_string(),
        "--append-system-prompt".to_string(),
        system_prompt.to_string(),
    ];

    let env = shell_environment();

    #[cfg(target_os = "windows")]
    let mut env = env;

    #[cfg(target_os = "windows")]
    if let Some(git_bash_path) = normalize_windows_git_bash_env(&mut env) {
        if let Err(error) = ensure_windows_project_settings(project_dir, &git_bash_path) {
            on_event(ClaudeEvent::Text(format!(
                "Warning: could not persist Claude Windows settings: {}",
                error
            )));
        }
    }

    let mut child = match Command::new(claude_path)
        .args(&args)
        .current_dir(project_dir)
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            let msg = format!("Failed to launch Claude Code: {}", e);
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

    on_event(ClaudeEvent::Text(format!(
        "MODEL SESSION · provider=claude-code · mode={} · model={} · max-turns={}",
        mode, model_flag, max_turns
    )));

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();
    let mut stdout_reader = BufReader::new(stdout).lines();
    let mut stderr_reader = BufReader::new(stderr).lines();

    let mut all_output = String::new();
    let mut stderr_output = String::new();
    let mut final_success = false;
    let mut stdout_done = false;
    let mut stderr_done = false;
    let mut last_activity = std::time::Instant::now();
    let mut last_heartbeat_second = 0;

    // Captured from the "result" event
    let mut result_input_tokens: Option<i64> = None;
    let mut result_output_tokens: Option<i64> = None;
    let mut result_cache_read_tokens: Option<i64> = None;
    let mut result_cost_usd: Option<f64> = None;
    let mut result_num_turns: Option<i64> = None;
    let mut result_error_text: Option<String> = None;

    // The agent manages its own completion via max-turns. The watchdog is
    // only a safety net for truly hung processes (e.g. zombie CLI), not a
    // performance lever. 30 minutes — should never be hit in practice.
    let watchdog_secs: u64 = 1800;
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
                        "Heartbeat: no new Claude output for {}s. The model is likely drafting files or waiting for a tool result.",
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

                        // Extract token/cost data from result events
                        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                            if json["type"].as_str() == Some("result") {
                                result_input_tokens = json["input_tokens"].as_i64()
                                    .or_else(|| json["usage"]["input_tokens"].as_i64());
                                result_output_tokens = json["output_tokens"].as_i64()
                                    .or_else(|| json["usage"]["output_tokens"].as_i64());
                                result_cache_read_tokens = json["cache_read_tokens"].as_i64()
                                    .or_else(|| json["usage"]["cache_read_input_tokens"].as_i64());
                                result_cost_usd = json["total_cost_usd"].as_f64()
                                    .or_else(|| json["cost_usd"].as_f64());
                                result_num_turns = json["num_turns"].as_i64();
                                if json["is_error"].as_bool().unwrap_or(false) {
                                    result_error_text = json["result"]
                                        .as_str()
                                        .map(str::trim)
                                        .filter(|text| !text.is_empty())
                                        .map(ToOwned::to_owned)
                                        .or_else(|| {
                                            json["error"]
                                                .as_str()
                                                .map(str::trim)
                                                .filter(|text| !text.is_empty())
                                                .map(ToOwned::to_owned)
                                        });
                                }
                            }
                        }

                        for event in parse_events(&text) {
                            if let ClaudeEvent::Result { success } = &event {
                                final_success = *success;
                            }
                            on_event(event);
                        }
                    }
                    Ok(None) => stdout_done = true,
                    Err(e) => {
                        last_activity = std::time::Instant::now();
                        stderr_output.push_str(&format!("Failed to read Claude stdout: {}\n", e));
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
                        stderr_output.push_str(&format!("Failed to read Claude stderr: {}\n", e));
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
    } else if let Some(message) = result_error_text {
        Some(message)
    } else if !all_output.trim().is_empty() {
        Some("Claude Code exited with error; see stdout for details".into())
    } else {
        Some("Claude Code exited with error".into())
    };

    RunResult {
        success: exit_ok && final_success,
        output: all_output,
        error,
        input_tokens: result_input_tokens,
        output_tokens: result_output_tokens,
        cache_read_tokens: result_cache_read_tokens,
        cost_usd: result_cost_usd,
        num_turns: result_num_turns,
    }
}

/// Run Claude Code for a fix pass (build errors).
pub async fn fix(
    claude_path: &str,
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
        Read CLAUDE.md for the full plugin spec. Only edit Source/ files. Do NOT touch CMakeLists.txt.\n\n\
        Errors:\n{}",
        attempt, errors
    );
    run(
        claude_path,
        &prompt,
        project_dir,
        model_flag,
        "fix",
        on_event,
        cancel_rx,
    )
    .await
}

// ---- Event parsing ----

fn parse_events(line: &str) -> Vec<ClaudeEvent> {
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
        "system" => {
            if json["subtype"].as_str() == Some("init") {
                let version = json["claude_code_version"].as_str().unwrap_or("?");
                let model = json["model"].as_str().unwrap_or("unknown-model");
                let cwd = json["cwd"].as_str().unwrap_or("");
                events.push(ClaudeEvent::Text(format!(
                    "Claude {} ready · model={}{}",
                    version,
                    model,
                    if cwd.is_empty() {
                        String::new()
                    } else {
                        format!(" · cwd={}", cwd)
                    }
                )));
            }
        }
        "assistant" => {
            if let Some(content) = json["message"]["content"].as_array() {
                for block in content {
                    match block["type"].as_str() {
                        Some("text") => {
                            if let Some(text) = block["text"].as_str() {
                                let trimmed = text.trim();
                                if !trimmed.is_empty() {
                                    events.push(ClaudeEvent::Text(trimmed.to_string()));
                                }
                            }
                        }
                        Some("tool_use") => {
                            if let Some(name) = block["name"].as_str() {
                                let input = &block["input"];
                                let file_path = extract_path(input);
                                let detail = build_tool_detail(name, input);
                                events.push(ClaudeEvent::ToolUse {
                                    tool: name.to_string(),
                                    file_path,
                                    detail,
                                });
                            }
                        }
                        _ => {}
                    }
                }
            }
        }
        "stream_event" => {
            let event = &json["event"];
            match event["type"].as_str() {
                Some("content_block_delta") => {
                    let delta = &event["delta"];
                    match delta["type"].as_str() {
                        Some("text_delta") => {
                            if let Some(text) = delta["text"].as_str() {
                                if !text.is_empty() {
                                    events.push(ClaudeEvent::StreamingText(text.to_string()));
                                }
                            }
                        }
                        Some("input_json_delta") => {
                            // The model is streaming tool input (e.g. file content
                            // for a Write call). Emit a dot so the UI stays alive.
                            events.push(ClaudeEvent::StreamingText("·".to_string()));
                        }
                        _ => {}
                    }
                }
                Some("content_block_start") => {
                    let content_block = &event["content_block"];
                    match content_block["type"].as_str() {
                        Some("text") => {
                            if let Some(text) = content_block["text"].as_str() {
                                let trimmed = text.trim();
                                if !trimmed.is_empty() {
                                    events.push(ClaudeEvent::StreamingText(trimmed.to_string()));
                                }
                            }
                        }
                        Some("tool_use") => {
                            if let Some(name) = content_block["name"].as_str() {
                                events.push(ClaudeEvent::Text(format!("MODEL → {} ...", name)));
                            }
                        }
                        _ => {}
                    }
                }
                _ => {}
            }
        }
        "user" => {
            if let Some(content) = json["message"]["content"].as_array() {
                for block in content {
                    if block["type"].as_str() == Some("tool_result") {
                        let tool_name = block["tool_name"]
                            .as_str()
                            .or_else(|| json["tool_name"].as_str())
                            .or_else(|| json["name"].as_str())
                            .unwrap_or("tool");
                        let output = extract_tool_output(block);
                        if !output.is_empty() {
                            events.push(ClaudeEvent::ToolResult {
                                tool: tool_name.to_string(),
                                output,
                            });
                        }
                    }
                }
            }
        }
        "tool_result" => {
            let output = extract_tool_output(&json);
            let tool_name = json["tool_name"]
                .as_str()
                .or_else(|| json["name"].as_str())
                .unwrap_or("tool");
            if !output.is_empty() {
                events.push(ClaudeEvent::ToolResult {
                    tool: tool_name.to_string(),
                    output,
                });
            }
        }
        "result" => {
            let is_error = json["is_error"].as_bool().unwrap_or(false);
            if let (Some(cost), Some(turns)) =
                (json["total_cost_usd"].as_f64(), json["num_turns"].as_i64())
            {
                events.push(ClaudeEvent::Text(format!(
                    "Done — {} turns, ${:.4}",
                    turns, cost
                )));
            }
            if let Some(result_text) = json["result"].as_str() {
                let trimmed = result_text.trim();
                if !trimmed.is_empty() {
                    events.push(ClaudeEvent::Text(trimmed.to_string()));
                }
            }
            events.push(ClaudeEvent::Result { success: !is_error });
        }
        _ => {}
    }

    events
}

#[cfg(target_os = "windows")]
fn normalize_windows_git_bash_env(env: &mut [(String, String)]) -> Option<String> {
    let (_, value) = env
        .iter_mut()
        .find(|(key, _)| key == "CLAUDE_CODE_GIT_BASH_PATH")?;

    let normalized = normalize_windows_path(value);
    *value = normalized.clone();
    Some(normalized)
}

#[cfg(any(test, target_os = "windows"))]
fn normalize_windows_path(path: &str) -> String {
    path.trim()
        .trim_matches('"')
        .replace('/', "\\")
}

#[cfg(target_os = "windows")]
fn ensure_windows_project_settings(project_dir: &str, git_bash_path: &str) -> Result<(), String> {
    let claude_dir = Path::new(project_dir).join(".claude");
    std::fs::create_dir_all(&claude_dir).map_err(|error| error.to_string())?;

    let settings_path = claude_dir.join("settings.local.json");
    let existing = if settings_path.exists() {
        std::fs::read_to_string(&settings_path).map_err(|error| error.to_string())?
    } else {
        String::new()
    };

    let mut settings = if existing.trim().is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str::<serde_json::Value>(&existing)
            .map_err(|error| format!("{} is not valid JSON: {}", settings_path.display(), error))?
    };

    let object = settings.as_object_mut().ok_or_else(|| {
        format!(
            "{} must contain a JSON object at the root",
            settings_path.display()
        )
    })?;

    let env = object
        .entry("env")
        .or_insert_with(|| serde_json::json!({}));
    let env_object = env.as_object_mut().ok_or_else(|| {
        format!(
            "{} must contain an object in the `env` field",
            settings_path.display()
        )
    })?;

    env_object.insert(
        "CLAUDE_CODE_GIT_BASH_PATH".into(),
        serde_json::Value::String(git_bash_path.to_string()),
    );

    let serialized = serde_json::to_string_pretty(&settings).map_err(|error| error.to_string())?;
    std::fs::write(settings_path, format!("{}\n", serialized)).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_windows_path_converts_slashes_and_quotes() {
        assert_eq!(
            normalize_windows_path("\"C:/Program Files/Git/bin/bash.exe\""),
            r"C:\Program Files\Git\bin\bash.exe"
        );
    }
}

fn extract_path(input: &serde_json::Value) -> Option<String> {
    for key in &["file_path", "target_file", "path", "file", "filename"] {
        if let Some(p) = input[key].as_str() {
            return Some(p.to_string());
        }
    }
    None
}

fn build_tool_detail(tool: &str, input: &serde_json::Value) -> Option<String> {
    let lower = tool.to_lowercase();
    if lower.contains("write") {
        if let Some(content) = input["content"].as_str() {
            return Some(format!("{} lines", content.lines().count()));
        }
    }
    if lower.contains("edit") || lower.contains("str_replace") {
        if let Some(old) = input["old_str"].as_str() {
            let first = old.trim().lines().next().unwrap_or("");
            let truncated: String = first.chars().take(50).collect();
            return Some(format!("«{}»", truncated));
        }
    }
    if lower.contains("multiedit") || lower.contains("multi_edit") {
        if let Some(edits) = input["edits"].as_array() {
            return Some(format!("{} edits", edits.len()));
        }
    }
    None
}

fn extract_tool_output(json: &serde_json::Value) -> String {
    if let Some(s) = json["content"].as_str() {
        return s.to_string();
    }
    if let Some(arr) = json["content"].as_array() {
        return arr
            .iter()
            .filter_map(|b| b["content"].as_str().or_else(|| b["text"].as_str()))
            .collect::<Vec<_>>()
            .join("\n");
    }
    if let Some(s) = json["output"].as_str() {
        return s.to_string();
    }
    String::new()
}
