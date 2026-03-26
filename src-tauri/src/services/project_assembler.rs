use std::fs;
use std::path::{Path, PathBuf};

pub struct AssembledProject {
    pub directory: PathBuf,
    pub plugin_name: String,
    pub plugin_type: String, // "instrument", "effect", "utility"
}

fn normalize_prompt_text(prompt: &str) -> String {
    let collapsed = prompt
        .to_lowercase()
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { ' ' })
        .collect::<String>();
    format!(
        " {} ",
        collapsed.split_whitespace().collect::<Vec<_>>().join(" ")
    )
}

fn contains_phrase(normalized_prompt: &str, phrase: &str) -> bool {
    let normalized_phrase = phrase.split_whitespace().collect::<Vec<_>>().join(" ");
    normalized_prompt.contains(&format!(" {} ", normalized_phrase))
}

fn score_keyword_matches(normalized_prompt: &str, keywords: &[(&str, i32)]) -> i32 {
    keywords
        .iter()
        .filter(|(phrase, _)| contains_phrase(normalized_prompt, phrase))
        .map(|(_, weight)| *weight)
        .sum()
}

fn normalize_plugin_type_override(plugin_type_override: Option<&str>) -> Option<&'static str> {
    match plugin_type_override
        .map(|value| value.trim().to_lowercase())
        .as_deref()
    {
        Some("instrument") => Some("instrument"),
        Some("effect") => Some("effect"),
        Some("utility") => Some("utility"),
        _ => None,
    }
}

pub fn infer_plugin_type(prompt: &str) -> String {
    let normalized = normalize_prompt_text(prompt);

    for (phrase, resolved) in [
        ("instrument plugin", "instrument"),
        ("virtual instrument", "instrument"),
        ("software instrument", "instrument"),
        ("synth plugin", "instrument"),
        ("effect plugin", "effect"),
        ("audio effect", "effect"),
        ("utility plugin", "utility"),
        ("audio utility", "utility"),
        ("analysis tool", "utility"),
    ] {
        if contains_phrase(&normalized, phrase) {
            return resolved.to_string();
        }
    }

    let instrument_score = score_keyword_matches(
        &normalized,
        &[
            ("instrument", 6),
            ("synth", 7),
            ("synthesizer", 7),
            ("polysynth", 7),
            ("poly synth", 7),
            ("monosynth", 7),
            ("mono synth", 7),
            ("polyphonic", 5),
            ("monophonic", 5),
            ("oscillator", 4),
            ("oscillators", 4),
            ("sampler", 6),
            ("rompler", 6),
            ("drum machine", 6),
            ("arpeggiator", 5),
            ("voice", 4),
            ("voices", 4),
            ("midi", 3),
            ("playable", 4),
            ("keyboard", 4),
            ("keys", 3),
            ("pad", 3),
            ("lead", 3),
            ("bass synth", 6),
            ("wavetable", 5),
            ("granular", 4),
            ("organ", 5),
            ("piano", 5),
        ],
    );

    let effect_score = score_keyword_matches(
        &normalized,
        &[
            ("effect", 5),
            ("reverb", 6),
            ("delay", 6),
            ("chorus", 5),
            ("phaser", 5),
            ("flanger", 5),
            ("compressor", 5),
            ("distortion", 5),
            ("saturation", 5),
            ("eq", 4),
            ("equalizer", 5),
            ("tremolo", 5),
            ("ring mod", 5),
            ("ring modulator", 5),
            ("pitch shifter", 5),
            ("autowah", 4),
            ("auto wah", 4),
            ("wah", 3),
            ("glitch", 4),
            ("bitcrusher", 5),
            ("shimmer", 4),
            ("feedback", 3),
            ("wet dry", 3),
            ("dry wet", 3),
            ("sidechain", 3),
        ],
    );

    let utility_score = score_keyword_matches(
        &normalized,
        &[
            ("utility", 7),
            ("analyzer", 7),
            ("analysis", 6),
            ("spectrum", 5),
            ("meter", 6),
            ("metering", 6),
            ("scope", 6),
            ("monitor", 4),
            ("correlation", 6),
            ("tuner", 7),
            ("gain staging", 7),
            ("test tone", 7),
            ("lufs", 7),
            ("true peak", 7),
            ("phase invert", 6),
            ("mono summing", 6),
            ("mid side", 5),
            ("stereo width", 4),
            ("imager", 4),
            ("alignment", 5),
            ("trim", 3),
            ("balance", 2),
            ("phase", 1),
            ("mono", 1),
            ("width", 1),
        ],
    );

    if instrument_score >= 6
        && instrument_score >= effect_score
        && instrument_score >= utility_score
    {
        return "instrument".to_string();
    }

    if utility_score >= 6 && utility_score > instrument_score + 1 && utility_score >= effect_score {
        return "utility".to_string();
    }

    if effect_score >= 5 && effect_score > instrument_score && effect_score >= utility_score {
        return "effect".to_string();
    }

    if instrument_score > 0 && instrument_score >= utility_score {
        return "instrument".to_string();
    }

    if utility_score > effect_score {
        return "utility".to_string();
    }

    "effect".to_string()
}

fn resolve_plugin_type(prompt: &str, plugin_type_override: Option<&str>) -> String {
    if let Some(explicit_plugin_type) = normalize_plugin_type_override(plugin_type_override) {
        explicit_plugin_type.to_string()
    } else {
        infer_plugin_type(prompt)
    }
}

#[allow(clippy::too_many_arguments)]
pub fn assemble(
    prompt: &str,
    plugin_name: &str,
    plugin_type_override: Option<&str>,
    format: &str,         // "au", "vst3", "both"
    channel_layout: &str, // "mono", "stereo"
    _preset_count: i32,
    _model: &str,
    juce_path: &Path,
) -> Result<AssembledProject, String> {
    let plugin_type = resolve_plugin_type(prompt, plugin_type_override);
    let interface_style = infer_interface_style(prompt, &plugin_type);

    let uuid = uuid::Uuid::new_v4().to_string();
    let short = &uuid[..8];
    let project_dir = crate::platform::temp_build_dir(short);
    let source_dir = project_dir.join("Source");

    fs::create_dir_all(&source_dir).map_err(|e| e.to_string())?;

    write_cmake_lists(&project_dir, plugin_name, &plugin_type, format, juce_path)?;
    write_foundry_kit(&project_dir)?;
    write_editor_skeleton(&source_dir, plugin_name)?;
    write_claude_md(
        &project_dir,
        plugin_name,
        &plugin_type,
        interface_style,
        prompt,
        channel_layout,
    )?;
    // Codex reads AGENTS.md instead of CLAUDE.md — write both so either agent works.
    write_agents_md(
        &project_dir,
        plugin_name,
        &plugin_type,
        interface_style,
        prompt,
        channel_layout,
    )?;

    Ok(AssembledProject {
        directory: project_dir,
        plugin_name: plugin_name.to_string(),
        plugin_type,
    })
}

fn infer_interface_style(prompt: &str, plugin_type: &str) -> &'static str {
    let lower = prompt.to_lowercase();
    let precision = [
        "eq",
        "compressor",
        "meter",
        "analyzer",
        "tuner",
        "lufs",
        "phase",
        "stereo",
        "utility",
    ];
    if precision.iter().any(|kw| lower.contains(kw)) {
        return "Graph-Led Precision";
    }
    let digital = [
        "fm",
        "wavetable",
        "digital",
        "granular",
        "glitch",
        "spectral",
        "modulation",
        "sequencer",
    ];
    if digital.iter().any(|kw| lower.contains(kw)) {
        return "Kinetic Digital";
    }
    let tactile = [
        "analog", "warm", "vintage", "tape", "spring", "tube", "organ",
    ];
    if tactile.iter().any(|kw| lower.contains(kw)) {
        return "Tactile Rack";
    }
    let focused = [
        "simple",
        "minimal",
        "clean",
        "focused",
        "few controls",
        "macro",
        "one knob",
        "two knobs",
        "three knobs",
        "fast",
    ];
    if focused.iter().any(|kw| lower.contains(kw)) {
        return "Focused Macro";
    }
    let exploratory = [
        "advanced",
        "deep",
        "modular",
        "matrix",
        "granular",
        "sequencer",
        "multi-stage",
        "complex",
        "dense",
        "experimental",
        "modulation",
        "synth",
        "synthesizer",
        "analog",
        "subtractive",
        "fm",
        "wavetable",
        "polysynth",
        "poly synth",
    ];
    if exploratory.iter().any(|kw| lower.contains(kw)) {
        return "Exploratory Performance";
    }
    match plugin_type {
        "utility" => "Graph-Led Precision",
        "instrument" => "Exploratory Performance",
        _ => "Balanced Character",
    }
}


fn write_editor_skeleton(
    source_dir: &Path,
    plugin_name: &str,
) -> Result<(), String> {
    // PluginEditor.h skeleton — correct structure guaranteed
    let h = format!(
        r#"#pragma once
#include <JuceHeader.h>
#include "PluginProcessor.h"

class {name}Editor : public juce::AudioProcessorEditor
{{
public:
    explicit {name}Editor({name}Processor&);
    ~{name}Editor() override;

    void paint(juce::Graphics&) override;
    void resized() override;

private:
    {name}Processor& processorRef;

    // TODO: declare your controls here
    // juce::Slider myKnob;
    // juce::SliderParameterAttachment myKnobAttachment;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR({name}Editor)
}};
"#,
        name = plugin_name
    );

    // PluginEditor.cpp skeleton — setSize and getLocalBounds guaranteed
    let cpp = format!(
        r#"#include <JuceHeader.h>
#include "PluginEditor.h"

{name}Editor::{name}Editor({name}Processor& p)
    : AudioProcessorEditor(&p), processorRef(p)
{{
    setSize(820, 520);
    // TODO: add controls — setLookAndFeel, addAndMakeVisible, attachments, etc.
}}

{name}Editor::~{name}Editor()
{{
    setLookAndFeel(nullptr);
}}

void {name}Editor::paint(juce::Graphics& g)
{{
    g.fillAll(juce::Colour(0xff1a1a22));
    g.setColour(juce::Colour(0xffe0e8ff));
    g.setFont(juce::Font(juce::FontOptions(14.0f)));
    g.drawText("{name}", getLocalBounds(), juce::Justification::centred, true);
}}

void {name}Editor::resized()
{{
    auto bounds = getLocalBounds().reduced(24);
    auto header = bounds.removeFromTop(44);
    (void)header;
    // TODO: lay out controls using bounds.removeFromTop / removeFromLeft etc.
}}
"#,
        name = plugin_name
    );

    fs::write(source_dir.join("PluginEditor.h"), h).map_err(|e| e.to_string())?;
    fs::write(source_dir.join("PluginEditor.cpp"), cpp).map_err(|e| e.to_string())?;
    Ok(())
}

fn write_cmake_lists(
    dir: &Path,
    name: &str,
    plugin_type: &str,
    format: &str,
    juce_path: &Path,
) -> Result<(), String> {
    let juce_str = juce_path.to_string_lossy();
    let prefix: String = name.chars().take(2).collect::<String>().to_uppercase();
    let suffix = format!("{:02X}", rand_byte());
    let plugin_code: String = format!("{}{}", prefix, suffix).chars().take(4).collect();
    let is_instrument = plugin_type == "instrument";

    let formats = crate::platform::cmake_formats(format);

    let content = format!(
        r#"cmake_minimum_required(VERSION 3.22)
project({name} VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory("{juce}" ${{CMAKE_BINARY_DIR}}/JUCE)

juce_add_plugin({name}
    COMPANY_NAME "Foundry"
    PLUGIN_MANUFACTURER_CODE Fndy
    PLUGIN_CODE {code}
    FORMATS {formats}
    PRODUCT_NAME "{name}"
    IS_SYNTH {is_synth}
    NEEDS_MIDI_INPUT {needs_midi}
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    COPY_PLUGIN_AFTER_BUILD FALSE
)

target_sources({name} PRIVATE
    Source/PluginProcessor.cpp
    Source/PluginEditor.cpp
)

target_compile_definitions({name} PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0
    JUCE_DISPLAY_SPLASH_SCREEN=0
)

target_link_libraries({name} PRIVATE
    juce::juce_audio_utils
    juce::juce_dsp
)

juce_generate_juce_header({name})
"#,
        name = name,
        juce = juce_str,
        code = plugin_code,
        formats = formats,
        is_synth = if is_instrument { "TRUE" } else { "FALSE" },
        needs_midi = if is_instrument { "TRUE" } else { "FALSE" },
    );

    fs::write(dir.join("CMakeLists.txt"), content).map_err(|e| e.to_string())
}

fn write_claude_md(
    dir: &Path,
    name: &str,
    plugin_type: &str,
    interface_style: &str,
    prompt: &str,
    channel_layout: &str,
) -> Result<(), String> {
    let plugin_role = match plugin_type {
        "instrument" => "playable instrument",
        "utility" => "utility or analysis tool",
        _ => "audio effect",
    };

    // Foundry Kit skills are inlined directly so Claude receives them in context
    // without any Read calls. Read is disallowed in generate phases to prevent
    // wasted turns, so file references would be silently ignored anyway.
    let sound_engineer = include_str!("../../../foundry-kit/skills/sound-engineer/SKILL.md");
    let juce_expert    = include_str!("../../../foundry-kit/skills/juce-expert/SKILL.md");
    let art_director   = include_str!("../../../foundry-kit/skills/art-director/SKILL.md");
    let beatmaker      = include_str!("../../../foundry-kit/skills/beatmaker/SKILL.md");

    let content = format!(
        r#"# {name} — JUCE Plugin

## Mission
Build a JUCE {role} plugin: {prompt}

## Plugin Type
{plugin_type}

## Channel Layout
{channels}

## Interface Direction
{style} — adjust the number and complexity of controls accordingly.

## Source Files
- Source/PluginProcessor.h
- Source/PluginProcessor.cpp
- Source/PluginEditor.h
- Source/PluginEditor.cpp
- Source/FoundryLookAndFeel.h

## Phase Rules
- The orchestration prompt is phase-aware and authoritative.
- Processor phase: create only PluginProcessor.h and PluginProcessor.cpp. Write immediately.
- UI phase: create only FoundryLookAndFeel.h, PluginEditor.h, PluginEditor.cpp. Write immediately.
- Do not plan or explain before writing. First tool call must be Write.
- Stop when the requested phase is complete.

---

# Foundry Kit — Expert Knowledge

The following expert personas define the quality standard for every plugin. Apply them. A plugin that compiles but sounds generic or looks like a scrollable list of sliders has failed.

---

{sound_engineer}

---

{juce_expert}

---

{art_director}

---

{beatmaker}
"#,
        name = name,
        role = plugin_role,
        prompt = prompt,
        plugin_type = plugin_type,
        channels = channel_layout,
        style = interface_style,
        sound_engineer = sound_engineer,
        juce_expert = juce_expert,
        art_director = art_director,
        beatmaker = beatmaker,
    );

    fs::write(dir.join("CLAUDE.md"), content).map_err(|e| e.to_string())
}

/// Write AGENTS.md — the Codex equivalent of CLAUDE.md.
/// Same inlined content so Codex receives the Foundry Kit without any Read calls.
fn write_agents_md(
    dir: &Path,
    name: &str,
    plugin_type: &str,
    interface_style: &str,
    prompt: &str,
    channel_layout: &str,
) -> Result<(), String> {
    let plugin_role = match plugin_type {
        "instrument" => "playable instrument",
        "utility" => "utility or analysis tool",
        _ => "audio effect",
    };

    let sound_engineer = include_str!("../../../foundry-kit/skills/sound-engineer/SKILL.md");
    let juce_expert    = include_str!("../../../foundry-kit/skills/juce-expert/SKILL.md");
    let art_director   = include_str!("../../../foundry-kit/skills/art-director/SKILL.md");
    let beatmaker      = include_str!("../../../foundry-kit/skills/beatmaker/SKILL.md");

    let content = format!(
        r#"# {name} — JUCE Plugin

## Mission
Build a JUCE {role} plugin: {prompt}

## Plugin Type
{plugin_type}

## Channel Layout
{channels}

## Interface Direction
{style} — adjust the number and complexity of controls accordingly.

## Source Files
- Source/PluginProcessor.h
- Source/PluginProcessor.cpp
- Source/PluginEditor.h
- Source/PluginEditor.cpp
- Source/FoundryLookAndFeel.h

## Phase Rules
- The orchestration prompt is phase-aware and authoritative.
- Processor phase: create only PluginProcessor.h and PluginProcessor.cpp. Write immediately.
- UI phase: create only FoundryLookAndFeel.h, PluginEditor.h, PluginEditor.cpp. Write immediately.
- Do not plan or explain before writing. First tool call must be Write.
- Stop when the requested phase is complete.

---

# Foundry Kit — Expert Knowledge

The following expert personas define the quality standard for every plugin. Apply them. A plugin that compiles but sounds generic or looks like a scrollable list of sliders has failed.

---

{sound_engineer}

---

{juce_expert}

---

{art_director}

---

{beatmaker}
"#,
        name = name,
        role = plugin_role,
        prompt = prompt,
        plugin_type = plugin_type,
        channels = channel_layout,
        style = interface_style,
        sound_engineer = sound_engineer,
        juce_expert = juce_expert,
        art_director = art_director,
        beatmaker = beatmaker,
    );

    fs::write(dir.join("AGENTS.md"), content).map_err(|e| e.to_string())
}

fn write_foundry_kit(project_dir: &Path) -> Result<(), String> {
    let kit_dir = project_dir.join("foundry-kit");
    let skills_dir = kit_dir.join("skills");

    fs::create_dir_all(skills_dir.join("sound-engineer")).map_err(|e| e.to_string())?;
    fs::create_dir_all(skills_dir.join("beatmaker")).map_err(|e| e.to_string())?;
    fs::create_dir_all(skills_dir.join("juce-expert")).map_err(|e| e.to_string())?;
    fs::create_dir_all(skills_dir.join("art-director")).map_err(|e| e.to_string())?;

    fs::write(
        kit_dir.join("SKILL.md"),
        include_str!("../../../foundry-kit/SKILL.md"),
    )
    .map_err(|e| e.to_string())?;
    fs::write(
        skills_dir.join("sound-engineer/SKILL.md"),
        include_str!("../../../foundry-kit/skills/sound-engineer/SKILL.md"),
    )
    .map_err(|e| e.to_string())?;
    fs::write(
        skills_dir.join("beatmaker/SKILL.md"),
        include_str!("../../../foundry-kit/skills/beatmaker/SKILL.md"),
    )
    .map_err(|e| e.to_string())?;
    fs::write(
        skills_dir.join("juce-expert/SKILL.md"),
        include_str!("../../../foundry-kit/skills/juce-expert/SKILL.md"),
    )
    .map_err(|e| e.to_string())?;
    fs::write(
        skills_dir.join("art-director/SKILL.md"),
        include_str!("../../../foundry-kit/skills/art-director/SKILL.md"),
    )
    .map_err(|e| e.to_string())?;

    Ok(())
}

fn rand_byte() -> u8 {
    uuid::Uuid::new_v4().as_bytes()[0]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn instrument_keywords_beat_weak_utility_hints() {
        assert_eq!(
            infer_plugin_type(
                "Warm polysynth with phase modulation, stereo width, resonant filter, and drifting oscillators"
            ),
            "instrument"
        );
    }

    #[test]
    fn utility_keywords_win_for_analysis_tools() {
        assert_eq!(
            infer_plugin_type(
                "Real-time spectrum analyzer with phase correlation meter, LUFS readout, and true peak tracking"
            ),
            "utility"
        );
    }

    #[test]
    fn effect_keywords_stay_effects_even_with_width_controls() {
        assert_eq!(
            infer_plugin_type("Tape delay with wow, flutter, stereo width, and wet dry mix"),
            "effect"
        );
    }

    #[test]
    fn explicit_plugin_type_override_wins_over_prompt_inference() {
        assert_eq!(
            resolve_plugin_type(
                "Warm analog polysynth with detuned oscillators",
                Some("utility")
            ),
            "utility"
        );
    }

    #[test]
    fn writes_foundry_kit_skill_files() {
        let dir = std::env::temp_dir().join(format!("foundry-kit-test-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&dir).unwrap();

        write_foundry_kit(&dir).unwrap();

        assert!(dir.join("foundry-kit/SKILL.md").exists());
        assert!(dir
            .join("foundry-kit/skills/sound-engineer/SKILL.md")
            .exists());
        assert!(dir.join("foundry-kit/skills/beatmaker/SKILL.md").exists());
        assert!(dir.join("foundry-kit/skills/juce-expert/SKILL.md").exists());
        assert!(dir
            .join("foundry-kit/skills/art-director/SKILL.md")
            .exists());

        let _ = fs::remove_dir_all(dir);
    }
}
