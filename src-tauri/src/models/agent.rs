use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum GenerationAgent {
    #[serde(rename = "Claude Code")]
    ClaudeCode,
    #[serde(rename = "Codex")]
    Codex,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AgentModel {
    pub id: String,
    pub name: String,
    pub subtitle: String,
    pub flag: String,
    #[serde(default)]
    pub default: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentProvider {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub command: String,
    pub models: Vec<AgentModel>,
}
