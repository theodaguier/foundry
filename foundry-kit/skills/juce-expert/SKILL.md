---
name: juce-expert
description: Senior JUCE C++ developer for correct, efficient plugin code that compiles on first attempt.
---

# JUCE Expert

You write code that compiles. You know the common pitfalls.

## Core Requirements

### Parameter Layout

```cpp
// In createParameterLayout():
layout.add(std::make_unique<juce::AudioParameterFloat>(
    juce::ParameterID{"drive", 1}, "Drive",  // Must match ID used in editor
    juce::NormalisableRange<float>(0.0f, 100.0f, 0.1f, 0.5f), 
    20.0f));
```

### SmoothedValue — mandatory for real-time parameters

```cpp
// Header:
juce::SmoothedValue<float> paramSmooth;

// prepareToPlay:
paramSmooth.reset(sampleRate, 0.02);  // 20ms ramp

// processBlock:
paramSmooth.setTargetValue(apvts.getRawParameterValue("param_id")->load());
float value = paramSmooth.getNextValue();
```

### Oversampling — for distortion/waveshaping

```cpp
// Header:
juce::dsp::Oversampling<float> oversampling{2, 2, 
    juce::dsp::Oversampling<float>::filterHalfBandPolyphaseIIR};

// prepareToPlay:
oversampling.initProcessing(samplesPerBlock);

// processBlock:
auto osBlock = oversampling.processSamplesUp(block);
// process in oversampled domain
oversampling.processSamplesDown(block);
```

### Dry/wet parallel (effects)

```cpp
juce::AudioBuffer<float> dry; dry.makeCopyOf(buffer);
// ... process buffer (wet) ...
float mix = mixSmoothed.getNextValue();
for (int ch = 0; ch < buffer.getNumChannels(); ++ch) {
    auto* wet = buffer.getWritePointer(ch);
    auto* d = dry.getReadPointer(ch);
    for (int i = 0; i < buffer.getNumSamples(); ++i)
        wet[i] = d[i] * (1.0f - mix) + wet[i] * mix;
}
```

## Common Mistakes (14 killers)

1. `juce::Font(float)` → use `juce::Font(juce::FontOptions(float))`
2. Lambda captures: `auto*` → explicit `[this]` or `[&param = param]`
3. Duplicate ParameterIDs: every `{"id", 1}` must be unique
4. `.h` / `.cpp` mismatch: must be identical signatures
5. Missing `juce::` prefix: `Slider` → `juce::Slider`
6. `juce::Reverb` → `juce::dsp::Reverb`
7. LookAndFeel before components: declare BEFORE any slider in header
8. Include `JuceHeader.h` in every source file
9. Missing `#include <JuceHeader.h>` → compilation fails
10. Division by zero: check `if (sampleRate > 0.0)`
11. Hardcoded sample rates: use `getSampleRate()` not `44100.0f`
12. Missing `adsr.setSampleRate()` in startNote → wrong pitch
13. Elliptical knobs: use `jmin(width, height)` before drawing arcs
14. Duplicate labels: ONE label per control, managed ONE way

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

## Synthesis (instruments)

```cpp
class MyVoice : public juce::SynthesiserVoice {
public:
    bool canPlaySound(juce::SynthesiserSound* s) override { 
        return dynamic_cast<MySound*>(s) != nullptr; 
    }
    void startNote(int note, float vel, juce::SynthesiserSound*, int) override {
        frequency = juce::MidiMessage::getMidiNoteInHertz(note);
        level = vel;
        adsr.setSampleRate(getSampleRate());
        adsr.noteOn();
    }
    void stopNote(float vel, bool tail) override { 
        if (tail) adsr.noteOff(); 
        else { adsr.reset(); clearCurrentNote(); } 
    }
    void renderNextBlock(juce::AudioBuffer<float>& buf, int start, int n) override {
        if (!adsr.isActive()) return;
        // Generate audio
        if (!adsr.isActive()) clearCurrentNote();
    }
private: 
    double frequency = 440.0;
    float level = 0.0f;
    juce::ADSR adsr;
};
```

## Factory Presets (optional but recommended)

```cpp
struct FactoryPreset {
    const char* name;
    std::vector<std::pair<juce::String, float>> values;  // paramID → value
};

std::vector<FactoryPreset> createFactoryPresets() {
    return {
        { "Default",    { {"drive", 20.0f}, {"mix", 50.0f} } },
        { "Warm Tape",  { {"drive", 45.0f}, {"mix", 70.0f} } },
        { "Crispy",    { {"drive", 80.0f}, {"mix", 60.0f} } },
    };
}
```

Save/load with `getStateInformation()` / `setStateInformation()`.

## NormalisableRange Reference

```cpp
// Frequency: log scale
juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.25f)

// Time ms: log-ish
juce::NormalisableRange<float>(1.0f, 5000.0f, 0.1f, 0.35f)

// Gain dB: linear
juce::NormalisableRange<float>(-60.0f, 12.0f, 0.1f)

// LFO rate: log-ish  
juce::NormalisableRange<float>(0.05f, 10.0f, 0.01f, 0.4f)
```