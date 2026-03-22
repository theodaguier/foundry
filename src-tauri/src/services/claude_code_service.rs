use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

/// Resolved path of the `claude` CLI binary.
pub fn resolve_claude_path() -> Option<String> {
    let output = std::process::Command::new("/bin/zsh")
        .args(["-l", "-c", "which claude"])
        .output()
        .ok()?;
    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    }
}

/// Shell environment inherited by subprocesses (login shell PATH).
pub fn shell_environment() -> Vec<(String, String)> {
    let output = std::process::Command::new("/bin/zsh")
        .args(["-l", "-c", "env"])
        .output()
        .ok();
    let mut env = Vec::new();
    if let Some(out) = output {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            if let Some((k, v)) = line.split_once('=') {
                env.push((k.to_string(), v.to_string()));
            }
        }
    }
    env
}

#[derive(Debug, Clone)]
pub enum ClaudeEvent {
    ToolUse { tool: String, file_path: Option<String>, detail: Option<String> },
    ToolResult { tool: String, output: String },
    Text(String),
    Result { success: bool },
    Error(String),
}

pub struct RunResult {
    pub success: bool,
    pub output: String,
    pub error: Option<String>,
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
    let system_prompt = match mode {
        "refine" => concat!(
            "SPEED IS CRITICAL. Minimize the number of turns.\n",
            "Turn 1: Read ALL existing Source/ files in PARALLEL (one Read call per file, all in the same turn).\n",
            "Turn 2+: Use Edit to make targeted changes — do NOT rewrite entire files.\n",
            "Only modify what is necessary to fulfill the user's request. Keep everything else intact.\n",
            "Never respond with only text — always use tools."
        ),
        _ => concat!(
            "SPEED IS CRITICAL. Minimize the number of turns.\n",
            "Turn 1: Read CLAUDE.md AND all juce-kit/*.md files in PARALLEL (one Read call per file, all in the same turn).\n",
            "Turn 2-4: Write ALL 5 source files. Use PARALLEL Write calls — write multiple files in the same turn.\n",
            "Do NOT verify your work with extra Read calls after writing. Trust your output.\n",
            "Never respond with only text — always use tools."
        ),
    };

    let args = vec![
        "-p".to_string(),
        prompt.to_string(),
        "--dangerously-skip-permissions".to_string(),
        "--output-format".to_string(), "stream-json".to_string(),
        "--verbose".to_string(),
        "--max-turns".to_string(), "25".to_string(),
        "--model".to_string(), model_flag.to_string(),
        "--strict-mcp-config".to_string(),
        "--disallowedTools".to_string(),
        "Bash,Grep,Glob,WebSearch,WebFetch,NotebookEdit,Skill,EnterPlanMode,ExitPlanMode,EnterWorktree,ExitWorktree,CronCreate,CronDelete,CronList,Task,TaskCreate,TaskGet,TaskUpdate,TaskList,TaskOutput,TaskStop,AskUserQuestion,ToolSearch".to_string(),
        "--append-system-prompt".to_string(),
        system_prompt.to_string(),
    ];

    let env = shell_environment();

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
            return RunResult { success: false, output: String::new(), error: Some(msg) };
        }
    };

    let stdout = child.stdout.take().unwrap();
    let mut reader = BufReader::new(stdout).lines();

    let mut all_output = String::new();
    let mut final_success = false;

    // 15-minute watchdog
    let watchdog = tokio::time::sleep(std::time::Duration::from_secs(900));
    tokio::pin!(watchdog);

    loop {
        tokio::select! {
            biased;

            _ = cancel_rx.changed() => {
                if *cancel_rx.borrow() {
                    let _ = child.kill().await;
                    return RunResult { success: false, output: all_output, error: Some("Cancelled".into()) };
                }
            }

            _ = &mut watchdog => {
                on_event(ClaudeEvent::Error("Process killed by 15-minute watchdog".into()));
                let _ = child.kill().await;
                return RunResult { success: false, output: all_output, error: Some("Watchdog timeout".into()) };
            }

            line = reader.next_line() => {
                match line {
                    Ok(Some(text)) => {
                        all_output.push_str(&text);
                        all_output.push('\n');
                        for event in parse_events(&text) {
                            if let ClaudeEvent::Result { success } = &event {
                                final_success = *success;
                            }
                            on_event(event);
                        }
                    }
                    Ok(None) => break, // EOF
                    Err(_) => break,
                }
            }
        }
    }

    let status = child.wait().await;
    let exit_ok = status.map(|s| s.success()).unwrap_or(false);

    RunResult {
        success: exit_ok && final_success,
        output: all_output,
        error: if exit_ok { None } else { Some("Claude Code exited with error".into()) },
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
        "Build failed (attempt {}). Fix ALL errors in 3 turns max.\n\
        Turn 1: Read ALL Source/ files in PARALLEL.\n\
        Turn 2: Fix with PARALLEL Edit calls.\n\
        Turn 3: Only if needed.\n\n\
        Errors:\n{}\n\n\
        Rules: ONLY edit Source/ files. Do NOT touch CMakeLists.txt. C++17, juce:: prefix everywhere,\n\
        juce::Font(juce::FontOptions(float)) not juce::Font(float), .h/.cpp signatures must match.\n\
        Linker errors = your source code, NOT CMakeLists.txt.",
        attempt, errors
    );
    run(claude_path, &prompt, project_dir, model_flag, "refine", on_event, cancel_rx).await
}

/// Run Claude Code for an audit pass.
pub async fn audit(
    claude_path: &str,
    project_dir: &str,
    user_intent: &str,
    plugin_type: &str,
    model_flag: &str,
    on_event: impl Fn(ClaudeEvent) + Send + 'static,
    cancel_rx: tokio::sync::watch::Receiver<bool>,
) -> RunResult {
    let prompt = format!(
        "Audit the plugin code. SPEED IS CRITICAL — do this in 3 turns max.\n\
        Turn 1: Read ALL 5 Source/ files in PARALLEL.\n\
        Turn 2: Fix any issues with PARALLEL Edit calls.\n\
        Turn 3: Only if needed.\n\n\
        Check: parameter/UI mismatches, missing juce:: prefixes, .h/.cpp signature mismatches,\n\
        juce::Font(float) (must be juce::FontOptions), LookAndFeel lifecycle, DSP matches \"{}\".\n\
        Plugin type: {}. Do NOT touch CMakeLists.txt.",
        user_intent, plugin_type
    );
    run(claude_path, &prompt, project_dir, model_flag, "refine", on_event, cancel_rx).await
}

/// Generate a plugin name using Claude haiku.
pub async fn generate_plugin_name(
    claude_path: &str,
    prompt: &str,
    existing_names: &[String],
) -> String {
    let taken = existing_names.join(", ");
    let name_prompt = format!(
        "Invent a short, creative plugin name (1 word, max 10 chars) for this audio plugin: \"{}\".\n\
        The name must sound like a premium audio brand — punchy, evocative, memorable.\n\
        These names are ALREADY TAKEN, do NOT use any of them: [{}].\n\
        Reply with ONLY the name, nothing else. No quotes, no explanation.",
        prompt, taken
    );

    let env = shell_environment();
    let output = Command::new(claude_path)
        .args(["-p", &name_prompt, "--dangerously-skip-permissions", "--output-format", "text", "--max-turns", "1", "--model", "haiku"])
        .envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .await;

    if let Ok(out) = output {
        if out.status.success() {
            let raw = String::from_utf8_lossy(&out.stdout).trim().replace('"', "");
            if let Some(name) = raw.split_whitespace().next() {
                if !name.is_empty() && !existing_names.contains(&name.to_string()) {
                    return name.to_string();
                }
            }
        }
    }

    fallback_name(existing_names)
}

fn fallback_name(existing: &[String]) -> String {
    let pool = ["Flux", "Apex", "Nova", "Zinc", "Opal", "Noir", "Glow", "Husk", "Dusk", "Null"];
    let taken: Vec<String> = existing.iter().map(|n| n.to_lowercase()).collect();
    for name in &pool {
        if !taken.contains(&name.to_lowercase()) {
            return name.to_string();
        }
    }
    format!("Plugin{}", &uuid::Uuid::new_v4().to_string()[..4])
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
                events.push(ClaudeEvent::Text(format!("Claude {} ready", version)));
            }
        }
        "assistant" => {
            if let Some(content) = json["message"]["content"].as_array() {
                for block in content {
                    match block["type"].as_str() {
                        Some("text") => {
                            if let Some(text) = block["text"].as_str() {
                                if !text.is_empty() {
                                    events.push(ClaudeEvent::Text(text.to_string()));
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
        "tool" | "tool_result" => {
            let output = extract_tool_output(&json);
            let tool_name = json["tool_name"].as_str()
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
            if let (Some(cost), Some(turns)) = (json["total_cost_usd"].as_f64(), json["num_turns"].as_i64()) {
                events.push(ClaudeEvent::Text(format!("Done — {} turns, ${:.4}", turns, cost)));
            }
            events.push(ClaudeEvent::Result { success: !is_error });
        }
        _ => {}
    }

    events
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
    if let Some(s) = json["content"].as_str() { return s.to_string(); }
    if let Some(arr) = json["content"].as_array() {
        return arr.iter()
            .filter_map(|b| b["content"].as_str().or_else(|| b["text"].as_str()))
            .collect::<Vec<_>>()
            .join("\n");
    }
    if let Some(s) = json["output"].as_str() { return s.to_string(); }
    String::new()
}
