use std::fs;
use crate::models::agent::{AgentProvider, AgentModel};
use crate::services::foundry_paths;

#[derive(serde::Deserialize)]
struct CatalogRoot { providers: Vec<AgentProvider> }

pub fn load_catalog() -> Result<Vec<AgentProvider>, Box<dyn std::error::Error>> {
    let user_path = foundry_paths::models_user_override_path();
    if user_path.exists() {
        let data = fs::read_to_string(&user_path)?;
        let root: CatalogRoot = serde_json::from_str(&data)?;
        return Ok(root.providers);
    }
    let cache_path = foundry_paths::models_cache_path();
    if cache_path.exists() {
        let data = fs::read_to_string(&cache_path)?;
        let root: CatalogRoot = serde_json::from_str(&data)?;
        return Ok(root.providers);
    }
    Ok(vec![AgentProvider {
        id: "claude-code".into(), name: "Claude Code".into(), icon: "ProviderAnthropic".into(), command: "claude".into(),
        models: vec![
            AgentModel { id: "sonnet".into(), name: "Sonnet".into(), subtitle: "Fast & capable".into(), flag: "sonnet".into(), default: Some(true) },
            AgentModel { id: "opus".into(), name: "Opus".into(), subtitle: "Most capable".into(), flag: "opus".into(), default: None },
        ],
    }])
}

pub async fn refresh() -> Result<Vec<AgentProvider>, Box<dyn std::error::Error>> {
    load_catalog()
}
