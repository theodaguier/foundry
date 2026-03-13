import Foundation

enum ProjectAssembler {

    struct AssembledProject {
        let directory: URL
        let pluginName: String
        let pluginType: PluginType
        let interfaceStyle: InterfaceStyle
    }

    static let templateMarker = "FOUNDRY_TEMPLATE_PLACEHOLDER"

    enum InterfaceStyle: String {
        case focused = "Focused"
        case balanced = "Balanced"
        case exploratory = "Exploratory"
    }

    // MARK: - Assemble

    static func assemble(config: GenerationConfig) throws -> AssembledProject {
        let fm = FileManager.default

        // Generate a clean plugin name from the prompt
        let pluginName = generatePluginName(from: config.prompt)
        let pluginType = inferPluginType(from: config.prompt)
        let interfaceStyle = inferInterfaceStyle(from: config.prompt, pluginType: pluginType)

        // Create temp directory
        let uuid = UUID().uuidString.prefix(8).lowercased()
        let projectDir = URL(fileURLWithPath: "/tmp/foundry-build-\(uuid)")
        let sourceDir = projectDir.appendingPathComponent("Source")
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        // Write all template files
        try writeCMakeLists(to: projectDir, pluginName: pluginName, pluginType: pluginType, config: config)
        switch pluginType {
        case .instrument:
            try writeSynthProcessor(to: sourceDir, pluginName: pluginName, config: config)
            try writeSynthEditor(to: sourceDir, pluginName: pluginName)
        case .effect:
            try writeEffectProcessor(to: sourceDir, pluginName: pluginName, config: config)
            try writeEffectEditor(to: sourceDir, pluginName: pluginName)
        case .utility:
            try writeUtilityProcessor(to: sourceDir, pluginName: pluginName, config: config)
            try writeUtilityEditor(to: sourceDir, pluginName: pluginName)
        }
        try writeLookAndFeel(to: sourceDir)
        try writeClaudeMD(
            to: projectDir,
            pluginName: pluginName,
            pluginType: pluginType,
            interfaceStyle: interfaceStyle,
            config: config
        )

        return AssembledProject(
            directory: projectDir,
            pluginName: pluginName,
            pluginType: pluginType,
            interfaceStyle: interfaceStyle
        )
    }

    // MARK: - Plugin name generation

    private static func generatePluginName(from prompt: String) -> String {
        let lower = prompt.lowercased()

        let categories: [(keywords: [String], names: [String])] = [
            (["reverb", "room", "hall", "space", "ambient", "cathedral", "plate"],
             ["Aether", "Drift", "Cavern", "Haze", "Vapor", "Void", "Mist", "Dwell"]),
            (["delay", "echo", "repeat", "ping pong"],
             ["Ripple", "Ghost", "Bounce", "Mirage", "Redux", "Trace", "Murmur"]),
            (["distortion", "overdrive", "saturation", "fuzz", "clip", "grit", "crunch", "drive", "waveshap"],
             ["Grind", "Scorch", "Blaze", "Rust", "Havoc", "Oxide", "Snarl", "Ember"]),
            (["filter", "eq", "equaliz", "lowpass", "highpass", "bandpass", "resonan"],
             ["Carve", "Prism", "Sieve", "Tilt", "Slice", "Facet", "Chisel"]),
            (["chorus", "flanger", "phaser", "modulation", "vibrato", "tremolo", "wobble", "ensemble"],
             ["Swirl", "Flux", "Warp", "Morph", "Lush", "Helix", "Bloom"]),
            (["compressor", "limiter", "dynamics", "gate", "expander", "squeeze", "punch", "transient"],
             ["Anvil", "Clamp", "Grip", "Forge", "Press", "Thump", "Crush"]),
            (["synth", "synthesiz", "oscillat", "keys", "pad", "lead", "poly", "mono", "arpeggi"],
             ["Nova", "Volt", "Pulse", "Zephyr", "Onyx", "Spark", "Quasar", "Neon"]),
            (["utility", "gain", "trim", "width", "stereo", "phase", "analy", "meter", "monitor", "mono", "balance"],
             ["Vector", "Atlas", "Scope", "Relay", "Pilot", "Axis", "Mirror", "Align"]),
            (["lofi", "lo-fi", "vinyl", "tape", "vintage", "retro", "warm", "analog"],
             ["Patina", "Grain", "Amber", "Relic", "Dusk", "Moth", "Sepia"]),
            (["pitch", "shift", "harmoniz", "tune", "transpos"],
             ["Apex", "Glide", "Rift", "Arc", "Bend"]),
            (["bass", "sub", "808", "low end"],
             ["Rumble", "Depth", "Quake", "Abyss", "Magma"]),
            (["granular", "grain", "texture", "glitch", "stutter"],
             ["Shard", "Frost", "Scatter", "Flicker", "Pixel"]),
        ]

        // Mix prompt hash with random salt for unique names each generation
        let base = abs(prompt.utf8.reduce(0) { ($0 &* 31) &+ Int($1) })
        let hash = abs(base &+ Int.random(in: 0..<1000))

        for category in categories {
            for keyword in category.keywords {
                if lower.contains(keyword) {
                    return category.names[hash % category.names.count]
                }
            }
        }

        let fallback = ["Null", "Flux", "Apex", "Dusk", "Nova", "Zinc", "Opal", "Noir", "Glow", "Husk"]
        return fallback[hash % fallback.count]
    }

    private static func inferPluginType(from prompt: String) -> PluginType {
        let lower = prompt.lowercased()
        let utilityKeywords = [
            "utility", "analyzer", "meter", "scope", "monitor", "phase", "mono",
            "gain staging", "trim", "width", "balance", "imager", "tool"
        ]
        if utilityKeywords.contains(where: lower.contains) {
            return .utility
        }

        let instrumentKeywords = [
            "instrument", "synth", "synthesizer", "oscillator", "polyphon",
            "monophon", "keys", "pad", "lead", "bass synth", "arpeggiator",
            "sampler", "rompler", "drum machine", "keyboard", "organ", "piano"
        ]
        if instrumentKeywords.contains(where: lower.contains) {
            return .instrument
        }

        return .effect
    }

    private static func inferInterfaceStyle(from prompt: String, pluginType: PluginType) -> InterfaceStyle {
        let lower = prompt.lowercased()

        let focusedKeywords = [
            "simple", "minimal", "clean", "focused", "few controls",
            "macro", "one knob", "two knobs", "three knobs", "fast"
        ]
        if focusedKeywords.contains(where: lower.contains) {
            return .focused
        }

        let exploratoryKeywords = [
            "advanced", "deep", "modular", "matrix", "granular", "sequencer",
            "multi-stage", "complex", "dense", "experimental", "modulation"
        ]
        if exploratoryKeywords.contains(where: lower.contains) {
            return .exploratory
        }

        switch pluginType {
        case .utility:
            return .focused
        case .instrument, .effect:
            return .balanced
        }
    }

    // MARK: - CMakeLists

    private static func writeCMakeLists(
        to dir: URL,
        pluginName: String,
        pluginType: PluginType,
        config: GenerationConfig
    ) throws {
        let jucePath = DependencyChecker.jucePath
        // Generate a unique 4-char plugin code: first 2 chars of name + 2 random hex chars
        let prefix = String(pluginName.prefix(2).uppercased())
        let suffix = String(format: "%02X", Int.random(in: 0..<256))
        let pluginCode = String((prefix + suffix).prefix(4))
        let isInstrument = pluginType == .instrument

        var formats = "AU VST3"
        switch config.format {
        case .au: formats = "AU"
        case .vst3: formats = "VST3"
        case .both: formats = "AU VST3"
        }

        let content = """
        cmake_minimum_required(VERSION 3.22)
        project(\(pluginName) VERSION 1.0.0)

        set(CMAKE_CXX_STANDARD 17)
        set(CMAKE_CXX_STANDARD_REQUIRED ON)

        add_subdirectory("\(jucePath)" ${CMAKE_BINARY_DIR}/JUCE)

        juce_add_plugin(\(pluginName)
            COMPANY_NAME "Foundry"
            PLUGIN_MANUFACTURER_CODE Fndy
            PLUGIN_CODE \(pluginCode)
            FORMATS \(formats)
            PRODUCT_NAME "\(pluginName)"
            IS_SYNTH \(isInstrument ? "TRUE" : "FALSE")
            NEEDS_MIDI_INPUT \(isInstrument ? "TRUE" : "FALSE")
            NEEDS_MIDI_OUTPUT FALSE
            IS_MIDI_EFFECT FALSE
            COPY_PLUGIN_AFTER_BUILD FALSE
        )

        target_sources(\(pluginName) PRIVATE
            Source/PluginProcessor.cpp
            Source/PluginEditor.cpp
        )

        target_compile_definitions(\(pluginName) PUBLIC
            JUCE_WEB_BROWSER=0
            JUCE_USE_CURL=0
            JUCE_VST3_CAN_REPLACE_VST2=0
            JUCE_DISPLAY_SPLASH_SCREEN=0
        )

        target_link_libraries(\(pluginName) PRIVATE
            juce::juce_audio_utils
            juce::juce_dsp
        )

        juce_generate_juce_header(\(pluginName))
        """
        try content.write(to: dir.appendingPathComponent("CMakeLists.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Effect Processor (complete, working)

    private static func writeEffectProcessor(to dir: URL, pluginName: String, config: GenerationConfig) throws {
        let busLayout = config.channelLayout == .stereo
            ? "juce::AudioChannelSet::stereo()"
            : "juce::AudioChannelSet::mono()"

        let header = """
        #pragma once
        #include <JuceHeader.h>

        class \(pluginName)Processor : public juce::AudioProcessor
        {
        public:
            \(pluginName)Processor();
            ~\(pluginName)Processor() override;

            void prepareToPlay(double sampleRate, int samplesPerBlock) override;
            void releaseResources() override;
            void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

            juce::AudioProcessorEditor* createEditor() override;
            bool hasEditor() const override { return true; }

            const juce::String getName() const override { return JucePlugin_Name; }
            bool acceptsMidi() const override { return false; }
            bool producesMidi() const override { return false; }
            double getTailLengthSeconds() const override { return 0.0; }

            int getNumPrograms() override { return 1; }
            int getCurrentProgram() override { return 0; }
            void setCurrentProgram(int) override {}
            const juce::String getProgramName(int) override { return {}; }
            void changeProgramName(int, const juce::String&) override {}

            void getStateInformation(juce::MemoryBlock& destData) override;
            void setStateInformation(const void* data, int sizeInBytes) override;

            juce::AudioProcessorValueTreeState apvts;

        private:
            juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();

            juce::SmoothedValue<float> gainSmoothed;
            juce::SmoothedValue<float> mixSmoothed;

            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Processor)
        };
        """
        try header.write(to: dir.appendingPathComponent("PluginProcessor.h"), atomically: true, encoding: .utf8)

        let impl = """
        #include "PluginProcessor.h"
        #include "PluginEditor.h"

        \(pluginName)Processor::\(pluginName)Processor()
            : AudioProcessor(BusesProperties()
                .withInput("Input", \(busLayout), true)
                .withOutput("Output", \(busLayout), true)),
              apvts(*this, nullptr, "PARAMETERS", createParameterLayout())
        {
        }

        \(pluginName)Processor::~\(pluginName)Processor() {}

        juce::AudioProcessorValueTreeState::ParameterLayout \(pluginName)Processor::createParameterLayout()
        {
            // \(templateMarker): replace these starter effect parameters with a purposeful control set for the requested plugin.
            std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;

            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"gain", 1}, "Gain", 0.0f, 1.0f, 0.7f));
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"mix", 1}, "Mix", 0.0f, 1.0f, 1.0f));

            return { params.begin(), params.end() };
        }

        void \(pluginName)Processor::prepareToPlay(double sampleRate, int)
        {
            gainSmoothed.reset(sampleRate, 0.02);
            mixSmoothed.reset(sampleRate, 0.02);
        }

        void \(pluginName)Processor::releaseResources() {}

        void \(pluginName)Processor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
        {
            // \(templateMarker): replace this default gain/mix processor with the requested audio effect.
            juce::ScopedNoDenormals noDenormals;
            auto totalIn = getTotalNumInputChannels();
            auto totalOut = getTotalNumOutputChannels();
            for (auto i = totalIn; i < totalOut; ++i)
                buffer.clear(i, 0, buffer.getNumSamples());

            gainSmoothed.setTargetValue(apvts.getRawParameterValue("gain")->load());
            mixSmoothed.setTargetValue(apvts.getRawParameterValue("mix")->load());

            juce::AudioBuffer<float> dryBuffer;
            dryBuffer.makeCopyOf(buffer);

            for (int ch = 0; ch < totalIn; ++ch)
            {
                auto* data = buffer.getWritePointer(ch);
                for (int i = 0; i < buffer.getNumSamples(); ++i)
                    data[i] *= gainSmoothed.getNextValue();
            }

            for (int ch = 0; ch < totalIn; ++ch)
            {
                auto* wet = buffer.getWritePointer(ch);
                auto* dry = dryBuffer.getReadPointer(ch);
                for (int i = 0; i < buffer.getNumSamples(); ++i)
                {
                    float m = mixSmoothed.getNextValue();
                    wet[i] = dry[i] * (1.0f - m) + wet[i] * m;
                }
            }
        }

        juce::AudioProcessorEditor* \(pluginName)Processor::createEditor()
        {
            return new \(pluginName)Editor(*this);
        }

        void \(pluginName)Processor::getStateInformation(juce::MemoryBlock& destData)
        {
            auto state = apvts.copyState();
            std::unique_ptr<juce::XmlElement> xml(state.createXml());
            copyXmlToBinary(*xml, destData);
        }

        void \(pluginName)Processor::setStateInformation(const void* data, int sizeInBytes)
        {
            std::unique_ptr<juce::XmlElement> xml(getXmlFromBinary(data, sizeInBytes));
            if (xml != nullptr && xml->hasTagName(apvts.state.getType()))
                apvts.replaceState(juce::ValueTree::fromXml(*xml));
        }

        juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
        {
            return new \(pluginName)Processor();
        }
        """
        try impl.write(to: dir.appendingPathComponent("PluginProcessor.cpp"), atomically: true, encoding: .utf8)
    }

    // MARK: - Effect Editor (complete, working)

    private static func writeEffectEditor(to dir: URL, pluginName: String) throws {
        let header = """
        #pragma once
        #include "PluginProcessor.h"
        #include "FoundryLookAndFeel.h"

        class \(pluginName)Editor : public juce::AudioProcessorEditor
        {
        public:
            explicit \(pluginName)Editor(\(pluginName)Processor&);
            ~\(pluginName)Editor() override;

            void paint(juce::Graphics&) override;
            void resized() override;

        private:
            \(pluginName)Processor& processorRef;
            FoundryLookAndFeel lookAndFeel;

            juce::Slider gainSlider;
            juce::Label gainLabel;
            std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> gainAttachment;

            juce::Slider mixSlider;
            juce::Label mixLabel;
            std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> mixAttachment;

            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Editor)
        };
        """
        try header.write(to: dir.appendingPathComponent("PluginEditor.h"), atomically: true, encoding: .utf8)

        let impl = """
        #include "PluginEditor.h"

        \(pluginName)Editor::\(pluginName)Editor(\(pluginName)Processor& p)
            : AudioProcessorEditor(&p), processorRef(p)
        {
            setLookAndFeel(&lookAndFeel);
            setSize(500, 300);

            // \(templateMarker): redesign this starter editor so the UI reflects the generated effect instead of a generic knob row.
            gainSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
            gainSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
            addAndMakeVisible(gainSlider);
            gainAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                processorRef.apvts, "gain", gainSlider);

            gainLabel.setText("GAIN", juce::dontSendNotification);
            gainLabel.setJustificationType(juce::Justification::centred);
            gainLabel.setFont(juce::Font(juce::FontOptions(11.0f)));
            gainLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
            addAndMakeVisible(gainLabel);

            mixSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
            mixSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
            addAndMakeVisible(mixSlider);
            mixAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                processorRef.apvts, "mix", mixSlider);

            mixLabel.setText("MIX", juce::dontSendNotification);
            mixLabel.setJustificationType(juce::Justification::centred);
            mixLabel.setFont(juce::Font(juce::FontOptions(11.0f)));
            mixLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
            addAndMakeVisible(mixLabel);
        }

        \(pluginName)Editor::~\(pluginName)Editor()
        {
            setLookAndFeel(nullptr);
        }

        void \(pluginName)Editor::paint(juce::Graphics& g)
        {
            g.fillAll(lookAndFeel.backgroundColour);

            auto headerArea = getLocalBounds().removeFromTop(40);
            g.setColour(lookAndFeel.surfaceColour);
            g.fillRect(headerArea);

            g.setColour(lookAndFeel.dimTextColour);
            g.setFont(juce::Font(juce::FontOptions(
                juce::Font::getDefaultMonospacedFontName(), 13.0f, juce::Font::plain)));
            g.drawText("\(pluginName)", headerArea.reduced(12, 0), juce::Justification::centredLeft);
        }

        void \(pluginName)Editor::resized()
        {
            auto area = getLocalBounds().reduced(20);
            area.removeFromTop(50);

            // \(templateMarker): regroup and resize controls to fit the generated effect's hierarchy.
            auto knobWidth = area.getWidth() / 2;
            auto row = area.removeFromTop(120);

            auto col1 = row.removeFromLeft(knobWidth);
            gainSlider.setBounds(col1.removeFromTop(90));
            gainLabel.setBounds(col1.removeFromTop(20));

            auto col2 = row;
            mixSlider.setBounds(col2.removeFromTop(90));
            mixLabel.setBounds(col2.removeFromTop(20));
        }
        """
        try impl.write(to: dir.appendingPathComponent("PluginEditor.cpp"), atomically: true, encoding: .utf8)
    }

    // MARK: - Synth Processor (complete, working)

    private static func writeSynthProcessor(to dir: URL, pluginName: String, config: GenerationConfig) throws {
        let busLayout = config.channelLayout == .stereo
            ? "juce::AudioChannelSet::stereo()"
            : "juce::AudioChannelSet::mono()"

        let header = """
        #pragma once
        #include <JuceHeader.h>

        //==============================================================================
        class \(pluginName)Sound : public juce::SynthesiserSound
        {
        public:
            bool appliesToNote(int) override { return true; }
            bool appliesToChannel(int) override { return true; }
        };

        //==============================================================================
        class \(pluginName)Voice : public juce::SynthesiserVoice
        {
        public:
            bool canPlaySound(juce::SynthesiserSound* s) override
            {
                return dynamic_cast<\(pluginName)Sound*>(s) != nullptr;
            }

            void startNote(int midiNoteNumber, float velocity, juce::SynthesiserSound*, int) override
            {
                frequency = juce::MidiMessage::getMidiNoteInHertz(midiNoteNumber);
                level = velocity;
                phase = 0.0;
                adsr.setSampleRate(getSampleRate());
                adsr.setParameters(adsrParams);
                adsr.noteOn();
            }

            void stopNote(float, bool allowTailOff) override
            {
                if (allowTailOff)
                    adsr.noteOff();
                else
                {
                    adsr.reset();
                    clearCurrentNote();
                }
            }

            void pitchWheelMoved(int) override {}
            void controllerMoved(int, int) override {}

            void renderNextBlock(juce::AudioBuffer<float>& buffer, int startSample, int numSamples) override
            {
                if (!adsr.isActive())
                    return;

                for (int i = startSample; i < startSample + numSamples; ++i)
                {
                    double sample = (2.0 * phase - 1.0) * level;
                    phase += frequency / getSampleRate();
                    if (phase >= 1.0) phase -= 1.0;

                    float env = adsr.getNextSample();
                    float out = static_cast<float>(sample) * env * gain;

                    for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                        buffer.addSample(ch, i, out);
                }

                if (!adsr.isActive())
                    clearCurrentNote();
            }

            void setADSRParams(float a, float d, float s, float r)
            {
                adsrParams = { a, d, s, r };
                adsr.setParameters(adsrParams);
            }

            void updateGain(float g) { gain = g; }

        private:
            double frequency = 440.0;
            double phase = 0.0;
            float level = 0.0f;
            float gain = 0.5f;
            juce::ADSR adsr;
            juce::ADSR::Parameters adsrParams { 0.01f, 0.3f, 0.7f, 0.5f };
        };

        //==============================================================================
        class \(pluginName)Processor : public juce::AudioProcessor
        {
        public:
            \(pluginName)Processor();
            ~\(pluginName)Processor() override;

            void prepareToPlay(double sampleRate, int samplesPerBlock) override;
            void releaseResources() override;
            void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

            juce::AudioProcessorEditor* createEditor() override;
            bool hasEditor() const override { return true; }

            const juce::String getName() const override { return JucePlugin_Name; }
            bool acceptsMidi() const override { return true; }
            bool producesMidi() const override { return false; }
            double getTailLengthSeconds() const override { return 0.0; }

            int getNumPrograms() override { return 1; }
            int getCurrentProgram() override { return 0; }
            void setCurrentProgram(int) override {}
            const juce::String getProgramName(int) override { return {}; }
            void changeProgramName(int, const juce::String&) override {}

            void getStateInformation(juce::MemoryBlock& destData) override;
            void setStateInformation(const void* data, int sizeInBytes) override;

            juce::AudioProcessorValueTreeState apvts;

        private:
            juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();
            juce::Synthesiser synth;

            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Processor)
        };
        """
        try header.write(to: dir.appendingPathComponent("PluginProcessor.h"), atomically: true, encoding: .utf8)

        let impl = """
        #include "PluginProcessor.h"
        #include "PluginEditor.h"

        \(pluginName)Processor::\(pluginName)Processor()
            : AudioProcessor(BusesProperties()
                .withOutput("Output", \(busLayout), true)),
              apvts(*this, nullptr, "PARAMETERS", createParameterLayout())
        {
            synth.addSound(new \(pluginName)Sound());
            for (int i = 0; i < 8; ++i)
                synth.addVoice(new \(pluginName)Voice());
        }

        \(pluginName)Processor::~\(pluginName)Processor() {}

        juce::AudioProcessorValueTreeState::ParameterLayout \(pluginName)Processor::createParameterLayout()
        {
            // \(templateMarker): replace these starter instrument parameters with controls that match the requested playable instrument.
            std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;

            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"attack", 1}, "Attack",
                juce::NormalisableRange<float>(0.001f, 5.0f, 0.001f, 0.3f), 0.01f));
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"decay", 1}, "Decay",
                juce::NormalisableRange<float>(0.001f, 5.0f, 0.001f, 0.3f), 0.3f));
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"sustain", 1}, "Sustain", 0.0f, 1.0f, 0.7f));
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"release", 1}, "Release",
                juce::NormalisableRange<float>(0.001f, 5.0f, 0.001f, 0.3f), 0.5f));
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"gain", 1}, "Gain", 0.0f, 1.0f, 0.5f));

            return { params.begin(), params.end() };
        }

        void \(pluginName)Processor::prepareToPlay(double sampleRate, int)
        {
            synth.setCurrentPlaybackSampleRate(sampleRate);
        }

        void \(pluginName)Processor::releaseResources() {}

        void \(pluginName)Processor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midi)
        {
            // \(templateMarker): replace this starter voice engine with the requested instrument architecture and tone generation.
            juce::ScopedNoDenormals noDenormals;
            buffer.clear();

            float a = apvts.getRawParameterValue("attack")->load();
            float d = apvts.getRawParameterValue("decay")->load();
            float s = apvts.getRawParameterValue("sustain")->load();
            float r = apvts.getRawParameterValue("release")->load();
            float g = apvts.getRawParameterValue("gain")->load();

            for (int i = 0; i < synth.getNumVoices(); ++i)
            {
                if (auto* voice = dynamic_cast<\(pluginName)Voice*>(synth.getVoice(i)))
                {
                    voice->setADSRParams(a, d, s, r);
                    voice->updateGain(g);
                }
            }

            synth.renderNextBlock(buffer, midi, 0, buffer.getNumSamples());
        }

        juce::AudioProcessorEditor* \(pluginName)Processor::createEditor()
        {
            return new \(pluginName)Editor(*this);
        }

        void \(pluginName)Processor::getStateInformation(juce::MemoryBlock& destData)
        {
            auto state = apvts.copyState();
            std::unique_ptr<juce::XmlElement> xml(state.createXml());
            copyXmlToBinary(*xml, destData);
        }

        void \(pluginName)Processor::setStateInformation(const void* data, int sizeInBytes)
        {
            std::unique_ptr<juce::XmlElement> xml(getXmlFromBinary(data, sizeInBytes));
            if (xml != nullptr && xml->hasTagName(apvts.state.getType()))
                apvts.replaceState(juce::ValueTree::fromXml(*xml));
        }

        juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
        {
            return new \(pluginName)Processor();
        }
        """
        try impl.write(to: dir.appendingPathComponent("PluginProcessor.cpp"), atomically: true, encoding: .utf8)
    }

    // MARK: - Synth Editor (complete, working)

    private static func writeSynthEditor(to dir: URL, pluginName: String) throws {
        let header = """
        #pragma once
        #include "PluginProcessor.h"
        #include "FoundryLookAndFeel.h"

        class \(pluginName)Editor : public juce::AudioProcessorEditor
        {
        public:
            explicit \(pluginName)Editor(\(pluginName)Processor&);
            ~\(pluginName)Editor() override;

            void paint(juce::Graphics&) override;
            void resized() override;

        private:
            \(pluginName)Processor& processorRef;
            FoundryLookAndFeel lookAndFeel;

            juce::Slider attackSlider, decaySlider, sustainSlider, releaseSlider, gainSlider;
            juce::Label attackLabel, decayLabel, sustainLabel, releaseLabel, gainLabel;
            std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment>
                attackAttachment, decayAttachment, sustainAttachment, releaseAttachment, gainAttachment;

            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Editor)
        };
        """
        try header.write(to: dir.appendingPathComponent("PluginEditor.h"), atomically: true, encoding: .utf8)

        let impl = """
        #include "PluginEditor.h"

        static void setupKnob(\(pluginName)Editor* editor, \(pluginName)Processor& proc,
                               FoundryLookAndFeel& lf,
                               juce::Slider& slider, juce::Label& label,
                               const juce::String& name, const juce::String& paramId,
                               std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment>& attachment)
        {
            slider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
            slider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
            editor->addAndMakeVisible(slider);
            attachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                proc.apvts, paramId, slider);

            label.setText(name, juce::dontSendNotification);
            label.setJustificationType(juce::Justification::centred);
            label.setFont(juce::Font(juce::FontOptions(11.0f)));
            label.setColour(juce::Label::textColourId, lf.dimTextColour);
            editor->addAndMakeVisible(label);
        }

        \(pluginName)Editor::\(pluginName)Editor(\(pluginName)Processor& p)
            : AudioProcessorEditor(&p), processorRef(p)
        {
            setLookAndFeel(&lookAndFeel);
            setSize(600, 350);

            // \(templateMarker): redesign this starter panel so the UI reflects the generated instrument and its performance flow.
            setupKnob(this, processorRef, lookAndFeel, attackSlider, attackLabel, "ATK", "attack", attackAttachment);
            setupKnob(this, processorRef, lookAndFeel, decaySlider, decayLabel, "DEC", "decay", decayAttachment);
            setupKnob(this, processorRef, lookAndFeel, sustainSlider, sustainLabel, "SUS", "sustain", sustainAttachment);
            setupKnob(this, processorRef, lookAndFeel, releaseSlider, releaseLabel, "REL", "release", releaseAttachment);
            setupKnob(this, processorRef, lookAndFeel, gainSlider, gainLabel, "GAIN", "gain", gainAttachment);
        }

        \(pluginName)Editor::~\(pluginName)Editor()
        {
            setLookAndFeel(nullptr);
        }

        void \(pluginName)Editor::paint(juce::Graphics& g)
        {
            g.fillAll(lookAndFeel.backgroundColour);

            auto headerArea = getLocalBounds().removeFromTop(40);
            g.setColour(lookAndFeel.surfaceColour);
            g.fillRect(headerArea);

            g.setColour(lookAndFeel.dimTextColour);
            g.setFont(juce::Font(juce::FontOptions(
                juce::Font::getDefaultMonospacedFontName(), 13.0f, juce::Font::plain)));
            g.drawText("\(pluginName)", headerArea.reduced(12, 0), juce::Justification::centredLeft);

            // ADSR section label
            auto adsrLabel = getLocalBounds().reduced(20, 0);
            adsrLabel.removeFromTop(50);
            g.setFont(juce::Font(juce::FontOptions(
                juce::Font::getDefaultMonospacedFontName(), 10.0f, juce::Font::plain)));
            g.drawText("ENVELOPE", adsrLabel.removeFromTop(16), juce::Justification::centredLeft);
        }

        void \(pluginName)Editor::resized()
        {
            auto area = getLocalBounds().reduced(20);
            area.removeFromTop(70);

            // \(templateMarker): regroup, resize, and mix control types to fit the generated instrument.
            auto knobW = area.getWidth() / 5;
            auto row = area.removeFromTop(120);

            auto layoutKnob = [&](juce::Slider& slider, juce::Label& label)
            {
                auto col = row.removeFromLeft(knobW);
                slider.setBounds(col.removeFromTop(90));
                label.setBounds(col.removeFromTop(20));
            };

            layoutKnob(attackSlider, attackLabel);
            layoutKnob(decaySlider, decayLabel);
            layoutKnob(sustainSlider, sustainLabel);
            layoutKnob(releaseSlider, releaseLabel);
            layoutKnob(gainSlider, gainLabel);
        }
        """
        try impl.write(to: dir.appendingPathComponent("PluginEditor.cpp"), atomically: true, encoding: .utf8)
    }

    // MARK: - Utility Processor (complete, working)

    private static func writeUtilityProcessor(to dir: URL, pluginName: String, config: GenerationConfig) throws {
        let busLayout = config.channelLayout == .stereo
            ? "juce::AudioChannelSet::stereo()"
            : "juce::AudioChannelSet::mono()"

        let header = """
        #pragma once
        #include <JuceHeader.h>

        class \(pluginName)Processor : public juce::AudioProcessor
        {
        public:
            \(pluginName)Processor();
            ~\(pluginName)Processor() override;

            void prepareToPlay(double sampleRate, int samplesPerBlock) override;
            void releaseResources() override;
            void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

            juce::AudioProcessorEditor* createEditor() override;
            bool hasEditor() const override { return true; }

            const juce::String getName() const override { return JucePlugin_Name; }
            bool acceptsMidi() const override { return false; }
            bool producesMidi() const override { return false; }
            double getTailLengthSeconds() const override { return 0.0; }

            int getNumPrograms() override { return 1; }
            int getCurrentProgram() override { return 0; }
            void setCurrentProgram(int) override {}
            const juce::String getProgramName(int) override { return {}; }
            void changeProgramName(int, const juce::String&) override {}

            void getStateInformation(juce::MemoryBlock& destData) override;
            void setStateInformation(const void* data, int sizeInBytes) override;

            juce::AudioProcessorValueTreeState apvts;

        private:
            juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();

            juce::SmoothedValue<float> inputGainSmoothed;
            juce::SmoothedValue<float> outputGainSmoothed;
            juce::SmoothedValue<float> widthSmoothed;

            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Processor)
        };
        """
        try header.write(to: dir.appendingPathComponent("PluginProcessor.h"), atomically: true, encoding: .utf8)

        let impl = """
        #include "PluginProcessor.h"
        #include "PluginEditor.h"

        \(pluginName)Processor::\(pluginName)Processor()
            : AudioProcessor(BusesProperties()
                .withInput("Input", \(busLayout), true)
                .withOutput("Output", \(busLayout), true)),
              apvts(*this, nullptr, "PARAMETERS", createParameterLayout())
        {
        }

        \(pluginName)Processor::~\(pluginName)Processor() {}

        juce::AudioProcessorValueTreeState::ParameterLayout \(pluginName)Processor::createParameterLayout()
        {
            // \(templateMarker): replace these starter utility parameters with controls that match the requested tool.
            std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;

            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"inputGain", 1}, "Input",
                juce::NormalisableRange<float>(-24.0f, 24.0f, 0.1f), 0.0f));
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"width", 1}, "Width", 0.0f, 2.0f, 1.0f));
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"outputGain", 1}, "Output",
                juce::NormalisableRange<float>(-24.0f, 24.0f, 0.1f), 0.0f));

            return { params.begin(), params.end() };
        }

        void \(pluginName)Processor::prepareToPlay(double sampleRate, int)
        {
            inputGainSmoothed.reset(sampleRate, 0.02);
            outputGainSmoothed.reset(sampleRate, 0.02);
            widthSmoothed.reset(sampleRate, 0.02);
        }

        void \(pluginName)Processor::releaseResources() {}

        void \(pluginName)Processor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
        {
            // \(templateMarker): replace this safe passthrough utility with the requested analyzer, helper, or routing tool.
            juce::ScopedNoDenormals noDenormals;
            auto totalIn = getTotalNumInputChannels();
            auto totalOut = getTotalNumOutputChannels();
            for (auto i = totalIn; i < totalOut; ++i)
                buffer.clear(i, 0, buffer.getNumSamples());

            inputGainSmoothed.setTargetValue(apvts.getRawParameterValue("inputGain")->load());
            outputGainSmoothed.setTargetValue(apvts.getRawParameterValue("outputGain")->load());
            widthSmoothed.setTargetValue(apvts.getRawParameterValue("width")->load());

            const bool isStereo = buffer.getNumChannels() >= 2;

            for (int sample = 0; sample < buffer.getNumSamples(); ++sample)
            {
                const float inputGain = juce::Decibels::decibelsToGain(inputGainSmoothed.getNextValue());
                const float outputGain = juce::Decibels::decibelsToGain(outputGainSmoothed.getNextValue());
                const float width = widthSmoothed.getNextValue();

                if (isStereo)
                {
                    auto left = buffer.getSample(0, sample) * inputGain;
                    auto right = buffer.getSample(1, sample) * inputGain;
                    const float mid = 0.5f * (left + right);
                    const float side = 0.5f * (left - right) * width;
                    buffer.setSample(0, sample, (mid + side) * outputGain);
                    buffer.setSample(1, sample, (mid - side) * outputGain);
                }
                else
                {
                    buffer.setSample(0, sample, buffer.getSample(0, sample) * inputGain * outputGain);
                }
            }

            for (int channel = 2; channel < buffer.getNumChannels(); ++channel)
            {
                buffer.applyGain(channel, 0, buffer.getNumSamples(),
                                 juce::Decibels::decibelsToGain(apvts.getRawParameterValue("outputGain")->load()));
            }
        }

        juce::AudioProcessorEditor* \(pluginName)Processor::createEditor()
        {
            return new \(pluginName)Editor(*this);
        }

        void \(pluginName)Processor::getStateInformation(juce::MemoryBlock& destData)
        {
            auto state = apvts.copyState();
            std::unique_ptr<juce::XmlElement> xml(state.createXml());
            copyXmlToBinary(*xml, destData);
        }

        void \(pluginName)Processor::setStateInformation(const void* data, int sizeInBytes)
        {
            std::unique_ptr<juce::XmlElement> xml(getXmlFromBinary(data, sizeInBytes));
            if (xml != nullptr && xml->hasTagName(apvts.state.getType()))
                apvts.replaceState(juce::ValueTree::fromXml(*xml));
        }

        juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
        {
            return new \(pluginName)Processor();
        }
        """
        try impl.write(to: dir.appendingPathComponent("PluginProcessor.cpp"), atomically: true, encoding: .utf8)
    }

    private static func writeUtilityEditor(to dir: URL, pluginName: String) throws {
        let header = """
        #pragma once
        #include "PluginProcessor.h"
        #include "FoundryLookAndFeel.h"

        class \(pluginName)Editor : public juce::AudioProcessorEditor
        {
        public:
            explicit \(pluginName)Editor(\(pluginName)Processor&);
            ~\(pluginName)Editor() override;

            void paint(juce::Graphics&) override;
            void resized() override;

        private:
            \(pluginName)Processor& processorRef;
            FoundryLookAndFeel lookAndFeel;

            juce::Slider inputSlider;
            juce::Label inputLabel;
            std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> inputAttachment;

            juce::Slider widthSlider;
            juce::Label widthLabel;
            std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> widthAttachment;

            juce::Slider outputSlider;
            juce::Label outputLabel;
            std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> outputAttachment;

            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Editor)
        };
        """
        try header.write(to: dir.appendingPathComponent("PluginEditor.h"), atomically: true, encoding: .utf8)

        let impl = """
        #include "PluginEditor.h"

        static void setupStageSlider(\(pluginName)Editor* editor, \(pluginName)Processor& proc,
                                     FoundryLookAndFeel& lf, juce::Slider& slider, juce::Label& label,
                                     const juce::String& name, const juce::String& paramId,
                                     std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment>& attachment)
        {
            slider.setSliderStyle(juce::Slider::LinearHorizontal);
            slider.setTextBoxStyle(juce::Slider::TextBoxRight, false, 64, 18);
            editor->addAndMakeVisible(slider);
            attachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                proc.apvts, paramId, slider);

            label.setText(name, juce::dontSendNotification);
            label.setJustificationType(juce::Justification::centredLeft);
            label.setFont(juce::Font(juce::FontOptions(11.0f)));
            label.setColour(juce::Label::textColourId, lf.dimTextColour);
            editor->addAndMakeVisible(label);
        }

        \(pluginName)Editor::\(pluginName)Editor(\(pluginName)Processor& p)
            : AudioProcessorEditor(&p), processorRef(p)
        {
            setLookAndFeel(&lookAndFeel);
            setSize(520, 260);

            // \(templateMarker): redesign this starter utility layout to match the requested workflow and visual hierarchy.
            setupStageSlider(this, processorRef, lookAndFeel, inputSlider, inputLabel, "INPUT", "inputGain", inputAttachment);
            setupStageSlider(this, processorRef, lookAndFeel, widthSlider, widthLabel, "WIDTH", "width", widthAttachment);
            setupStageSlider(this, processorRef, lookAndFeel, outputSlider, outputLabel, "OUTPUT", "outputGain", outputAttachment);
        }

        \(pluginName)Editor::~\(pluginName)Editor()
        {
            setLookAndFeel(nullptr);
        }

        void \(pluginName)Editor::paint(juce::Graphics& g)
        {
            g.fillAll(lookAndFeel.backgroundColour);

            auto bounds = getLocalBounds().reduced(20);
            auto header = bounds.removeFromTop(56);
            g.setColour(lookAndFeel.surfaceColour);
            g.fillRoundedRectangle(header.toFloat(), 8.0f);

            g.setColour(lookAndFeel.textColour);
            g.setFont(juce::Font(juce::FontOptions(
                juce::Font::getDefaultMonospacedFontName(), 14.0f, juce::Font::plain)));
            g.drawText("\(pluginName)", header.removeFromTop(24).reduced(12, 0), juce::Justification::centredLeft);

            g.setColour(lookAndFeel.dimTextColour);
            g.setFont(juce::Font(juce::FontOptions(
                juce::Font::getDefaultMonospacedFontName(), 10.0f, juce::Font::plain)));
            g.drawText("UTILITY STAGE", header.reduced(12, 0), juce::Justification::centredLeft);
        }

        void \(pluginName)Editor::resized()
        {
            auto area = getLocalBounds().reduced(20);
            area.removeFromTop(72);

            auto layoutRow = [&](juce::Label& label, juce::Slider& slider)
            {
                auto row = area.removeFromTop(42);
                label.setBounds(row.removeFromLeft(80));
                slider.setBounds(row);
                area.removeFromTop(12);
            };

            // \(templateMarker): rebuild the control grouping, spacing, and component mix for the generated plugin.
            layoutRow(inputLabel, inputSlider);
            layoutRow(widthLabel, widthSlider);
            layoutRow(outputLabel, outputSlider);
        }
        """
        try impl.write(to: dir.appendingPathComponent("PluginEditor.cpp"), atomically: true, encoding: .utf8)
    }

    // MARK: - LookAndFeel

    private static func writeLookAndFeel(to dir: URL) throws {
        let content = """
        #pragma once
        #include <JuceHeader.h>

        class FoundryLookAndFeel : public juce::LookAndFeel_V4
        {
        public:
            juce::Colour backgroundColour  { 0xff0a0a0a };
            juce::Colour surfaceColour     { 0xff1a1a1a };
            juce::Colour borderColour      { 0xff2a2a2a };
            juce::Colour textColour        { 0xffd0d0d0 };
            juce::Colour dimTextColour     { 0xff606060 };
            juce::Colour accentColour      { 0xffc0c0c0 };
            juce::Colour knobTrackColour   { 0xff2a2a2a };

            FoundryLookAndFeel()
            {
                applyColours();
            }

            void applyColours()
            {
                setColour(juce::ResizableWindow::backgroundColourId, backgroundColour);
                setColour(juce::Slider::rotarySliderFillColourId, accentColour);
                setColour(juce::Slider::rotarySliderOutlineColourId, knobTrackColour);
                setColour(juce::Slider::thumbColourId, accentColour);
                setColour(juce::Slider::trackColourId, knobTrackColour);
                setColour(juce::Slider::backgroundColourId, knobTrackColour);
                setColour(juce::Slider::textBoxTextColourId, dimTextColour);
                setColour(juce::Slider::textBoxOutlineColourId, juce::Colour(0x00000000));
                setColour(juce::Label::textColourId, textColour);
                setColour(juce::ComboBox::backgroundColourId, backgroundColour);
                setColour(juce::ComboBox::outlineColourId, borderColour);
                setColour(juce::ComboBox::textColourId, textColour);
                setColour(juce::TextButton::buttonColourId, backgroundColour);
                setColour(juce::TextButton::textColourOffId, textColour);
                setColour(juce::ToggleButton::textColourId, textColour);
                setColour(juce::ToggleButton::tickColourId, accentColour);
            }

            void drawRotarySlider(juce::Graphics& g, int x, int y, int width, int height,
                                  float sliderPos, float rotaryStartAngle, float rotaryEndAngle,
                                  juce::Slider&) override
            {
                auto bounds = juce::Rectangle<int>(x, y, width, height).toFloat().reduced(2.0f);
                auto radius = juce::jmin(bounds.getWidth(), bounds.getHeight()) / 2.0f;
                auto cx = bounds.getCentreX();
                auto cy = bounds.getCentreY();
                auto angle = rotaryStartAngle + sliderPos * (rotaryEndAngle - rotaryStartAngle);

                g.setColour(knobTrackColour);
                g.drawEllipse(cx - radius, cy - radius, radius * 2.0f, radius * 2.0f, 1.0f);

                juce::Path arc;
                arc.addCentredArc(cx, cy, radius, radius, 0.0f, rotaryStartAngle, angle, true);
                g.setColour(accentColour);
                g.strokePath(arc, juce::PathStrokeType(1.5f, juce::PathStrokeType::curved,
                                                         juce::PathStrokeType::rounded));

                juce::Path indicator;
                indicator.startNewSubPath(cx, cy);
                indicator.lineTo(cx + (radius - 4.0f) * std::sin(angle),
                                 cy - (radius - 4.0f) * std::cos(angle));
                g.strokePath(indicator, juce::PathStrokeType(1.5f));
            }

            void drawLinearSlider(juce::Graphics& g, int x, int y, int width, int height,
                                  float sliderPos, float minPos, float maxPos,
                                  juce::Slider::SliderStyle style, juce::Slider& slider) override
            {
                if (style == juce::Slider::LinearHorizontal)
                {
                    auto trackY = (float)y + (float)height * 0.5f;
                    g.setColour(knobTrackColour);
                    g.fillRoundedRectangle((float)x, trackY - 1.0f, (float)width, 2.0f, 1.0f);
                    g.setColour(accentColour);
                    g.fillRoundedRectangle((float)x, trackY - 1.0f, sliderPos - (float)x, 2.0f, 1.0f);
                }
                else
                {
                    LookAndFeel_V4::drawLinearSlider(g, x, y, width, height, sliderPos, minPos, maxPos, style, slider);
                }
            }

            juce::Font getLabelFont(juce::Label&) override
            {
                return juce::Font(juce::FontOptions(juce::Font::getDefaultMonospacedFontName(), 11.0f, juce::Font::plain));
            }

            void drawButtonBackground(juce::Graphics& g, juce::Button& button,
                                       const juce::Colour&, bool isHighlighted, bool isDown) override
            {
                auto bounds = button.getLocalBounds().toFloat().reduced(0.5f);
                g.setColour(isDown ? borderColour.brighter(0.2f)
                          : isHighlighted ? borderColour.brighter(0.1f)
                          : borderColour);
                g.drawRoundedRectangle(bounds, 2.0f, 1.0f);
            }
        };
        """
        try content.write(to: dir.appendingPathComponent("FoundryLookAndFeel.h"), atomically: true, encoding: .utf8)
    }

    // MARK: - CLAUDE.md

    private static func writeClaudeMD(
        to dir: URL,
        pluginName: String,
        pluginType: PluginType,
        interfaceStyle: InterfaceStyle,
        config: GenerationConfig
    ) throws {
        let pluginRole: String = switch pluginType {
        case .instrument: "playable instrument"
        case .effect: "audio effect"
        case .utility: "utility or analysis tool"
        }
        let channelDesc = config.channelLayout == .stereo ? "stereo" : "mono"
        let presetCount = config.presetCount.rawValue
        let interfaceDirection: String = switch interfaceStyle {
        case .focused: "Keep the UI tight and immediate. Show only the essential controls at first glance."
        case .balanced: "Use clear grouped sections with a strong primary area and tidy secondary controls."
        case .exploratory: "Allow a denser interface with richer modulation, modes, and deeper parameter access."
        }

        let presetSection: String
        if presetCount > 0 {
            presetSection = """

            ## Presets — MANDATORY (\(presetCount) presets required)

            You MUST implement exactly **\(presetCount) presets** using JUCE's program system.
            Each preset must set ALL parameters to musically useful, distinct values.

            ### In PluginProcessor.h:
            - Add a struct or array to hold preset data
            - Store the current preset index

            ### In PluginProcessor.cpp:
            - `getNumPrograms()` → return \(presetCount)
            - `getCurrentProgram()` → return the stored index
            - `setCurrentProgram(int index)` → load parameter values from preset data into apvts
            - `getProgramName(int index)` → return the preset name (short, descriptive, no emojis)
            - Define \(presetCount) presets with creative names that fit the plugin character
            - Each preset MUST set every parameter to a different, musically interesting value

            ### Preset loading pattern:
            ```cpp
            struct PresetData {
                const char* name;
                std::vector<std::pair<const char*, float>> values;
            };

            // In setCurrentProgram():
            void \(pluginName)Processor::setCurrentProgram(int index)
            {
                if (index < 0 || index >= getNumPrograms()) return;
                currentPreset = index;
                for (auto& [paramId, value] : presets[index].values)
                {
                    if (auto* param = apvts.getParameter(paramId))
                        param->setValueNotifyingHost(param->convertTo0to1(value));
                }
            }
            ```

            ### In PluginEditor — add a preset ComboBox:
            ```cpp
            // Header:
            juce::ComboBox presetBox;

            // Constructor:
            for (int i = 0; i < processorRef.getNumPrograms(); ++i)
                presetBox.addItem(processorRef.getProgramName(i), i + 1);
            presetBox.setSelectedId(processorRef.getCurrentProgram() + 1, juce::dontSendNotification);
            presetBox.onChange = [this] {
                processorRef.setCurrentProgram(presetBox.getSelectedId() - 1);
            };
            addAndMakeVisible(presetBox);

            // In resized(): place presetBox in the header area, right-aligned
            ```
            """
        } else {
            presetSection = ""
        }

        let content = """
        # \(pluginName) — JUCE Plugin Project

        You are modifying a **working \(pluginRole) plugin** to match this description:
        **\(config.prompt)**

        Channel layout: **\(channelDesc)**
        Interface direction: **\(interfaceStyle.rawValue)**

        ## IMPORTANT: The plugin already compiles and works.
        Your job is to MODIFY the existing code, not start from scratch.
        Read all 4 source files first, then make targeted edits.

        ## Files you can edit
        - `Source/PluginProcessor.h` — parameters + DSP members
        - `Source/PluginProcessor.cpp` — createParameterLayout(), prepareToPlay(), processBlock()
        - `Source/PluginEditor.h` — slider/label/attachment members
        - `Source/PluginEditor.cpp` — UI controls, layout, paint
        - `Source/FoundryLookAndFeel.h` — customise colours and knob style

        **DO NOT** modify `CMakeLists.txt`. **DO NOT** create new files.
        **DO NOT** rename classes — keep `\(pluginName)Processor` and `\(pluginName)Editor`.
        **REMOVE every line containing `\(templateMarker)`** before you finish. If any placeholder markers remain, the generation is considered a failure.

        ## What to modify

        1. **Add parameters** in `createParameterLayout()` for the specific plugin described
        2. **Implement DSP** in processBlock() — replace the placeholder with real audio processing
        3. **Design the editor intentionally** — group controls by role, create 2-4 sections, and choose the right control type for each parameter
        4. **Customise colours** — pick an accent colour that fits the plugin character
        \(presetCount > 0 ? "5. **Implement \(presetCount) presets** — see Presets section below" : "")

        ## DSP rules
        - Use `juce::SmoothedValue<float>` for parameters read in processBlock()
        - Effects: keep dry/wet mix when musically relevant, copy the dry buffer before destructive processing
        - Utilities: stay safe, transparent, and immediately useful on first load
        - Use `juce::dsp::` classes where helpful: IIR::Filter, DelayLine, Reverb, Chorus, WaveShaper, Oscillator
        - Initialize DSP in prepareToPlay() with correct sample rate
        - Feedback must be < 1.0. Sensible defaults that sound good immediately.
        \(pluginType == .instrument ? """
        - Instruments: modify \(pluginName)Voice::renderNextBlock() for your oscillator or tone generator
        - Add filters, effects, modulators, or performance behavior as needed
        - 8 voices for polyphony are already set up as a safe default
        """ : "")
        \(pluginType == .utility ? """
        - Utilities should expose clear metering, routing, gain staging, stereo, or analysis behavior when relevant
        - Avoid fake “creative” DSP if the requested plugin is meant to be a helper or analyzer
        """ : "")

        ## UI rules
        - Every parameter MUST have an appropriate visible control and attachment
        - Use a mix of rotary sliders, linear sliders, ComboBox, and buttons when it improves usability
        - Group controls into named sections instead of one flat row whenever there are more than 4 controls
        - Make the first screenful feel like a product, not a generic debug panel
        - Dark background (0xff080808 to 0xff181818), one muted accent colour
        - No emojis, no "AI" branding, no purple, no bright colours
        - Use `addAndMakeVisible()` for every control
        - Set `setSize(width, height)` to fit your layout
        - Use `juce::Font(juce::FontOptions(float))` not `juce::Font(float)`
        - \(interfaceDirection)

        ## Control pattern examples
        ```cpp
        // In header private section:
        juce::Slider mySlider;
        juce::Label myLabel;
        std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> myAttachment;

        // In constructor:
        mySlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
        mySlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
        addAndMakeVisible(mySlider);
        myAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
            processorRef.apvts, "paramId", mySlider);
        myLabel.setText("LABEL", juce::dontSendNotification);
        myLabel.setJustificationType(juce::Justification::centred);
        myLabel.setFont(juce::Font(juce::FontOptions(11.0f)));
        myLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
        addAndMakeVisible(myLabel);

        // In resized(): position with setBounds()
        ```
        You can also use `juce::ComboBox` with `ComboBoxAttachment`, or `juce::ToggleButton` with `ButtonAttachment`, when those fit the parameter better.
        \(presetSection)
        """
        try content.write(to: dir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    }
}
