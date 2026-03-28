use std::fs;
use std::path::{Path, PathBuf};

pub struct AssembledProject {
    pub directory: PathBuf,
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

/// Creative profile fields injected into the mission brief.
pub struct CreativeContext {
    pub signature_interaction: String,
    pub control_strategy: String,
    pub ui_direction: String,
    pub sonic_hook: String,
    pub contrast_detail: String,
    pub sound_design_focus: String,
    pub visualization_focus: String,
    pub control_palette: String,
    pub anti_template_warning: String,
    pub editor_width: i32,
    pub editor_height: i32,
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
    creative_context: Option<&CreativeContext>,
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

    let brief = build_mission_brief(
        plugin_name,
        &plugin_type,
        interface_style,
        prompt,
        channel_layout,
        creative_context,
    );
    fs::write(project_dir.join("CLAUDE.md"), &brief).map_err(|e| e.to_string())?;
    fs::write(project_dir.join("AGENTS.md"), &brief).map_err(|e| e.to_string())?;

    Ok(AssembledProject {
        directory: project_dir,
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


fn select_skills_for_type(plugin_type: &str) -> String {
    let juce_expert = include_str!("../../../foundry-kit/skills/juce-expert/SKILL.md");
    let art_director = include_str!("../../../foundry-kit/skills/art-director/SKILL.md");

    // Always include juce-expert (compiler rules) and art-director (UI rules).
    // Add sound-engineer or beatmaker based on plugin type.
    let domain_skill = match plugin_type {
        "instrument" => include_str!("../../../foundry-kit/skills/beatmaker/SKILL.md"),
        _ => include_str!("../../../foundry-kit/skills/sound-engineer/SKILL.md"),
    };

    format!(
        "{juce_expert}\n\n---\n\n{art_director}\n\n---\n\n{domain_skill}",
        juce_expert = juce_expert,
        art_director = art_director,
        domain_skill = domain_skill,
    )
}

fn plugin_type_constraints(plugin_type: &str) -> &'static str {
    match plugin_type {
        "instrument" => {
            "- This is a playable instrument, not an insert effect or utility.\n\
            - Generate sound from MIDI note events. Use `juce::Synthesiser` + voices.\n\
            - The default preset must be immediately playable and sound good.\n\
            - Do not build a pass-through chain with only metering or gain utilities."
        }
        "utility" => {
            "- Prioritize metering, analysis, routing, correction, or gain utility workflows.\n\
            - Do not add fake synth voices or a decorative wet/dry FX chain unless the brief asks for it.\n\
            - Processing should be technical, transparent, and purpose-driven."
        }
        _ => {
            "- This is an audio effect. Process incoming audio in `processBlock`.\n\
            - Do not require MIDI-note playback or build a synth voice architecture unless the brief asks.\n\
            - A clear input → effect → output signal path is expected."
        }
    }
}

fn build_mission_brief(
    name: &str,
    plugin_type: &str,
    interface_style: &str,
    prompt: &str,
    channel_layout: &str,
    creative_context: Option<&CreativeContext>,
) -> String {
    let plugin_role = match plugin_type {
        "instrument" => "playable instrument",
        "utility" => "utility or analysis tool",
        _ => "audio effect",
    };
    let type_constraints = plugin_type_constraints(plugin_type);
    let skills = select_skills_for_type(plugin_type);

    let creative_section = if let Some(ctx) = creative_context {
        format!(
            r#"## Creative Direction

- Signature interaction: {signature_interaction}
- Sonic hook: {sonic_hook}
- Sound design focus: {sound_design_focus}
- Control strategy: {control_strategy}
- UI direction: {ui_direction}
- Contrast detail: {contrast_detail}
- Visualization focus: {visualization_focus}
- Control palette: {control_palette}
- Anti-template: {anti_template_warning}
- Target editor size: {editor_width}x{editor_height}"#,
            signature_interaction = ctx.signature_interaction,
            sonic_hook = ctx.sonic_hook,
            sound_design_focus = ctx.sound_design_focus,
            control_strategy = ctx.control_strategy,
            ui_direction = ctx.ui_direction,
            contrast_detail = ctx.contrast_detail,
            visualization_focus = ctx.visualization_focus,
            control_palette = ctx.control_palette,
            anti_template_warning = ctx.anti_template_warning,
            editor_width = ctx.editor_width,
            editor_height = ctx.editor_height,
        )
    } else {
        String::new()
    };

    format!(
        r#"# {name} — JUCE Plugin

## Mission
Build a complete, compilable JUCE {role} plugin: {prompt}

## Plugin Type
{plugin_type}

## Channel Layout
{channels}

## Interface Direction
{interface_style}

{creative_section}

## Source Files to Create

You must create all five files in Source/:

### Phase 1 — Processor (write these first)
- `Source/PluginProcessor.h`
- `Source/PluginProcessor.cpp`

### Phase 2 — UI (write these after the processor)
- `Source/FoundryLookAndFeel.h`
- `Source/PluginEditor.h`
- `Source/PluginEditor.cpp`

## Architecture Rules
- Class names: `{name}Processor` and `{name}Editor`.
- Use `juce::` prefix everywhere. Include `JuceHeader.h` in all files.
- Implement APVTS parameters with real processBlock logic. No dead controls.
- Use `FoundryLookAndFeel` in the editor. Every visible control needs an APVTS attachment.
- Editor must call `setSize(width, height)` with explicit numeric landscape dimensions.
- Layout from `getLocalBounds().reduced(...)` — no absolute coordinates, no scrolling.
- Multi-zone layout: header/display, hero control region, secondary sections. Not a single vertical column.
- Implement 5 factory presets using JUCE's program API (`getNumPrograms`, `setCurrentProgram`, `getProgramName`). Name them with vibe/character — not "Preset 1". See juce-expert and beatmaker skills for the pattern.
- Add a preset ComboBox in the editor header zone. See art-director skill for the pattern.
- Do NOT touch CMakeLists.txt.
{type_constraints}

## Workflow
- Write the processor files first (Phase 1), then the UI files (Phase 2).
- You know the parameters you just created — use the same IDs in the editor attachments.
- Be decisive. Write complete files. Do not plan or explain before writing.
- If you spot an error after writing, fix it with a targeted Edit.

---

# Expert Knowledge

{skills}
"#,
        name = name,
        role = plugin_role,
        prompt = prompt,
        plugin_type = plugin_type,
        channels = channel_layout,
        interface_style = interface_style,
        creative_section = creative_section,
        type_constraints = type_constraints,
        skills = skills,
    )
}

fn write_cmake_lists(
    dir: &Path,
    name: &str,
    plugin_type: &str,
    format: &str,
    juce_path: &Path,
) -> Result<(), String> {
    // CMake requires forward slashes even on Windows — backslashes are
    // interpreted as escape sequences inside strings.
    let juce_str = juce_path.to_string_lossy().replace('\\', "/");
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
