use crate::models::agent::{AgentModel, AgentProvider};
use crate::services::foundry_paths;
use std::fs;

#[derive(serde::Deserialize)]
struct CatalogRoot {
    providers: Vec<AgentProvider>,
}

/// Known models for each provider. These are the models that the CLI accepts
/// via `--model` / `-m`. Neither CLI exposes a "list models" command, so we
/// maintain the list here and filter by which CLIs are actually installed.
fn claude_code_models() -> Vec<AgentModel> {
    vec![
        AgentModel {
            id: "sonnet".into(),
            name: "Sonnet".into(),
            subtitle: "Fast & capable".into(),
            flag: "sonnet".into(),
            default: Some(true),
        },
        AgentModel {
            id: "opus".into(),
            name: "Opus".into(),
            subtitle: "Most capable".into(),
            flag: "opus".into(),
            default: None,
        },
        AgentModel {
            id: "haiku".into(),
            name: "Haiku".into(),
            subtitle: "Fastest".into(),
            flag: "haiku".into(),
            default: None,
        },
    ]
}

fn codex_models() -> Vec<AgentModel> {
    vec![
        AgentModel {
            id: "gpt-5.4".into(),
            name: "GPT-5.4".into(),
            subtitle: "Most capable".into(),
            flag: "gpt-5.4".into(),
            default: Some(true),
        },
        AgentModel {
            id: "gpt-5.4-mini".into(),
            name: "GPT-5.4 Mini".into(),
            subtitle: "Fast & efficient".into(),
            flag: "gpt-5.4-mini".into(),
            default: None,
        },
        AgentModel {
            id: "gpt-5.2-codex".into(),
            name: "GPT-5.2 Codex".into(),
            subtitle: "Optimized for code".into(),
            flag: "gpt-5.2-codex".into(),
            default: None,
        },
    ]
}

/// Build the catalog by detecting which CLIs are installed on this machine.
fn detect_installed_providers() -> Vec<AgentProvider> {
    let mut providers = Vec::new();

    if crate::platform::resolve_claude_path().is_some() {
        providers.push(AgentProvider {
            id: "claude-code".into(),
            name: "Claude Code".into(),
            icon: "ProviderAnthropic".into(),
            command: "claude".into(),
            models: claude_code_models(),
        });
    }

    if crate::platform::resolve_codex_path().is_some() {
        providers.push(AgentProvider {
            id: "codex".into(),
            name: "Codex".into(),
            icon: "ProviderOpenAI".into(),
            command: "codex".into(),
            models: codex_models(),
        });
    }

    providers
}

/// Load the model catalog. Priority:
/// 1. User override file (`models.json`) — full customization
/// 2. Dynamic detection of installed CLIs (always fresh, always authoritative)
pub fn load_catalog() -> Result<Vec<AgentProvider>, Box<dyn std::error::Error>> {
    // User override takes precedence — allows full customization
    let user_path = foundry_paths::models_user_override_path();
    if user_path.exists() {
        let data = fs::read_to_string(&user_path)?;
        let root: CatalogRoot = serde_json::from_str(&data)?;
        return Ok(root.providers);
    }

    // Always detect installed CLIs — no stale cache
    Ok(detect_installed_providers())
}

/// Refresh the catalog by re-detecting installed CLIs.
/// Invalidates the shell cache first so newly installed tools are found.
pub async fn refresh() -> Result<Vec<AgentProvider>, Box<dyn std::error::Error>> {
    // Invalidate platform caches so we pick up newly installed CLIs
    crate::platform::invalidate_shell_cache();
    load_catalog()
}
