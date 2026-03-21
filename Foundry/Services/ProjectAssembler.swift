import Foundation

enum ProjectAssembler {

    struct AssembledProject {
        let directory: URL
        let pluginName: String
        let pluginType: PluginType
        let interfaceStyle: InterfaceStyle
    }

    enum InterfaceStyle: String {
        case focused = "Focused"
        case balanced = "Balanced"
        case exploratory = "Exploratory"
    }

    // MARK: - Assemble

    static func assemble(config: GenerationConfig) throws -> AssembledProject {
        let fm = FileManager.default

        let pluginName = generatePluginName(from: config.prompt)
        let pluginType = inferPluginType(from: config.prompt)
        let interfaceStyle = inferInterfaceStyle(from: config.prompt, pluginType: pluginType)

        let uuid = UUID().uuidString.prefix(8).lowercased()
        let projectDir = URL(fileURLWithPath: "/tmp/foundry-build-\(uuid)")
        let sourceDir = projectDir.appendingPathComponent("Source")
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        try writeCMakeLists(to: projectDir, pluginName: pluginName, pluginType: pluginType, config: config)
        try writeStubFiles(to: sourceDir, pluginName: pluginName, pluginType: pluginType, config: config)
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
            "multi-stage", "complex", "dense", "experimental", "modulation",
            "synth", "synthesizer", "analog", "subtractive", "fm", "wavetable",
            "polysynth", "poly synth", "jupiter", "juno", "moog", "prophet",
            "supersaw", "unison"
        ]
        if exploratoryKeywords.contains(where: lower.contains) {
            return .exploratory
        }

        switch pluginType {
        case .utility:
            return .focused
        case .instrument:
            return .exploratory
        case .effect:
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

    // MARK: - Stub files (minimal compilable skeletons)

    private static func writeStubFiles(
        to dir: URL,
        pluginName: String,
        pluginType: PluginType,
        config: GenerationConfig
    ) throws {
        let busLayout = config.channelLayout == .stereo
            ? "juce::AudioChannelSet::stereo()"
            : "juce::AudioChannelSet::mono()"
        let isInstrument = pluginType == .instrument

        // ── PluginProcessor.h ────────────────────────────────────────

        var processorH = """
        #pragma once
        #include <JuceHeader.h>

        """

        if isInstrument {
            processorH += """
            class \(pluginName)Processor; // forward declaration

            struct \(pluginName)Sound : public juce::SynthesiserSound
            {
                bool appliesToNote(int) override { return true; }
                bool appliesToChannel(int) override { return true; }
            };

            class \(pluginName)Voice : public juce::SynthesiserVoice
            {
            public:
                void setProcessor(\(pluginName)Processor* p) { processor = p; }

                bool canPlaySound(juce::SynthesiserSound* sound) override
                {
                    return dynamic_cast<\(pluginName)Sound*>(sound) != nullptr;
                }
                void startNote(int midiNote, float velocity, juce::SynthesiserSound*, int) override
                {
                    frequency = juce::MidiMessage::getMidiNoteInHertz(midiNote);
                    level = velocity;
                    phase = 0.0;
                    adsr.setSampleRate(getSampleRate());
                    adsr.setParameters({ 0.01f, 0.1f, 0.8f, 0.3f });
                    adsr.noteOn();
                }
                void stopNote(float, bool allowTailOff) override
                {
                    adsr.noteOff();
                    if (!allowTailOff) clearCurrentNote();
                }
                void pitchWheelMoved(int) override {}
                void controllerMoved(int, int) override {}
                void renderNextBlock(juce::AudioBuffer<float>& buffer, int startSample, int numSamples) override
                {
                    if (!isVoiceActive()) return;
                    for (int s = startSample; s < startSample + numSamples; ++s)
                    {
                        float sample = static_cast<float>(std::sin(phase * juce::MathConstants<double>::twoPi));
                        phase += frequency / getSampleRate();
                        if (phase >= 1.0) phase -= 1.0;
                        float out = sample * adsr.getNextSample() * level;
                        for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                            buffer.addSample(ch, s, out);
                    }
                    if (!adsr.isActive()) clearCurrentNote();
                }

                void prepareToPlay(double sampleRate, int /*samplesPerBlock*/)
                {
                    adsr.setSampleRate(sampleRate);
                }

            private:
                \(pluginName)Processor* processor = nullptr;
                double frequency = 440.0;
                double phase = 0.0;
                float level = 0.0f;
                juce::ADSR adsr;
            };

            """
        }

        // Processor private members depend on plugin type
        let processorMembers: String
        switch pluginType {
        case .effect:
            processorMembers = """
                juce::SmoothedValue<float> gainSmoothed;
                juce::SmoothedValue<float> mixSmoothed;
            """
        case .instrument:
            processorMembers = """
                juce::Synthesiser synth;
                juce::SmoothedValue<float> levelSmoothed;
            """
        case .utility:
            processorMembers = """
                juce::SmoothedValue<float> gainSmoothed;
            """
        }

        processorH += """
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
            bool acceptsMidi() const override { return \(isInstrument ? "true" : "false"); }
            bool producesMidi() const override { return false; }
            double getTailLengthSeconds() const override { return 0.0; }

            int getNumPrograms() override;
            int getCurrentProgram() override;
            void setCurrentProgram(int index) override;
            const juce::String getProgramName(int index) override;
            void changeProgramName(int, const juce::String&) override {}

            void getStateInformation(juce::MemoryBlock& destData) override;
            void setStateInformation(const void* data, int sizeInBytes) override;

            juce::AudioProcessorValueTreeState apvts;

        private:
            juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();
        \(processorMembers)
            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Processor)
        };
        """
        try processorH.write(to: dir.appendingPathComponent("PluginProcessor.h"), atomically: true, encoding: .utf8)

        // ── PluginProcessor.cpp ──────────────────────────────────────

        let createParameterLayoutBody: String
        let prepareToPlayBody: String
        let processBlockBody: String
        var synthInit = ""

        switch pluginType {
        case .effect:
            createParameterLayoutBody = """
                std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;
                params.push_back(std::make_unique<juce::AudioParameterFloat>(
                    juce::ParameterID{"gain", 1}, "Gain",
                    juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.5f));
                params.push_back(std::make_unique<juce::AudioParameterFloat>(
                    juce::ParameterID{"mix", 1}, "Mix",
                    juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 1.0f));
                return { params.begin(), params.end() };
            """
            prepareToPlayBody = """
                gainSmoothed.reset(sampleRate, 0.02);
                mixSmoothed.reset(sampleRate, 0.02);
            """
            processBlockBody = """
                juce::ignoreUnused(midiMessages);
                juce::ScopedNoDenormals noDenormals;
                for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
                    buffer.clear(i, 0, buffer.getNumSamples());

                gainSmoothed.setTargetValue(apvts.getRawParameterValue("gain")->load());
                mixSmoothed.setTargetValue(apvts.getRawParameterValue("mix")->load());

                juce::AudioBuffer<float> dryBuffer;
                dryBuffer.makeCopyOf(buffer);

                for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                {
                    auto* data = buffer.getWritePointer(ch);
                    for (int s = 0; s < buffer.getNumSamples(); ++s)
                    {
                        const float g = gainSmoothed.getNextValue() * 2.0f;
                        data[s] = std::tanh(data[s] * g);
                    }
                }

                for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                {
                    auto* wet = buffer.getWritePointer(ch);
                    const auto* dry = dryBuffer.getReadPointer(ch);
                    for (int s = 0; s < buffer.getNumSamples(); ++s)
                    {
                        const float m = mixSmoothed.getNextValue();
                        wet[s] = dry[s] + m * (wet[s] - dry[s]);
                    }
                }
            """

        case .instrument:
            synthInit = """

                synth.addSound(new \(pluginName)Sound());
                for (int i = 0; i < 8; ++i)
                    synth.addVoice(new \(pluginName)Voice());
            """
            createParameterLayoutBody = """
                std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;
                params.push_back(std::make_unique<juce::AudioParameterFloat>(
                    juce::ParameterID{"level", 1}, "Level",
                    juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.8f));
                params.push_back(std::make_unique<juce::AudioParameterFloat>(
                    juce::ParameterID{"attack", 1}, "Attack",
                    juce::NormalisableRange<float>(0.001f, 2.0f, 0.001f, 0.4f), 0.01f));
                params.push_back(std::make_unique<juce::AudioParameterFloat>(
                    juce::ParameterID{"release", 1}, "Release",
                    juce::NormalisableRange<float>(0.01f, 5.0f, 0.01f, 0.4f), 0.3f));
                return { params.begin(), params.end() };
            """
            prepareToPlayBody = """
                synth.setCurrentPlaybackSampleRate(sampleRate);
                levelSmoothed.reset(sampleRate, 0.02);
            """
            processBlockBody = """
                juce::ScopedNoDenormals noDenormals;
                buffer.clear();
                levelSmoothed.setTargetValue(apvts.getRawParameterValue("level")->load());
                synth.renderNextBlock(buffer, midiMessages, 0, buffer.getNumSamples());
                for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                {
                    auto* data = buffer.getWritePointer(ch);
                    for (int s = 0; s < buffer.getNumSamples(); ++s)
                        data[s] *= levelSmoothed.getNextValue();
                }
            """

        case .utility:
            createParameterLayoutBody = """
                std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;
                params.push_back(std::make_unique<juce::AudioParameterFloat>(
                    juce::ParameterID{"gain", 1}, "Gain",
                    juce::NormalisableRange<float>(-60.0f, 12.0f, 0.1f), 0.0f));
                params.push_back(std::make_unique<juce::AudioParameterBool>(
                    juce::ParameterID{"invert", 1}, "Phase Invert", false));
                return { params.begin(), params.end() };
            """
            prepareToPlayBody = """
                gainSmoothed.reset(sampleRate, 0.02);
            """
            processBlockBody = """
                juce::ignoreUnused(midiMessages);
                juce::ScopedNoDenormals noDenormals;
                for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
                    buffer.clear(i, 0, buffer.getNumSamples());

                gainSmoothed.setTargetValue(
                    juce::Decibels::decibelsToGain(apvts.getRawParameterValue("gain")->load()));
                const bool invert = apvts.getRawParameterValue("invert")->load() > 0.5f;
                const float phase = invert ? -1.0f : 1.0f;

                for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                {
                    auto* data = buffer.getWritePointer(ch);
                    for (int s = 0; s < buffer.getNumSamples(); ++s)
                        data[s] *= gainSmoothed.getNextValue() * phase;
                }
            """
        }

        let processorCPP = """
        #include "PluginProcessor.h"
        #include "PluginEditor.h"

        \(pluginName)Processor::\(pluginName)Processor()
            : AudioProcessor(BusesProperties()
                \(isInstrument ? ".withOutput(\"Output\", \(busLayout), true)" : ".withInput(\"Input\", \(busLayout), true)\n            .withOutput(\"Output\", \(busLayout), true)")),
              apvts(*this, nullptr, "PARAMETERS", createParameterLayout())
        {\(synthInit)
        }

        \(pluginName)Processor::~\(pluginName)Processor() {}

        juce::AudioProcessorValueTreeState::ParameterLayout \(pluginName)Processor::createParameterLayout()
        {
        \(createParameterLayoutBody)
        }

        void \(pluginName)Processor::prepareToPlay(double sampleRate, int samplesPerBlock)
        {
            juce::ignoreUnused(samplesPerBlock);
        \(prepareToPlayBody)
        }

        void \(pluginName)Processor::releaseResources() {}

        void \(pluginName)Processor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
        {
        \(processBlockBody)
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
            if (xml && xml->hasTagName(apvts.state.getType()))
                apvts.replaceState(juce::ValueTree::fromXml(*xml));
        }

        juce::AudioProcessorEditor* \(pluginName)Processor::createEditor()
        {
            return new \(pluginName)Editor(*this);
        }

        int \(pluginName)Processor::getNumPrograms() { return 1; }
        int \(pluginName)Processor::getCurrentProgram() { return 0; }
        void \(pluginName)Processor::setCurrentProgram(int) {}
        const juce::String \(pluginName)Processor::getProgramName(int) { return {}; }

        juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
        {
            return new \(pluginName)Processor();
        }
        """
        try processorCPP.write(to: dir.appendingPathComponent("PluginProcessor.cpp"), atomically: true, encoding: .utf8)

        // ── PluginEditor.h ───────────────────────────────────────────

        // Build editor members matching the starter parameters
        let editorMembers: String
        switch pluginType {
        case .effect:
            editorMembers = """
                juce::Slider gainSlider;
                juce::Label gainLabel;
                std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> gainAttachment;

                juce::Slider mixSlider;
                juce::Label mixLabel;
                std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> mixAttachment;
            """
        case .instrument:
            editorMembers = """
                juce::Slider levelSlider;
                juce::Label levelLabel;
                std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> levelAttachment;

                juce::Slider attackSlider;
                juce::Label attackLabel;
                std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> attackAttachment;

                juce::Slider releaseSlider;
                juce::Label releaseLabel;
                std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> releaseAttachment;
            """
        case .utility:
            editorMembers = """
                juce::Slider gainSlider;
                juce::Label gainLabel;
                std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> gainAttachment;

                juce::ToggleButton invertButton { "Phase Invert" };
                std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment> invertAttachment;
            """
        }

        let editorH = """
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

        \(editorMembers)
            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Editor)
        };
        """
        try editorH.write(to: dir.appendingPathComponent("PluginEditor.h"), atomically: true, encoding: .utf8)

        // ── PluginEditor.cpp ─────────────────────────────────────────

        let editorConstructorBody: String
        let editorResizedBody: String

        switch pluginType {
        case .effect:
            editorConstructorBody = """
                gainSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
                gainSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
                addAndMakeVisible(gainSlider);
                gainAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                    processorRef.apvts, "gain", gainSlider);
                gainLabel.setText("GAIN", juce::dontSendNotification);
                gainLabel.setJustificationType(juce::Justification::centred);
                gainLabel.setFont(juce::Font(juce::FontOptions(10.0f)));
                gainLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
                addAndMakeVisible(gainLabel);

                mixSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
                mixSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
                addAndMakeVisible(mixSlider);
                mixAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                    processorRef.apvts, "mix", mixSlider);
                mixLabel.setText("MIX", juce::dontSendNotification);
                mixLabel.setJustificationType(juce::Justification::centred);
                mixLabel.setFont(juce::Font(juce::FontOptions(10.0f)));
                mixLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
                addAndMakeVisible(mixLabel);
            """
            editorResizedBody = """
                auto area = getLocalBounds().reduced(20);
                area.removeFromTop(40);
                auto left = area.removeFromLeft(area.getWidth() / 2);
                gainSlider.setBounds(left.removeFromTop(left.getHeight() - 20).reduced(10));
                gainLabel.setBounds(left);
                mixSlider.setBounds(area.removeFromTop(area.getHeight() - 20).reduced(10));
                mixLabel.setBounds(area);
            """

        case .instrument:
            editorConstructorBody = """
                levelSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
                levelSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
                addAndMakeVisible(levelSlider);
                levelAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                    processorRef.apvts, "level", levelSlider);
                levelLabel.setText("LEVEL", juce::dontSendNotification);
                levelLabel.setJustificationType(juce::Justification::centred);
                levelLabel.setFont(juce::Font(juce::FontOptions(10.0f)));
                levelLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
                addAndMakeVisible(levelLabel);

                attackSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
                attackSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
                addAndMakeVisible(attackSlider);
                attackAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                    processorRef.apvts, "attack", attackSlider);
                attackLabel.setText("ATTACK", juce::dontSendNotification);
                attackLabel.setJustificationType(juce::Justification::centred);
                attackLabel.setFont(juce::Font(juce::FontOptions(10.0f)));
                attackLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
                addAndMakeVisible(attackLabel);

                releaseSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
                releaseSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
                addAndMakeVisible(releaseSlider);
                releaseAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                    processorRef.apvts, "release", releaseSlider);
                releaseLabel.setText("RELEASE", juce::dontSendNotification);
                releaseLabel.setJustificationType(juce::Justification::centred);
                releaseLabel.setFont(juce::Font(juce::FontOptions(10.0f)));
                releaseLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
                addAndMakeVisible(releaseLabel);
            """
            editorResizedBody = """
                auto area = getLocalBounds().reduced(20);
                area.removeFromTop(40);
                int sectionW = area.getWidth() / 3;
                auto s1 = area.removeFromLeft(sectionW);
                auto s2 = area.removeFromLeft(sectionW);
                auto s3 = area;
                levelSlider.setBounds(s1.removeFromTop(s1.getHeight() - 20).reduced(10));
                levelLabel.setBounds(s1);
                attackSlider.setBounds(s2.removeFromTop(s2.getHeight() - 20).reduced(10));
                attackLabel.setBounds(s2);
                releaseSlider.setBounds(s3.removeFromTop(s3.getHeight() - 20).reduced(10));
                releaseLabel.setBounds(s3);
            """

        case .utility:
            editorConstructorBody = """
                gainSlider.setSliderStyle(juce::Slider::LinearHorizontal);
                gainSlider.setTextBoxStyle(juce::Slider::TextBoxRight, false, 60, 20);
                addAndMakeVisible(gainSlider);
                gainAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
                    processorRef.apvts, "gain", gainSlider);
                gainLabel.setText("GAIN (dB)", juce::dontSendNotification);
                gainLabel.setFont(juce::Font(juce::FontOptions(10.0f)));
                gainLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
                addAndMakeVisible(gainLabel);

                addAndMakeVisible(invertButton);
                invertAttachment = std::make_unique<juce::AudioProcessorValueTreeState::ButtonAttachment>(
                    processorRef.apvts, "invert", invertButton);
            """
            editorResizedBody = """
                auto area = getLocalBounds().reduced(20);
                area.removeFromTop(40);
                gainLabel.setBounds(area.removeFromTop(20));
                gainSlider.setBounds(area.removeFromTop(40));
                area.removeFromTop(20);
                invertButton.setBounds(area.removeFromTop(30).removeFromLeft(160));
            """
        }

        let editorCPP = """
        #include "PluginEditor.h"

        \(pluginName)Editor::\(pluginName)Editor(\(pluginName)Processor& p)
            : AudioProcessorEditor(&p), processorRef(p)
        {
            setLookAndFeel(&lookAndFeel);

        \(editorConstructorBody)
            setSize(600, 400);
        }

        \(pluginName)Editor::~\(pluginName)Editor()
        {
            setLookAndFeel(nullptr);
        }

        void \(pluginName)Editor::paint(juce::Graphics& g)
        {
            g.fillAll(lookAndFeel.backgroundColour);
        }

        void \(pluginName)Editor::resized()
        {
        \(editorResizedBody)
        }
        """
        try editorCPP.write(to: dir.appendingPathComponent("PluginEditor.cpp"), atomically: true, encoding: .utf8)
    }

    // MARK: - LookAndFeel (reusable dark theme)

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
                    juce::LookAndFeel_V4::drawLinearSlider(g, x, y, width, height,
                                                            sliderPos, minPos, maxPos, style, slider);
                }
            }

            void drawButtonBackground(juce::Graphics& g, juce::Button& button,
                                      const juce::Colour& bgColour,
                                      bool isHighlighted, bool isDown) override
            {
                auto bounds = button.getLocalBounds().toFloat().reduced(0.5f);
                auto base = bgColour;
                if (isDown) base = base.brighter(0.1f);
                else if (isHighlighted) base = base.brighter(0.05f);

                g.setColour(base);
                g.fillRoundedRectangle(bounds, 6.0f);
                g.setColour(borderColour);
                g.drawRoundedRectangle(bounds, 6.0f, 1.0f);
            }

            juce::Font getLabelFont(juce::Label&) override
            {
                return juce::Font(juce::FontOptions(13.0f));
            }
        };
        """
        try content.write(to: dir.appendingPathComponent("FoundryLookAndFeel.h"), atomically: true, encoding: .utf8)
    }

    // MARK: - CLAUDE.md (expert knowledge document)

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
        case .focused: "Focused — tight, immediate. 3-4 essential controls. No clutter."
        case .balanced: "Balanced — grouped sections, clear primary area, tidy secondary controls. 5-8 parameters."
        case .exploratory: "Exploratory — denser layout, richer modulation, modes, deeper parameter access. 8-12+ parameters."
        }

        // --- Per-type architecture sections ---

        let architectureSection: String
        let dspSection: String

        switch pluginType {
        case .effect:
            architectureSection = """
            ## Architecture: Audio Effect

            An audio effect receives audio input, transforms it, and outputs the result.

            **Signal flow:** Host → processBlock(buffer) → your DSP modifies buffer in-place → Host

            **Key principle:** Every parameter you expose must audibly change the output. If a knob
            doesn't do anything perceptible, remove it. Effects should sound good on default settings
            and get more extreme as you turn knobs up.

            **Processor owns:** parameters, DSP state (filters, delay lines, smoothed values), prepareToPlay setup.
            **Editor owns:** sliders, labels, attachments, layout. Editor reads nothing from the audio thread directly.
            **They connect through:** `AudioProcessorValueTreeState` (apvts). Parameters are defined once in
            the Processor, and the Editor binds UI controls to them via Attachments. That's the only bridge.
            """

            dspSection = """
            ## Phase 2: DSP — Audio Processing

            Your processBlock receives a buffer of audio samples. You must:
            1. Read parameter values (atomically, they're set from the UI thread)
            2. Feed them into SmoothedValues (prevents clicks/zipper noise)
            3. Process every sample in the buffer with real math
            4. Optionally mix dry/wet

            ### processBlock pattern:
            ```cpp
            void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
            {
                juce::ScopedNoDenormals noDenormals;
                for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
                    buffer.clear(i, 0, buffer.getNumSamples());

                // 1. Update smoothed parameter targets
                driveSmoothed.setTargetValue(apvts.getRawParameterValue("drive")->load());
                mixSmoothed.setTargetValue(apvts.getRawParameterValue("mix")->load());

                // 2. Copy dry signal for dry/wet mixing
                juce::AudioBuffer<float> dryBuffer;
                dryBuffer.makeCopyOf(buffer);

                // 3. Process each channel, each sample
                for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                {
                    auto* data = buffer.getWritePointer(ch);
                    for (int s = 0; s < buffer.getNumSamples(); ++s)
                    {
                        const float drive = driveSmoothed.getNextValue();
                        data[s] = std::tanh(data[s] * drive * 4.0f);
                    }
                }

                // 4. Apply dry/wet mix
                for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                {
                    auto* wet = buffer.getWritePointer(ch);
                    const auto* dry = dryBuffer.getReadPointer(ch);
                    for (int s = 0; s < buffer.getNumSamples(); ++s)
                    {
                        const float mix = mixSmoothed.getNextValue();
                        wet[s] = dry[s] + mix * (wet[s] - dry[s]);
                    }
                }
            }
            ```

            ### prepareToPlay pattern:
            ```cpp
            void prepareToPlay(double sampleRate, int samplesPerBlock)
            {
                juce::dsp::ProcessSpec spec;
                spec.sampleRate = sampleRate;
                spec.maximumBlockSize = (juce::uint32)samplesPerBlock;
                spec.numChannels = (juce::uint32)getTotalNumOutputChannels();

                // Prepare all DSP objects
                myFilter.prepare(spec);
                myDelay.prepare(spec);

                // Reset smoothed values with ~20ms ramp
                driveSmoothed.reset(sampleRate, 0.02);
                mixSmoothed.reset(sampleRate, 0.02);
            }
            ```

            ### Available juce::dsp classes:
            | Class | Use for |
            |---|---|
            | `juce::dsp::IIR::Filter<float>` | EQ, lowpass, highpass, shelving, bandpass |
            | `juce::dsp::StateVariableTPTFilter<float>` | Multi-mode filter (LP/HP/BP simultaneously) |
            | `juce::dsp::DelayLine<float>` | Delay, chorus, flanger, comb filtering |
            | `juce::dsp::Reverb` | Reverb (Freeverb algorithm) |
            | `juce::dsp::WaveShaper<float>` | Distortion, saturation, waveshaping |
            | `juce::dsp::Oscillator<float>` | LFO, tone generation, test signals |
            | `juce::dsp::Chorus<float>` | Chorus effect |
            | `juce::dsp::Compressor<float>` | Dynamics compression |
            | `juce::dsp::Limiter<float>` | Output limiting |
            | `juce::SmoothedValue<float>` | Parameter smoothing (ALWAYS use for continuous params) |

            ### DSP rules:
            - Feedback coefficients must be < 1.0 (or you get infinite gain → explosion)
            - Delay times: allocate max in prepareToPlay, set actual time in processBlock
            - All SmoothedValue members must be `.reset(sampleRate, rampTime)` in prepareToPlay
            - Every `getRawParameterValue()` call must use the exact string ID from createParameterLayout
            - Default parameter values must produce a musically useful, audible effect
            """

        case .instrument:
            architectureSection = """
            ## Architecture: Instrument Plugin

            An instrument receives MIDI input and generates audio output. There is no audio input.

            **Signal flow:** Host sends MIDI → Synthesiser distributes to Voices → each Voice renders
            audio via renderNextBlock → mixed into output buffer → Host

            **Key principle:** The Synthesiser + Voice architecture is already set up in the stubs.
            8 voices are pre-allocated. The stubs provide a minimal sine oscillator with basic ADSR.

            ⚠️ **THE STUBS ARE SCAFFOLDING — YOU MUST REPLACE THEM.**
            The sine oscillator stub exists only so the project compiles. It is NOT the finished
            instrument. You must completely redesign the voice implementation, the parameter layout,
            and the UI. If you leave the sine stub as-is, automated validation will reject your work.

            Think like a synth designer. Ask yourself:
            - What kind of instrument does the user's description suggest?
            - What sound sources and shaping tools would make it expressive and versatile?
            - What controls would let someone discover different sounds within this instrument?
            - What makes this instrument unique and worth playing?

            Design your own answer to these questions. A good instrument gives the user enough
            control to explore — not just one static tone.

            **Processor owns:** `juce::Synthesiser synth`, parameters, global DSP (master effects, etc.).
            processBlock calls `synth.renderNextBlock()` — do NOT generate audio directly in processBlock.
            **Voice owns:** per-note state (oscillators, filters, envelopes, etc.). Each voice is one note.
            **Editor owns:** sliders, labels, attachments, layout.
            **They connect through:** `apvts` for parameters. Voices access processor params via pointer.
            """

            dspSection = """
            ## Phase 2: DSP — Voice Rendering + Processor

            ⚠️ The voice stub has a bare sine oscillator — this MUST be completely replaced.
            The starter parameters (level, attack, release) MUST be replaced with your own design.
            If validation detects the unmodified stub, your work will be rejected.

            Design the synthesis engine from scratch. Choose the techniques that fit the instrument
            the user described. The reference material below gives you building blocks — use what
            makes sense, combine them creatively, and make your own design decisions.

            ### Synthesis knowledge reference

            Use the techniques below as building blocks. Pick what fits the instrument you're building —
            you don't need to use all of them, but a good instrument typically combines several.

            #### Oscillator waveforms with anti-aliasing (polyBLEP)
            Naive digital waveforms alias badly. PolyBLEP is cheap and effective:
            ```cpp
            static double polyBlep(double t, double dt)
            {
                if (t < dt) { t /= dt; return t + t - t * t - 1.0; }
                if (t > 1.0 - dt) { t = (t - 1.0) / dt; return t * t + t + t + 1.0; }
                return 0.0;
            }

            // Saw: raw = 2*phase - 1, then subtract polyBlep(phase, dt)
            // Square: raw = (phase < 0.5) ? 1 : -1, add polyBlep at 0 and 0.5
            // Triangle: 2*fabs(2*phase - 1) - 1 (already smooth, no BLEP needed)
            // Sine: std::sin(phase * twoPi) (alias-free)
            ```

            #### Multiple oscillators and detuning
            Layering oscillators creates richer sound. Detuning creates width and movement:
            ```cpp
            double freq2 = frequency * std::pow(2.0, detuneAmount / 12.0); // semitone detune
            double freq2 = frequency * std::pow(2.0, detuneCents / 1200.0); // cent detune
            float mixed = oscMix * osc1 + (1.0f - oscMix) * osc2;
            ```

            #### Per-voice filtering
            Filters shape timbre. Per-voice filters track each note independently:
            ```cpp
            // StateVariableTPTFilter is ideal for per-voice use (LP/HP/BP modes)
            juce::dsp::StateVariableTPTFilter<float> voiceFilter;
            // Prepare with maximumBlockSize = 1 for per-sample processing
            // setCutoffFrequency() and setResonance() can change per-sample
            // processSample(channel, sample) for single-sample filtering
            ```

            #### Envelopes beyond basic ADSR
            Multiple envelopes make sound evolve. Common routing:
            - Amplitude envelope → voice volume (essential)
            - Filter envelope → cutoff modulation (adds movement and punch)
            - Pitch envelope → frequency (for plucks, kicks, percussive attacks)
            ```cpp
            juce::ADSR ampEnv, filterEnv; // independent ADSR instances
            // Both need setSampleRate(), both trigger on noteOn/noteOff
            ```

            #### LFO modulation
            LFOs add life and movement. Common targets: filter cutoff, pitch (vibrato), amplitude (tremolo):
            ```cpp
            float lfo = std::sin(lfoPhase * juce::MathConstants<float>::twoPi);
            lfoPhase += lfoRate / sampleRate;
            if (lfoPhase >= 1.0) lfoPhase -= 1.0;
            // Modulate pitch: freq * std::pow(2.0, depth * lfo / 12.0)
            // Modulate cutoff: cutoff * (1.0f + depth * lfo)
            ```

            #### FM synthesis
            One oscillator modulates another's frequency for metallic, bell-like, evolving tones:
            ```cpp
            double modulator = std::sin(modPhase * twoPi) * fmDepth * modFreq;
            double carrier = std::sin((carrierPhase + modulator / sampleRate) * twoPi);
            ```

            #### Noise and sub-oscillators
            White noise adds texture (hi-hats, breath). Sub-oscillators add body:
            ```cpp
            float noise = (random.nextFloat() * 2.0f - 1.0f); // white noise
            float sub = std::sin(phase * 0.5 * twoPi); // one octave below
            ```

            ### Available juce::dsp classes
            | Class | Use for |
            |---|---|
            | `juce::dsp::StateVariableTPTFilter<float>` | Multi-mode filter (LP/HP/BP) — ideal for per-voice filters |
            | `juce::dsp::IIR::Filter<float>` | EQ, shelving, bandpass |
            | `juce::dsp::DelayLine<float>` | Delay, chorus, flanger, comb filtering |
            | `juce::dsp::Reverb` | Reverb (Freeverb) |
            | `juce::dsp::WaveShaper<float>` | Distortion, saturation, waveshaping |
            | `juce::dsp::Oscillator<float>` | LFO, tone generation |
            | `juce::dsp::Chorus<float>` | Chorus effect |
            | `juce::dsp::Compressor<float>` | Dynamics compression |
            | `juce::dsp::Limiter<float>` | Output limiting |
            | `juce::SmoothedValue<float>` | Parameter smoothing (ALWAYS use for continuous params) |

            ### Processor processBlock pattern:
            ```cpp
            void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
            {
                juce::ScopedNoDenormals noDenormals;
                buffer.clear();
                synth.renderNextBlock(buffer, midiMessages, 0, buffer.getNumSamples());
                // Apply master-level processing here (level, effects, etc.)
            }
            ```

            ### prepareToPlay pattern:
            ```cpp
            void prepareToPlay(double sampleRate, int samplesPerBlock)
            {
                synth.setCurrentPlaybackSampleRate(sampleRate);
                // Reset SmoothedValues, prepare DSP objects, prepare voices
                for (int i = 0; i < synth.getNumVoices(); ++i)
                    if (auto* voice = dynamic_cast<\(pluginName)Voice*>(synth.getVoice(i)))
                        voice->prepareToPlay(sampleRate, samplesPerBlock);
            }
            ```

            ### Voice rules:
            - 8 voices are pre-allocated in the constructor — do not change this
            - Use `buffer.addSample()` (not setSample) — voices are mixed additively
            - Always check `isVoiceActive()` at the top of renderNextBlock
            - Always call `clearCurrentNote()` when the envelope finishes
            - Use `juce::ADSR` for envelopes — it handles sample-accurate note-on/off
            - Access processor parameters via the stored pointer, not globals
            - Filters and envelopes should be per-voice for polyphonic correctness
            """

        case .utility:
            architectureSection = """
            ## Architecture: Utility Plugin

            A utility plugin processes or analyzes audio without creative coloring.
            It should be transparent, precise, and immediately useful.

            **Signal flow:** Same as effect — Host → processBlock → Host.

            **Key principle:** Utility plugins must be safe and predictable. Default settings should
            pass audio through unchanged or with minimal, expected processing. No surprises.
            Gain parameters should use decibels. Metering should be accurate.

            **Common utility types:** gain/trim, stereo width, mono check, phase invert,
            spectrum analyzer, level meter, balance, mid/side encoder.
            """

            dspSection = """
            ## Phase 2: DSP — Utility Processing

            ### processBlock pattern for utilities:
            ```cpp
            void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
            {
                juce::ScopedNoDenormals noDenormals;
                for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
                    buffer.clear(i, 0, buffer.getNumSamples());

                // Read parameters
                gainSmoothed.setTargetValue(
                    juce::Decibels::decibelsToGain(apvts.getRawParameterValue("gain")->load()));

                for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                {
                    auto* data = buffer.getWritePointer(ch);
                    for (int s = 0; s < buffer.getNumSamples(); ++s)
                        data[s] *= gainSmoothed.getNextValue();
                }
            }
            ```

            ### Utility-specific rules:
            - Use `juce::Decibels::decibelsToGain()` / `gainToDecibels()` for all gain parameters
            - Gain range: typically -60 dB to +12 dB, default 0 dB (unity)
            - Width range: 0% (mono) to 200% (wide), default 100% (unchanged)
            - Phase parameters are boolean (invert or not)
            - Be transparent: default settings = no audible change
            """
        }

        // --- Preset section (conditional) ---

        let presetSection: String
        if presetCount > 0 {
            presetSection = """

            ## Phase 5: Presets (\(presetCount) required)

            After completing Phases 1-4, implement exactly \(presetCount) presets.

            ### In PluginProcessor.h — add to private section:
            ```cpp
            struct PresetData {
                const char* name;
                std::vector<std::pair<const char*, float>> values;
            };
            static const std::array<PresetData, \(presetCount)> presets;
            int currentPreset = 0;
            ```

            ### In PluginProcessor.cpp — MODIFY (not add) existing stubs:
            These methods already exist with one-liner bodies. Use Edit to replace them:
            - `getNumPrograms()` → `return \(presetCount);`
            - `getCurrentProgram()` → `return currentPreset;`
            - `getProgramName(int index)` → `return presets[(size_t)index].name;`
            - `setCurrentProgram(int index)`:
            ```cpp
            {
                if (index < 0 || index >= getNumPrograms()) return;
                currentPreset = index;
                for (const auto& [paramId, value] : presets[(size_t)index].values)
                    if (auto* param = apvts.getParameter(paramId))
                        param->setValueNotifyingHost(param->convertTo0to1(value));
            }
            ```

            ### In PluginEditor — add a preset ComboBox:
            ```cpp
            // Header: juce::ComboBox presetBox;
            // Constructor:
            for (int i = 0; i < processorRef.getNumPrograms(); ++i)
                presetBox.addItem(processorRef.getProgramName(i), i + 1);
            presetBox.setSelectedId(processorRef.getCurrentProgram() + 1, juce::dontSendNotification);
            presetBox.onChange = [this] {
                processorRef.setCurrentProgram(presetBox.getSelectedId() - 1);
            };
            addAndMakeVisible(presetBox);
            ```

            Each preset must set ALL parameters to musically distinct, useful values.
            """
        } else {
            presetSection = ""
        }

        // --- Main CLAUDE.md content ---

        let content = """
        # \(pluginName)

        You are an expert C++/JUCE audio plugin developer. Your job is to implement a fully
        working \(pluginRole) plugin based on this description:

        > \(config.prompt)

        Channel layout: **\(channelDesc)** | Interface: **\(interfaceDirection)**

        ---

        ## Project Structure

        | File | Role | You should |
        |---|---|---|
        | `Source/PluginProcessor.h` | Processor class, voice classes (instruments), member declarations | Add members (SmoothedValues, DSP objects, sliders) |
        | `Source/PluginProcessor.cpp` | Parameter layout, prepareToPlay, processBlock, state save/load | Implement all DSP logic |
        | `Source/PluginEditor.h` | Editor class, UI member declarations | Add slider/label/attachment members |
        | `Source/PluginEditor.cpp` | Constructor (create controls), paint, resized (layout) | Build the full UI |
        | `Source/FoundryLookAndFeel.h` | Dark theme with configurable accent colour | Change `accentColour` only |
        | `CMakeLists.txt` | Build configuration | **NEVER MODIFY** |

        Class names: **\(pluginName)Processor**, **\(pluginName)Editor** — do not rename.

        \(architectureSection)

        ---

        ## Implementation Phases

        Follow these phases in strict order. Complete each phase fully before moving to the next.

        ## Phase 1: Parameters — Define the Controls

        Parameters are the contract between your DSP and your UI. Define them first because
        everything else depends on them.

        The starter code has basic parameters (gain/mix or level/attack/release). You must
        REPLACE them with parameters specific to this plugin. Edit `createParameterLayout()`
        in PluginProcessor.cpp:

        ```cpp
        juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout()
        {
            std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;

            // Continuous float parameter:
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"drive", 1}, "Drive",
                juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.5f));

            // Frequency parameter (skewed — more resolution at low end):
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID{"cutoff", 1}, "Cutoff",
                juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.3f), 1000.0f));

            // Choice parameter (discrete options):
            params.push_back(std::make_unique<juce::AudioParameterChoice>(
                juce::ParameterID{"mode", 1}, "Mode",
                juce::StringArray{"Clean", "Warm", "Aggressive"}, 0));

            // Boolean parameter:
            params.push_back(std::make_unique<juce::AudioParameterBool>(
                juce::ParameterID{"bypass", 1}, "Bypass", false));

            return { params.begin(), params.end() };
        }
        ```

        ### Parameter design rules:
        - Choose parameter IDs that are short, lowercase, no spaces: `"drive"`, `"cutoff"`, `"mix"`
        - The second argument to ParameterID is the version number — always use `1`
        - Set default values that produce a musically useful result immediately
        - For frequencies, use skew factor < 1 (typically 0.2-0.4) for log-like feel
        - For gain/volume, consider using decibels with `juce::Decibels::decibelsToGain()`
        - Every plugin should have a `"mix"` (dry/wet) parameter unless it's a utility

        ### Reading parameters in the audio thread:
        ```cpp
        // Atomic read — safe from audio thread:
        float value = apvts.getRawParameterValue("drive")->load();
        ```

        \(dspSection)

        ## Phase 3: Interface — Build the UI

        Every parameter must have a visible, interactive control in the editor.
        The editor must have at least as many `addAndMakeVisible()` calls as you have parameters.

        ### Step 3a: Declare members in PluginEditor.h

        For each parameter, add to the private section:
        ```cpp
        // For a float parameter "drive":
        juce::Slider driveSlider;
        juce::Label driveLabel;
        std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> driveAttachment;

        // For a choice parameter "mode":
        juce::ComboBox modeBox;
        juce::Label modeLabel;
        std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment> modeAttachment;

        // For a bool parameter "bypass":
        juce::ToggleButton bypassButton { "Bypass" };
        std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment> bypassAttachment;
        ```

        ### Step 3b: Wire controls in the constructor (PluginEditor.cpp)

        For each slider parameter:
        ```cpp
        driveSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
        driveSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
        addAndMakeVisible(driveSlider);
        driveAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
            processorRef.apvts, "drive", driveSlider);

        driveLabel.setText("DRIVE", juce::dontSendNotification);
        driveLabel.setJustificationType(juce::Justification::centred);
        driveLabel.setFont(juce::Font(juce::FontOptions(10.0f)));
        driveLabel.setColour(juce::Label::textColourId, lookAndFeel.dimTextColour);
        addAndMakeVisible(driveLabel);
        ```

        For a ComboBox:
        ```cpp
        addAndMakeVisible(modeBox);
        modeAttachment = std::make_unique<juce::AudioProcessorValueTreeState::ComboBoxAttachment>(
            processorRef.apvts, "mode", modeBox);
        modeLabel.setText("MODE", juce::dontSendNotification);
        modeLabel.setJustificationType(juce::Justification::centred);
        addAndMakeVisible(modeLabel);
        ```

        For a ToggleButton:
        ```cpp
        addAndMakeVisible(bypassButton);
        bypassAttachment = std::make_unique<juce::AudioProcessorValueTreeState::ButtonAttachment>(
            processorRef.apvts, "bypass", bypassButton);
        ```

        ### Step 3c: Layout in resized()

        ```cpp
        void resized() override
        {
            auto area = getLocalBounds().reduced(20);

            // Optional: plugin title at top
            auto header = area.removeFromTop(40);

            // Divide remaining area into columns for knob groups
            int numSections = 3; // adjust to your parameter count
            int sectionWidth = area.getWidth() / numSections;

            auto section1 = area.removeFromLeft(sectionWidth);
            auto section2 = area.removeFromLeft(sectionWidth);
            auto section3 = area;

            // Place knob + label in each section
            driveSlider.setBounds(section1.removeFromTop(section1.getHeight() - 20).reduced(10));
            driveLabel.setBounds(section1);

            // ... repeat for other controls
        }
        ```

        ### Slider style guide:
        | Parameter type | Slider style | Why |
        |---|---|---|
        | Gain, drive, amount | `RotaryHorizontalVerticalDrag` | Familiar knob feel |
        | Frequency, time | `RotaryHorizontalVerticalDrag` | Continuous range |
        | Dry/wet mix | `LinearHorizontal` | Visual feedback of balance |
        | Pan, balance | `LinearHorizontal` | Matches spatial metaphor |
        | Mode, type | `juce::ComboBox` | Discrete choices |
        | On/off, bypass | `juce::ToggleButton` | Binary state |

        ## Phase 4: Visual Polish

        - Edit `accentColour` in FoundryLookAndFeel.h to match the plugin's character
        - Call `setSize(width, height)` in the constructor to fit your layout
        - Use `juce::Font(juce::FontOptions(float))` for fonts — never `juce::Font(float)`
        - Suggested sizes: Focused = 400x300, Balanced = 600x400, Exploratory = 800x500

        ### Visual rules:
        - Dark background (already set: 0xff0a0a0a). One muted accent colour, not neon.
        - No emojis, no "AI" branding, no purple/magenta.
        - Group controls into named sections when there are more than 4 parameters.
        - Labels should be uppercase, small font (10-11pt), dimTextColour.
        \(presetSection)

        ---

        ## Fatal Mistakes — WILL NOT COMPILE

        These are the most common errors. Memorize them.

        ### 1. `auto*` on value types
        ```cpp
        // FATAL — std::pair is a value type, not a pointer:
        for (auto* pair : myPairs) { ... }

        // CORRECT:
        for (const auto& [first, second] : myPairs) { ... }
        for (const auto& pair : myPairs) { pair.first->setBounds(...); }
        ```

        ### 2. Duplicate method definitions
        The stubs already define every method declared in the header. If you add a second
        `getNumPrograms()` definition, you get a "redefinition" linker error.
        → Use **Edit** to modify the existing body. Never add a new definition.

        ### 3. Signature mismatch between .h and .cpp
        If the header declares `void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&)`,
        the .cpp must match exactly. Extra `const`, different param names, or missing `override` → error.

        ### 4. Wrong Font constructor
        ```cpp
        // FATAL — deprecated, will not compile:
        juce::Font(14.0f)

        // CORRECT:
        juce::Font(juce::FontOptions(14.0f))
        ```

        ### 5. Missing juce:: prefix
        Every JUCE type must be fully qualified: `juce::Slider`, `juce::Label`,
        `juce::AudioProcessorValueTreeState`, etc. Unqualified names → "undeclared identifier".

        ### 6. Parameter ID mismatch
        If createParameterLayout uses `"drive"` but the SliderAttachment uses `"Drive"` or `"drv"`,
        you get a runtime assertion failure. IDs must match exactly, case-sensitive.

        ---

        ## Automated Validation

        After your code compiles, it is automatically validated. The starter code already
        passes these checks — your job is to replace the generic implementation with one
        that matches the plugin description. Do not remove functionality without replacing it.

        | Check | Requirement |
        |---|---|
        | Parameters exist | ≥1 parameter with `ParameterID{"...", 1}` in Processor.cpp |
        | DSP is real | processBlock contains actual audio processing (math, filters, parameter reads) |
        | UI coverage | Every parameter ID string appears in Editor.cpp (via Attachments) |
        | Visible controls | ≥2 `addAndMakeVisible()` calls in Editor.cpp |
        \(pluginType == .instrument ? """
        | Voice rendering | `renderNextBlock` exists with real implementation |
        | Enough controls | Instruments need ≥5 parameters for sound exploration |
        | Voice redesigned | The sine stub fingerprint must be gone — voice must be your own design |
        """ : "")
        """

        try content.write(to: dir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    }
}
