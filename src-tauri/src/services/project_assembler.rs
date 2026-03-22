use std::fs;
use std::path::{Path, PathBuf};

use crate::services::foundry_paths;

pub struct AssembledProject {
    pub directory: PathBuf,
    pub plugin_name: String,
    pub plugin_type: String,  // "instrument", "effect", "utility"
}

pub fn infer_plugin_type(prompt: &str) -> String {
    let lower = prompt.to_lowercase();
    let utility_keywords = [
        "utility", "analyzer", "meter", "scope", "monitor", "phase", "mono",
        "gain staging", "trim", "width", "balance", "imager", "tool",
    ];
    if utility_keywords.iter().any(|kw| lower.contains(kw)) {
        return "utility".to_string();
    }
    let instrument_keywords = [
        "instrument", "synth", "synthesizer", "oscillator", "polyphon",
        "monophon", "keys", "pad", "lead", "bass synth", "arpeggiator",
        "sampler", "rompler", "drum machine", "keyboard", "organ", "piano",
    ];
    if instrument_keywords.iter().any(|kw| lower.contains(kw)) {
        return "instrument".to_string();
    }
    "effect".to_string()
}

fn infer_interface_style(prompt: &str, plugin_type: &str) -> &'static str {
    let lower = prompt.to_lowercase();
    let focused = ["simple", "minimal", "clean", "focused", "few controls", "macro", "one knob", "two knobs", "three knobs", "fast"];
    if focused.iter().any(|kw| lower.contains(kw)) { return "Focused"; }
    let exploratory = [
        "advanced", "deep", "modular", "matrix", "granular", "sequencer",
        "multi-stage", "complex", "dense", "experimental", "modulation",
        "synth", "synthesizer", "analog", "subtractive", "fm", "wavetable",
        "polysynth", "poly synth",
    ];
    if exploratory.iter().any(|kw| lower.contains(kw)) { return "Exploratory"; }
    match plugin_type {
        "utility" => "Focused",
        "instrument" => "Exploratory",
        _ => "Balanced",
    }
}

pub fn assemble(
    prompt: &str,
    plugin_name: &str,
    format: &str,        // "au", "vst3", "both"
    channel_layout: &str, // "mono", "stereo"
    _preset_count: i32,
    _model: &str,
) -> Result<AssembledProject, String> {
    let plugin_type = infer_plugin_type(prompt);
    let interface_style = infer_interface_style(prompt, &plugin_type);

    let uuid = uuid::Uuid::new_v4().to_string();
    let short = &uuid[..8];
    let project_dir = PathBuf::from(format!("/tmp/foundry-build-{}", short));
    let source_dir = project_dir.join("Source");
    let kit_dir = project_dir.join("juce-kit");

    fs::create_dir_all(&source_dir).map_err(|e| e.to_string())?;
    fs::create_dir_all(&kit_dir).map_err(|e| e.to_string())?;

    write_cmake_lists(&project_dir, plugin_name, &plugin_type, format)?;
    write_juce_kit(&kit_dir, plugin_name, &plugin_type)?;
    write_claude_md(&project_dir, plugin_name, &plugin_type, interface_style, prompt, channel_layout)?;

    Ok(AssembledProject {
        directory: project_dir,
        plugin_name: plugin_name.to_string(),
        plugin_type,
    })
}

fn write_cmake_lists(dir: &Path, name: &str, plugin_type: &str, format: &str) -> Result<(), String> {
    let juce_path = foundry_paths::juce_dir();
    let juce_str = juce_path.to_string_lossy();
    let prefix: String = name.chars().take(2).collect::<String>().to_uppercase();
    let suffix = format!("{:02X}", rand_byte());
    let plugin_code: String = format!("{}{}", prefix, suffix).chars().take(4).collect();
    let is_instrument = plugin_type == "instrument";

    let formats = match format.to_uppercase().as_str() {
        "AU" => "AU",
        "VST3" => "VST3",
        _ => "AU VST3",
    };

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

## Files to Create
- Source/PluginProcessor.h
- Source/PluginProcessor.cpp
- Source/PluginEditor.h
- Source/PluginEditor.cpp
- Source/FoundryLookAndFeel.h

## Knowledge Kit
Read these reference files for API patterns and build rules:
- juce-kit/juce-api.md
- juce-kit/dsp-patterns.md
- juce-kit/ui-patterns.md
- juce-kit/look-and-feel.md
- juce-kit/build-rules.md
- juce-kit/presets.md

## Workflow
1. Read this file + all juce-kit/*.md files in PARALLEL
2. Write all 5 source files using PARALLEL Write calls
3. Do NOT verify — trust your output

## Design Principles
- Every parameter uses AudioProcessorValueTreeState (APVTS)
- Every UI control has a matching Attachment (SliderAttachment, ComboBoxAttachment, ButtonAttachment)
- All JUCE types use juce:: prefix
- FoundryLookAndFeel customizes the visual appearance
- C++17, no auto* parameters, .h/.cpp signatures must match

## Creative Direction
Make it sound and look professional. The plugin should feel like a premium commercial product.
"#,
        name = name,
        role = plugin_role,
        prompt = prompt,
        plugin_type = plugin_type,
        channels = channel_layout,
        style = interface_style,
    );

    fs::write(dir.join("CLAUDE.md"), content).map_err(|e| e.to_string())
}

fn write_juce_kit(dir: &Path, plugin_name: &str, plugin_type: &str) -> Result<(), String> {
    write_juce_api(dir, plugin_name, plugin_type)?;
    write_dsp_patterns(dir, plugin_type)?;
    write_ui_patterns(dir, plugin_name)?;
    write_look_and_feel(dir)?;
    write_build_rules(dir, plugin_name)?;
    write_presets(dir, plugin_name)?;
    Ok(())
}

fn write_juce_api(dir: &Path, _name: &str, plugin_type: &str) -> Result<(), String> {
    let instrument_api = if plugin_type == "instrument" {
        r#"
### Synthesiser + Voice (instruments only)

```cpp
synth.addSound(new MySynthSound());
synth.addVoice(new MySynthVoice());
synth.setCurrentPlaybackSampleRate(sr);
synth.renderNextBlock(buffer, midi, 0, numSamples);
```

Voice must override: `canPlaySound()`, `startNote()`, `stopNote()`, `renderNextBlock()`, `pitchWheelMoved()`, `controllerMoved()`.
"#
    } else { "" };

    let content = format!(
        r#"# JUCE API Reference

## AudioProcessorValueTreeState (APVTS)
```cpp
auto layout = juce::AudioProcessorValueTreeState::ParameterLayout();
layout.add(std::make_unique<juce::AudioParameterFloat>(
    juce::ParameterID("gain", 1), "Gain",
    juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.5f));
apvts(processor, nullptr, "Parameters", std::move(layout));
auto* param = apvts.getRawParameterValue("gain");
```

## AudioBuffer
```cpp
buffer.getNumChannels();
buffer.getNumSamples();
auto* channelData = buffer.getWritePointer(channel);
buffer.clear();
```

## DSP Module Classes
```cpp
juce::dsp::ProcessorChain<...>
juce::dsp::Gain<float>
juce::dsp::Reverb
juce::dsp::Chorus<float>
juce::dsp::Phaser<float>
juce::dsp::Compressor<float>
juce::dsp::LadderFilter<float>
juce::dsp::StateVariableTPTFilter<float>
juce::dsp::DelayLine<float>
juce::dsp::Oscillator<float>
juce::dsp::IIR::Filter<float>
juce::dsp::FIR::Filter<float>
juce::dsp::Convolution
juce::dsp::WaveShaper<float>
juce::dsp::Oversampling<float>
```
{instrument_api}
"#,
        instrument_api = instrument_api,
    );
    fs::write(dir.join("juce-api.md"), content).map_err(|e| e.to_string())
}

fn write_dsp_patterns(dir: &Path, plugin_type: &str) -> Result<(), String> {
    let type_patterns = match plugin_type {
        "instrument" => r#"
## Instrument Patterns
- Synthesiser manages voices; each voice has its own oscillator + envelope
- ADSR envelope controls amplitude; optionally filter envelope
- Voice::renderNextBlock fills a buffer for one voice; Synthesiser sums them
- Use juce::dsp::Oscillator or manual wavetable for sound generation
- Map MIDI note to frequency: juce::MidiMessage::getMidiNoteInHertz(noteNumber)
"#,
        "utility" => r#"
## Utility Patterns
- Gain: multiply samples by linear gain (dB → linear: juce::Decibels::decibelsToGain)
- Width: mid/side processing (mid = (L+R)/2, side = (L-R)/2)
- Phase: invert one or both channels
- Metering: track RMS/peak per channel, update UI via atomic floats
"#,
        _ => r#"
## Effect Patterns
- Serial chain: input → effect1 → effect2 → output
- Parallel: split → process each path → sum
- Feedback: output → delay → mix back to input
- Modulation: LFO modulates a parameter (rate, depth, shape)
- Envelope follower: track amplitude → control another parameter
"#,
    };

    let content = format!(
        "# DSP Patterns\n{}\n",
        type_patterns
    );
    fs::write(dir.join("dsp-patterns.md"), content).map_err(|e| e.to_string())
}

fn write_ui_patterns(dir: &Path, _name: &str) -> Result<(), String> {
    let content = r#"# UI Patterns

## Editor Structure
```cpp
class PluginEditor : public juce::AudioProcessorEditor {
    PluginEditor(PluginProcessor&);
    void paint(juce::Graphics&) override;
    void resized() override;
private:
    PluginProcessor& processor;
    FoundryLookAndFeel lookAndFeel;
    juce::Slider gainSlider;
    std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> gainAttachment;
};
```

## Wiring Controls
```cpp
// In constructor:
gainSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
gainSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 20);
addAndMakeVisible(gainSlider);
gainAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
    processor.apvts, "gain", gainSlider);
```

## Layout in resized()
```cpp
auto bounds = getLocalBounds().reduced(20);
auto topArea = bounds.removeFromTop(bounds.getHeight() / 2);
gainSlider.setBounds(topArea.removeFromLeft(topArea.getWidth() / 2).reduced(10));
```
"#;
    fs::write(dir.join("ui-patterns.md"), content).map_err(|e| e.to_string())
}

fn write_look_and_feel(dir: &Path) -> Result<(), String> {
    let content = r#"# Look and Feel

## FoundryLookAndFeel : public juce::LookAndFeel_V4
Create a custom LookAndFeel that gives the plugin a polished, professional appearance.

### Required Colour IDs to set:
- juce::Slider::rotarySliderFillColourId
- juce::Slider::rotarySliderOutlineColourId
- juce::Slider::thumbColourId
- juce::Slider::textBoxTextColourId
- juce::Slider::textBoxOutlineColourId
- juce::Label::textColourId
- juce::ComboBox::backgroundColourId
- juce::ComboBox::textColourId
- juce::TextButton::buttonColourId
- juce::TextButton::textColourOnId
- juce::ResizableWindow::backgroundColourId

### Lifecycle Rules
- Set LookAndFeel in Editor constructor: `setLookAndFeel(&lookAndFeel);`
- Clear in destructor: `setLookAndFeel(nullptr);`
- LookAndFeel must outlive all components — declare it BEFORE any sliders/buttons in the header.

### Knob Styles
Override `drawRotarySlider()` for custom knobs. Common styles:
- Arc style: draw background arc + value arc
- Filled dot: circle at value position on arc
- Minimal: just a line indicator

### Font Constructor
ALWAYS use: `juce::Font(juce::FontOptions(fontSize))`
NEVER use: `juce::Font(fontSize)` — this constructor is deprecated and causes build errors.
"#;
    fs::write(dir.join("look-and-feel.md"), content).map_err(|e| e.to_string())
}

fn write_build_rules(dir: &Path, plugin_name: &str) -> Result<(), String> {
    let content = format!(
        r#"# Build Rules

## Naming
- Processor class: `{name}Processor`
- Editor class: `{name}Editor`
- These names MUST match CMakeLists.txt PRODUCT_NAME

## C++17
- Use `std::make_unique`, `auto`, range-based for
- No raw `new` for owned objects

## juce:: Namespace
- EVERY JUCE type must use `juce::` prefix
- `juce::Slider`, `juce::AudioProcessorValueTreeState`, `juce::Graphics`, etc.

## 12 Fatal Mistakes
1. `auto*` in lambda captures — use explicit types
2. Duplicate parameter IDs in APVTS layout
3. .h/.cpp signature mismatch — they must be identical
4. `juce::Font(float)` — use `juce::Font(juce::FontOptions(float))`
5. Parameter ID string mismatch between Processor and Editor
6. Missing `#include` — include JuceHeader.h in every file
7. Linker errors are SOURCE errors, not CMakeLists.txt errors
8. `juce::Reverb` — use `juce::dsp::Reverb`
9. LookAndFeel must outlive components — declare BEFORE sliders in header
10. PopupMenu colours need explicit `setColour()` calls
11. Hardcoded sample rates — always use `getSampleRate()`
12. Division by zero — check denominators
"#,
        name = plugin_name,
    );
    fs::write(dir.join("build-rules.md"), content).map_err(|e| e.to_string())
}

fn write_presets(dir: &Path, plugin_name: &str) -> Result<(), String> {
    let content = format!(
        r#"# Presets

## JUCE Program System
```cpp
// In {name}Processor:
int getNumPrograms() override {{ return presets.size(); }}
int getCurrentProgram() override {{ return currentPreset; }}
void setCurrentProgram(int index) override {{
    currentPreset = index;
    // Apply preset values to APVTS parameters
}}
juce::String getProgramName(int index) override {{ return presets[index].name; }}
```

## Preset Structure
```cpp
struct PresetData {{
    juce::String name;
    std::map<juce::String, float> values;
}};
```

## ComboBox Wiring
```cpp
presetSelector.onChange = [this]() {{
    processor.setCurrentProgram(presetSelector.getSelectedItemIndex());
}};
```
"#,
        name = plugin_name,
    );
    fs::write(dir.join("presets.md"), content).map_err(|e| e.to_string())
}

fn rand_byte() -> u8 {
    uuid::Uuid::new_v4().as_bytes()[0]
}
