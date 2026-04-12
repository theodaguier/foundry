use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SubagentRole {
    Planner,
    Dsp,
    Ui,
    Review,
    BuildFix,
    RefineModify,
}

impl SubagentRole {
    pub fn as_str(&self) -> &'static str {
        match self {
            SubagentRole::Planner => "planner",
            SubagentRole::Dsp => "dsp",
            SubagentRole::Ui => "ui",
            SubagentRole::Review => "review",
            SubagentRole::BuildFix => "build_fix",
            SubagentRole::RefineModify => "refine_modify",
        }
    }

    pub fn max_turns(&self) -> u32 {
        match self {
            SubagentRole::Planner => 4,
            SubagentRole::Dsp => 6,
            SubagentRole::Ui => 6,
            SubagentRole::Review => 3,
            SubagentRole::BuildFix => 4,
            SubagentRole::RefineModify => 5,
        }
    }

    pub fn system_instruction(&self) -> &'static str {
        match self {
            SubagentRole::Planner => "Analyze the user brief and create a plugin implementation plan with required skills.",
            SubagentRole::Dsp => "Generate the DSP processor file. Write PluginProcessor.h and PluginProcessor.cpp with APVTS parameters.",
            SubagentRole::Ui => "Generate the UI editor file. Write PluginEditor.h, PluginEditor.cpp and FoundryLookAndFeel.h.",
            SubagentRole::Review => "Review the generated code for correctness and completeness. Report findings.",
            SubagentRole::BuildFix => "Fix the build errors. Only edit Source/ files. Do NOT touch CMakeLists.txt.",
            SubagentRole::RefineModify => "Make targeted modifications to the plugin. Read Source/ files first, then apply changes.",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SkillId {
    JuceExpert,
    ArtDirector,
    SoundEngineer,
    Beatmaker,
}

impl SkillId {
    pub fn as_str(&self) -> &'static str {
        match self {
            SkillId::JuceExpert => "juce-expert",
            SkillId::ArtDirector => "art-director",
            SkillId::SoundEngineer => "sound-engineer",
            SkillId::Beatmaker => "beatmaker",
        }
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub fn display_name(&self) -> &'static str {
        match self {
            SkillId::JuceExpert => "JUCE Expert",
            SkillId::ArtDirector => "Art Director",
            SkillId::SoundEngineer => "Sound Engineer",
            SkillId::Beatmaker => "Beatmaker",
        }
    }
}

impl std::fmt::Display for SubagentRole {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

impl std::fmt::Display for SkillId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

pub fn skills_for_plugin_type(plugin_type: &str) -> Vec<SkillId> {
    vec![
        SkillId::JuceExpert,
        SkillId::ArtDirector,
        match plugin_type {
            "instrument" => SkillId::Beatmaker,
            _ => SkillId::SoundEngineer,
        },
    ]
}

pub fn skills_to_load(skills: &[SkillId]) -> Vec<&'static str> {
    skills.iter().map(|s| s.as_str()).collect()
}

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
