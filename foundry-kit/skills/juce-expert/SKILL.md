---
name: juce-expert
description: Senior JUCE C++ developer for correct, efficient plugin code that compiles on first attempt.
---

# JUCE Expert

You write code that compiles on the first attempt. You know every pitfall by heart.

## Phase Discipline — Write First, Always

**In `generate_processor` mode:** Turn 1 = Write `PluginProcessor.h`. Turn 2 = Write `PluginProcessor.cpp`. Turn 3 (only if needed) = one Edit. Then stop. Do NOT read files first. Do NOT explain before writing. The first tool call must be Write.

**In `generate_ui` mode:** Turn 1 = Write `FoundryLookAndFeel.h` + `PluginEditor.h`. Turn 2 = Write `PluginEditor.cpp`. Turn 3 = one Edit if needed. Stop.

If you spend Turn 1 on text or Read, the pipeline times out with:
`DSP pass did not create processor files: Source/PluginProcessor.h, Source/PluginProcessor.cpp`

## Parameter Layout

```cpp
MyProcessor::MyProcessor()
    : AudioProcessor(BusesProperties()
        .withInput("Input", juce::AudioChannelSet::stereo(), true)
        .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      apvts(*this, nullptr, "Parameters", createParameterLayout())
{}

juce::AudioProcessorValueTreeState::ParameterLayout MyProcessor::createParameterLayout()
{
    juce::AudioProcessorValueTreeState::ParameterLayout layout;
    layout.add(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID{"drive", 1}, "Drive",
        juce::NormalisableRange<float>(0.0f, 100.0f, 0.1f, 0.5f), 20.0f));
    return layout;
}
```

## SmoothedValue — mandatory, no exceptions

```cpp
// Header: juce::SmoothedValue<float> driveSmoothed;
// prepareToPlay: driveSmoothed.reset(sampleRate, 0.02);
// processBlock:
driveSmoothed.setTargetValue(apvts.getRawParameterValue("drive")->load());
float drive = driveSmoothed.getNextValue(); // per sample
```

## Oversampling — mandatory for distortion/waveshaping

```cpp
// Header: juce::dsp::Oversampling<float> oversampling{2, 2,
//     juce::dsp::Oversampling<float>::filterHalfBandPolyphaseIIR};
// prepareToPlay: oversampling.initProcessing(samplesPerBlock);
// processBlock:
juce::dsp::AudioBlock<float> block(buffer);
auto osBlock = oversampling.processSamplesUp(block);
for (size_t ch = 0; ch < osBlock.getNumChannels(); ++ch) {
    auto* data = osBlock.getChannelPointer(ch);
    for (size_t i = 0; i < osBlock.getNumSamples(); ++i)
        data[i] = std::tanh(data[i] * drive);
}
oversampling.processSamplesDown(block);
// Factor: 2x = subtle sat, 4x = distortion, 8x = heavy clipping
```

## Dry/wet parallel

```cpp
juce::AudioBuffer<float> dry; dry.makeCopyOf(buffer);
// ... process buffer (wet) ...
float mix = mixSmoothed.getNextValue();
for (int ch = 0; ch < buffer.getNumChannels(); ++ch) {
    auto* wet = buffer.getWritePointer(ch);
    auto* d   = dry.getReadPointer(ch);
    for (int i = 0; i < buffer.getNumSamples(); ++i)
        wet[i] = d[i] * (1.0f - mix) + wet[i] * mix;
}
```

## ProcessorChain

```cpp
juce::dsp::ProcessorChain<juce::dsp::Gain<float>, juce::dsp::StateVariableTPTFilter<float>> chain;
// prepareToPlay:
juce::dsp::ProcessSpec spec{sampleRate, (uint32)samplesPerBlock, (uint32)numChannels};
chain.prepare(spec);
// processBlock:
juce::dsp::AudioBlock<float> block(buffer);
chain.process(juce::dsp::ProcessContextReplacing<float>(block));
```

## Synthesiser voice

```cpp
class MySynthVoice : public juce::SynthesiserVoice {
public:
    bool canPlaySound(juce::SynthesiserSound* s) override { return dynamic_cast<MySynthSound*>(s) != nullptr; }
    void startNote(int note, float vel, juce::SynthesiserSound*, int) override {
        frequency = juce::MidiMessage::getMidiNoteInHertz(note);
        level = vel; phase = 0.0;
        adsr.setSampleRate(getSampleRate()); adsr.noteOn();
    }
    void stopNote(float, bool tail) override { if (tail) adsr.noteOff(); else { adsr.reset(); clearCurrentNote(); } }
    void renderNextBlock(juce::AudioBuffer<float>& buf, int start, int n) override {
        if (!adsr.isActive()) return;
        for (int i = start; i < start + n; ++i) {
            float out = (float)std::sin(juce::MathConstants<double>::twoPi * phase) * level * adsr.getNextSample();
            phase += frequency / getSampleRate(); if (phase >= 1.0) phase -= 1.0;
            for (int ch = 0; ch < buf.getNumChannels(); ++ch) buf.addSample(ch, i, out);
        }
        if (!adsr.isActive()) clearCurrentNote();
    }
    void pitchWheelMoved(int) override {} void controllerMoved(int, int) override {}
private: double frequency = 440.0, phase = 0.0; float level = 0.0f; juce::ADSR adsr;
};
```

## The 12 Compiler Killers

1. `juce::Font(float)` → `juce::Font(juce::FontOptions(float))`
2. `auto*` in lambda captures → explicit: `[this]` or `[&param = myParam]`
3. Duplicate ParameterIDs → every `{"id", 1}` must be unique
4. `.h`/`.cpp` signature mismatch → must be character-for-character identical
5. Missing `juce::` prefix → `Slider` = error; `juce::Slider` = correct
6. `juce::Reverb` → `juce::dsp::Reverb`
7. LookAndFeel after components → declare `FoundryLookAndFeel lookAndFeel` BEFORE any slider in header
8. Missing `#include <JuceHeader.h>` → every file needs it
9. Linker errors = source errors, NOT CMakeLists.txt errors
10. Division by zero → always check: `if (sampleRate > 0.0)`
11. Hardcoded `44100.0f` → always `getSampleRate()`
12. Missing `adsr.setSampleRate()` in `startNote()` → voice pitch wrong

## NormalisableRange mappings

```cpp
juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.25f)  // frequency (log)
juce::NormalisableRange<float>(1.0f, 5000.0f, 0.1f, 0.35f)    // time ms (log-ish)
juce::NormalisableRange<float>(-60.0f, 12.0f, 0.1f)           // gain dB (linear)
juce::NormalisableRange<float>(0.05f, 10.0f, 0.01f, 0.4f)     // LFO rate (log-ish)
```

## LookAndFeel lifecycle

```cpp
// Header: FoundryLookAndFeel lookAndFeel; ← BEFORE any slider
// Constructor: setLookAndFeel(&lookAndFeel);
// Destructor: setLookAndFeel(nullptr);
```

## Factory Presets — mandatory for every plugin

Every plugin ships with 5 factory presets using JUCE's program API. Presets are named with vibe/character (not "Preset 1"). See beatmaker skill for naming.

```cpp
// ── Header ──────────────────────────────────────────────
struct FactoryPreset {
    const char* name;
    std::vector<std::pair<juce::String, float>> values; // paramID → raw value
};

int currentPresetIndex = 0;
static std::vector<FactoryPreset> createFactoryPresets();

int getNumPrograms() override;
int getCurrentProgram() override;
void setCurrentProgram(int index) override;
const juce::String getProgramName(int index) override;
void changeProgramName(int, const juce::String&) override {}

// ── Implementation ──────────────────────────────────────
std::vector<MyProcessor::FactoryPreset> MyProcessor::createFactoryPresets()
{
    return {
        { "Default",     { {"drive", 20.0f}, {"mix", 50.0f} } },
        { "Warm Tape",   { {"drive", 45.0f}, {"mix", 70.0f} } },
        { "Crispy Edge", { {"drive", 80.0f}, {"mix", 60.0f} } },
        // ... 5 presets total, one per role: safe default / genre staple / character / creative / extreme
    };
}

int MyProcessor::getNumPrograms() { return (int)createFactoryPresets().size(); }
int MyProcessor::getCurrentProgram() { return currentPresetIndex; }
const juce::String MyProcessor::getProgramName(int i) {
    auto presets = createFactoryPresets();
    return (i >= 0 && i < (int)presets.size()) ? presets[i].name : juce::String();
}
void MyProcessor::setCurrentProgram(int index) {
    auto presets = createFactoryPresets();
    if (index < 0 || index >= (int)presets.size()) return;
    currentPresetIndex = index;
    for (auto& [id, val] : presets[index].values) {
        if (auto* param = apvts.getParameter(id))
            param->setValueNotifyingHost(param->getNormalisableRange().convertTo0to1(val));
    }
}
```

The preset ComboBox in the editor header is handled by the UI phase (see art-director skill).

## State save/load

```cpp
void getStateInformation(juce::MemoryBlock& d) override {
    auto state = apvts.copyState();
    std::unique_ptr<juce::XmlElement> xml(state.createXml());
    copyXmlToBinary(*xml, d);
}
void setStateInformation(const void* d, int n) override {
    std::unique_ptr<juce::XmlElement> xml(getXmlFromBinary(d, n));
    if (xml && xml->hasTagName(apvts.state.getType()))
        apvts.replaceState(juce::ValueTree::fromXml(*xml));
}
```
