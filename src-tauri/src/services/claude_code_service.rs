use std::process::Stdio;
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
    const IDLE_HEARTBEAT_SECS: u64 = 15;

    let (system_prompt, max_turns) = match mode {
        "plan" => (
            concat!(
                "SPEED IS CRITICAL. Produce a short, visible planning pass immediately.\n",
                "Turn 1: Respond with a concise implementation plan in 3-6 bullets.\n",
                "Cover only: DSP architecture, parameter list, and UI structure.\n",
                "Do NOT use any tools.\n",
                "Do NOT read or write files.\n",
                "Stop after the plan."
            ),
            "2",
        ),
        "generate" => (
            concat!(
                "SPEED IS CRITICAL, but the first pass must still be compile-oriented.\n",
                "Start with one short progress note describing DSP architecture, interaction concept, and UI structure.\n",
                "The prompt contains ALL the information you need — do NOT read any files.\n",
                "Turn 1: Immediately create Source/PluginProcessor.h and Source/PluginProcessor.cpp.\n",
                "Turn 2: Create Source/FoundryLookAndFeel.h, Source/PluginEditor.h, and Source/PluginEditor.cpp.\n",
                "Turn 3: Only if necessary, make one targeted Edit pass to align parameter IDs, attachments, and class names.\n",
                "Prefer distinctive control hierarchy over a generic row of knobs.\n",
                "Do NOT verify your work with Read calls. Trust the prompt and write decisively.\n",
                "Never respond with only text — always use tools after the initial sentence."
            ),
            "5",
        ),
        "generate_processor" => (
            concat!(
                "SPEED IS CRITICAL, and observability matters.\n",
                "Start with one short sentence describing the DSP/processor work you are about to do.\n",
                "The prompt contains ALL the information you need — do NOT read any files.\n",
                "Create ONLY Source/PluginProcessor.h and Source/PluginProcessor.cpp.\n",
                "Use Write calls immediately.\n",
                "If needed, make one final targeted Edit pass.\n",
                "Do NOT create editor or look-and-feel files in this phase.\n",
                "Do NOT verify your work with Read calls. Trust your output.\n",
                "Never respond with only text — always use tools after the initial sentence."
            ),
            "4",
        ),
        "generate_ui" => (
            concat!(
                "SPEED IS CRITICAL, and observability matters.\n",
                "Start with one short sentence describing the UI work you are about to do.\n",
                "The prompt contains the parameter manifest and class names you need — do NOT read any files.\n",
                "Immediately create Source/FoundryLookAndFeel.h, Source/PluginEditor.h, and Source/PluginEditor.cpp.\n",
                "Use Write calls for missing files and Edit only if needed.\n",
                "In PluginEditor.cpp, write an explicit numeric landscape call like setSize(820, 520); in the constructor.\n",
                "Do not use named constants, helper variables, or portrait dimensions for setSize(...).\n",
                "Do NOT modify CMakeLists.txt.\n",
                "Do NOT rewrite processor files unless absolutely necessary.\n",
                "Never respond with only text — always use tools after the initial sentence."
            ),
            "5",
        ),
        "repair_generation" => (
            concat!(
                "RECOVERY MODE. Fix the generated Source/ tree quickly and decisively.\n",
                "Start with one short sentence describing the repair you are about to make.\n",
                "Read existing Source/ files first, then repair them with Write or Edit as needed.\n",
                "You MAY fully rewrite a broken Source/ file if that is faster and safer than patching it.\n",
                "If PluginEditor.cpp has sizing issues, write an explicit numeric landscape call like setSize(820, 520); in the constructor.\n",
                "Do not use named constants, helper variables, or portrait dimensions for setSize(...).\n",
                "Only touch Source/ files. Do NOT modify CMakeLists.txt.\n",
                "Do not spend turns on planning or todo tools.\n",
                "Never respond with only text — always use tools after the initial sentence."
            ),
            "5",
        ),
        "refine" => (
            concat!(
                "SPEED IS CRITICAL. Minimize the number of turns.\n",
                "Before using any tool, briefly state what you are about to do in one sentence.\n",
                "Turn 1: Read ALL existing Source/ files in PARALLEL (one Read call per file, all in the same turn).\n",
                "Turn 2+: Use Edit to make targeted changes — do NOT rewrite entire files.\n",
                "Only modify what is necessary to fulfill the user's request. Keep everything else intact.\n",
                "Never respond with only text — always use tools."
            ),
            "6",
        ),
        "quality_audit" => (
            concat!(
                "QUALITY IS THE PRIORITY.\n",
                "Start with one short sentence describing what you are auditing.\n",
                "Turn 1: Read ALL existing Source/ files in PARALLEL.\n",
                "Turn 2+: Improve sound quality, parameter usefulness, and audible impact with targeted Edit calls.\n",
                "Requirements:\n",
                "- No dead knobs: every exposed parameter must audibly affect the result.\n",
                "- Instruments must sound good immediately at default settings on first MIDI note.\n",
                "- Effects must produce a clearly audible effect at meaningful settings.\n",
                "- Use proper gain staging and avoid outputs that are too quiet.\n",
                "- Prefer smoother, more musical defaults over placeholder behavior.\n",
                "- Keep class names and parameter IDs stable.\n",
                "Do NOT touch CMakeLists.txt.\n",
                "Never respond with only text — always use tools."
            ),
            "6",
        ),
        _ => (
            concat!(
                "SPEED IS CRITICAL, but observability matters too.\n",
                "Start with a very short progress message describing your implementation plan in 2-4 bullets.\n",
                "The prompt contains ALL the information you need — do NOT read any files.\n",
                "Turn 1: Immediately create Source/PluginProcessor.h and Source/PluginProcessor.cpp using PARALLEL Write calls.\n",
                "Turn 2: Create Source/PluginEditor.h, Source/PluginEditor.cpp, and Source/FoundryLookAndFeel.h using PARALLEL Write calls.\n",
                "Turn 3: Only if you realize you made an error, fix with Edit. Otherwise, STOP.\n",
                "Do NOT verify your work with Read calls. Trust your output.\n",
                "Before each batch of tool calls, briefly say what you are about to do.\n",
                "Never respond with only text — always use tools."
            ),
            "6",
        ),
    };

    // For "generate" mode, also disallow Read — the prompt is self-contained.
    // For "refine" and "fix" modes, Claude must read existing Source/ files.
    let disallowed_base = "Bash,Grep,Glob,WebSearch,WebFetch,NotebookEdit,Skill,EnterPlanMode,ExitPlanMode,EnterWorktree,ExitWorktree,CronCreate,CronDelete,CronList,Task,TaskCreate,TaskGet,TaskUpdate,TaskList,TaskOutput,TaskStop,AskUserQuestion,ToolSearch,Agent,TodoRead,TodoWrite,RemoteTrigger,mcp__remote,computer";
    let disallowed = match mode {
        "plan" => format!("{},Read,Write,Edit,MultiEdit,StrReplace", disallowed_base),
        "generate" | "generate_processor" | "generate_ui" => format!("{},Read", disallowed_base),
        _ => disallowed_base.to_string(),
    };

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
        disallowed,
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
    let mut saw_write_activity = false;

    // Captured from the "result" event
    let mut result_input_tokens: Option<i64> = None;
    let mut result_output_tokens: Option<i64> = None;
    let mut result_cache_read_tokens: Option<i64> = None;
    let mut result_cost_usd: Option<f64> = None;
    let mut result_num_turns: Option<i64> = None;

    let watchdog_secs = match mode {
        "generate" => 360,
        "generate_processor" | "generate_ui" | "refine" | "quality_audit" => 300,
        _ => 900,
    };
    let no_write_timeout_secs = match mode {
        "generate_processor" => Some(75),
        "generate_ui" => Some(45),
        _ => None,
    };
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
                if let Some(timeout_secs) = no_write_timeout_secs {
                    if !saw_write_activity && idle_for >= timeout_secs {
                        let message = format!(
                            "No write activity detected after {}s in {} mode",
                            timeout_secs, mode
                        );
                        on_event(ClaudeEvent::Error(message.clone()));
                        let _ = child.kill().await;
                        return RunResult {
                            success: false,
                            output: all_output,
                            error: Some(message),
                            input_tokens: result_input_tokens,
                            output_tokens: result_output_tokens,
                            cache_read_tokens: result_cache_read_tokens,
                            cost_usd: result_cost_usd,
                            num_turns: result_num_turns,
                        };
                    }
                }
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
                            }
                        }

                        for event in parse_events(&text) {
                            if let ClaudeEvent::Result { success } = &event {
                                final_success = *success;
                            }
                            if let ClaudeEvent::ToolUse { tool, .. } = &event {
                                let lower = tool.to_lowercase();
                                if lower.contains("write")
                                    || lower.contains("edit")
                                    || lower.contains("str_replace")
                                    || lower.contains("multi_edit")
                                    || lower.contains("multiedit")
                                {
                                    saw_write_activity = true;
                                }
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

    let error = if exit_ok {
        None
    } else if !stderr_output.trim().is_empty() {
        Some(stderr_output.trim().to_string())
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
        "Build failed (attempt {}). Fix ALL errors in 2 turns.\n\
        Turn 1: Read ALL Source/ files in PARALLEL.\n\
        Turn 2: Fix ALL issues with PARALLEL Edit calls.\n\n\
        Errors:\n{}\n\n\
        Rules: ONLY edit Source/ files. Do NOT touch CMakeLists.txt. C++17, juce:: prefix everywhere,\n\
        juce::Font(juce::FontOptions(float)) not juce::Font(float), .h/.cpp signatures must match.\n\
        Linker errors = your source code, NOT CMakeLists.txt.",
        attempt, errors
    );
    run(
        claude_path,
        &prompt,
        project_dir,
        model_flag,
        "refine",
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
                    if delta["type"].as_str() == Some("text_delta") {
                        if let Some(text) = delta["text"].as_str() {
                            if !text.is_empty() {
                                events.push(ClaudeEvent::StreamingText(text.to_string()));
                            }
                        }
                    }
                }
                Some("content_block_start") => {
                    let content_block = &event["content_block"];
                    if content_block["type"].as_str() == Some("text") {
                        if let Some(text) = content_block["text"].as_str() {
                            let trimmed = text.trim();
                            if !trimmed.is_empty() {
                                events.push(ClaudeEvent::StreamingText(trimmed.to_string()));
                            }
                        }
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
