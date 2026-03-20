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
            struct \(pluginName)Sound : public juce::SynthesiserSound
            {
                bool appliesToNote(int) override { return true; }
                bool appliesToChannel(int) override { return true; }
            };

            class \(pluginName)Voice : public juce::SynthesiserVoice
            {
            public:
                bool canPlaySound(juce::SynthesiserSound* sound) override
                {
                    return dynamic_cast<\(pluginName)Sound*>(sound) != nullptr;
                }
                void startNote(int midiNote, float velocity, juce::SynthesiserSound*, int) override {}
                void stopNote(float, bool) override { clearCurrentNote(); }
                void pitchWheelMoved(int) override {}
                void controllerMoved(int, int) override {}
                void renderNextBlock(juce::AudioBuffer<float>&, int startSample, int numSamples) override {}
            };

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
        \(isInstrument ? "    juce::Synthesiser synth;\n" : "")
            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Processor)
        };
        """
        try processorH.write(to: dir.appendingPathComponent("PluginProcessor.h"), atomically: true, encoding: .utf8)

        // ── PluginProcessor.cpp ──────────────────────────────────────

        var synthInit = ""
        var processBlockBody: String

        if isInstrument {
            synthInit = """

                synth.addSound(new \(pluginName)Sound());
                for (int i = 0; i < 8; ++i)
                    synth.addVoice(new \(pluginName)Voice());
            """
            processBlockBody = """
                juce::ScopedNoDenormals noDenormals;
                buffer.clear();
                synth.renderNextBlock(buffer, midiMessages, 0, buffer.getNumSamples());
            """
        } else {
            processBlockBody = """
                juce::ScopedNoDenormals noDenormals;
                for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
                    buffer.clear(i, 0, buffer.getNumSamples());
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
            std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;
            return { params.begin(), params.end() };
        }

        void \(pluginName)Processor::prepareToPlay(double sampleRate, int samplesPerBlock)
        {
        \(isInstrument ? "    synth.setCurrentPlaybackSampleRate(sampleRate);" : "    juce::ignoreUnused(sampleRate, samplesPerBlock);")
        }

        void \(pluginName)Processor::releaseResources() {}

        void \(pluginName)Processor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
        {
        \(isInstrument ? "" : "    juce::ignoreUnused(midiMessages);\n")\(processBlockBody)
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

            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Editor)
        };
        """
        try editorH.write(to: dir.appendingPathComponent("PluginEditor.h"), atomically: true, encoding: .utf8)

        // ── PluginEditor.cpp ─────────────────────────────────────────

        let editorCPP = """
        #include "PluginEditor.h"

        \(pluginName)Editor::\(pluginName)Editor(\(pluginName)Processor& p)
            : AudioProcessorEditor(&p), processorRef(p)
        {
            setLookAndFeel(&lookAndFeel);
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
        case .focused: "Keep the UI tight and immediate. Show only essential controls at first glance."
        case .balanced: "Use clear grouped sections with a strong primary area and tidy secondary controls."
        case .exploratory: "Allow a denser interface with richer modulation, modes, and deeper parameter access."
        }

        let instrumentSkills: String = pluginType == .instrument ? """

        ### Instrument voice pattern
        Voices are declared in PluginProcessor.h. Each voice handles one note:
        ```cpp
        void startNote(int midiNote, float velocity, juce::SynthesiserSound*, int) override
        {
            frequency = juce::MidiMessage::getMidiNoteInHertz(midiNote);
            level = velocity;
            adsr.noteOn();
        }

        void stopNote(float, bool allowTailOff) override
        {
            adsr.noteOff();
            if (!allowTailOff) clearCurrentNote();
        }

        void renderNextBlock(juce::AudioBuffer<float>& buffer, int startSample, int numSamples) override
        {
            // Generate samples using oscillator + envelope
            for (int s = startSample; s < startSample + numSamples; ++s)
            {
                float sample = /* oscillator output */ * adsr.getNextSample() * level;
                for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                    buffer.addSample(ch, s, sample);
            }
            if (!adsr.isActive()) clearCurrentNote();
        }
        ```
        - 8 voices are pre-allocated in the constructor
        - Access processor parameters via `dynamic_cast` or store pointers
        - Use `juce::ADSR` for envelopes, `juce::dsp::Oscillator<float>` for waveforms
        """ : ""

        let utilitySkills: String = pluginType == .utility ? """

        ### Utility plugin guidelines
        - Stay safe, transparent, and immediately useful on first load
        - Expose clear metering, routing, gain staging, or analysis behavior
        - Avoid fake "creative" DSP if the plugin is meant to be a helper or analyzer
        - Use `juce::Decibels::decibelsToGain()` for dB parameters
        """ : ""

        let presetSection: String
        if presetCount > 0 {
            presetSection = """

            ## SKILL: Presets (\(presetCount) required)

            Implement exactly **\(presetCount) presets** using JUCE's program system.

            ### In PluginProcessor.h:
            ```cpp
            struct PresetData {
                const char* name;
                std::vector<std::pair<const char*, float>> values;
            };
            static const std::array<PresetData, \(presetCount)> presets;
            int currentPreset = 0;
            ```

            ### In PluginProcessor.cpp — use Edit to MODIFY the existing one-liner stubs:
            The file already contains these methods with stub bodies. Use your Edit tool to replace their bodies:
            - `getNumPrograms()` → return \(presetCount);
            - `getCurrentProgram()` → return currentPreset;
            - `getProgramName(int index)` → return presets[index].name;
            - `setCurrentProgram(int index)` → apply preset values via apvts

            **DO NOT add new method definitions — they already exist. Edit them in place.**

            ```cpp
            // setCurrentProgram implementation pattern:
            void \(pluginName)Processor::setCurrentProgram(int index)
            {
                if (index < 0 || index >= getNumPrograms()) return;
                currentPreset = index;
                for (const auto& [paramId, value] : presets[index].values)
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
            Each preset must set ALL parameters to musically distinct values. Short, descriptive names.
            """
        } else {
            presetSection = ""
        }

        let content = """
        # \(pluginName) — Audio Plugin Brief

        ## Mission
        You are an expert JUCE/C++ audio plugin developer.
        Build a **\(pluginRole)** plugin: **\(config.prompt)**

        Channel layout: **\(channelDesc)**
        Interface style: **\(interfaceStyle.rawValue)**

        ## Project
        - `Source/PluginProcessor.h/.cpp` — DSP engine, parameters, audio processing
        - `Source/PluginEditor.h/.cpp` — interface, controls, layout
        - `Source/FoundryLookAndFeel.h` — visual theme (change `accentColour` to fit plugin character)
        - `CMakeLists.txt` — build config, **DO NOT MODIFY**

        Class names: `\(pluginName)Processor`, `\(pluginName)Editor` — do not rename.
        C++17. JUCE only. No external dependencies. All JUCE types prefixed `juce::`.
        Do not create new files. Do not modify CMakeLists.txt.

        ## SKILL: Parameter System

        Parameters bridge DSP and UI. Define them in `createParameterLayout()`:

        ```cpp
        // Continuous value (gain, frequency, time):
        params.push_back(std::make_unique<juce::AudioParameterFloat>(
            juce::ParameterID{"drive", 1}, "Drive",
            juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.5f));

        // Skewed range (frequencies):
        juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.3f)  // skew < 1 = more resolution at low end

        // Discrete choice (waveform, mode):
        params.push_back(std::make_unique<juce::AudioParameterChoice>(
            juce::ParameterID{"mode", 1}, "Mode",
            juce::StringArray{"Clean", "Warm", "Aggressive"}, 0));

        // Boolean (bypass, enable):
        params.push_back(std::make_unique<juce::AudioParameterBool>(
            juce::ParameterID{"bypass", 1}, "Bypass", false));
        ```

        Reading parameters in processBlock:
        ```cpp
        auto value = apvts.getRawParameterValue("paramId")->load();
        ```
        Always smooth continuous parameters with `juce::SmoothedValue<float>` to avoid zipper noise.

        ## SKILL: DSP

        ### Effect processBlock structure:
        ```cpp
        void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
        {
            juce::ScopedNoDenormals noDenormals;
            for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
                buffer.clear(i, 0, buffer.getNumSamples());

            // Read parameters with smoothing
            driveSmoothed.setTargetValue(apvts.getRawParameterValue("drive")->load());

            // Copy dry buffer if you need dry/wet mix
            juce::AudioBuffer<float> dryBuffer;
            dryBuffer.makeCopyOf(buffer);

            // Process audio per-sample or per-block
            for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
            {
                auto* data = buffer.getWritePointer(ch);
                for (int s = 0; s < buffer.getNumSamples(); ++s)
                {
                    const float drive = driveSmoothed.getNextValue();
                    data[s] = std::tanh(data[s] * drive);
                }
            }

            // Apply dry/wet
            const float mix = apvts.getRawParameterValue("mix")->load();
            for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
            {
                auto* wet = buffer.getWritePointer(ch);
                auto* dry = dryBuffer.getReadPointer(ch);
                for (int s = 0; s < buffer.getNumSamples(); ++s)
                    wet[s] = dry[s] + mix * (wet[s] - dry[s]);
            }
        }
        ```

        ### Common juce::dsp classes:
        - `juce::dsp::IIR::Filter<float>` — EQ, lowpass, highpass, shelving
        - `juce::dsp::DelayLine<float>` — delay, chorus base, flanger
        - `juce::dsp::Reverb` — reverb
        - `juce::dsp::WaveShaper<float>` — distortion, saturation
        - `juce::dsp::Oscillator<float>` — LFO, tone generation
        - `juce::dsp::Chorus<float>` — chorus
        - `juce::dsp::Compressor<float>` — dynamics
        - `juce::SmoothedValue<float>` — parameter smoothing

        ### Preparing DSP (in prepareToPlay):
        ```cpp
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = (juce::uint32) samplesPerBlock;
        spec.numChannels = (juce::uint32) getTotalNumOutputChannels();
        myFilter.prepare(spec);
        mySmoothedValue.reset(sampleRate, 0.02);
        ```

        ### Rules:
        - Feedback must be < 1.0
        - Sensible defaults that sound good immediately
        - Effects: keep dry/wet mix when musically relevant
        \(instrumentSkills)\(utilitySkills)

        ## SKILL: Interface

        ### Control types:
        - `RotaryHorizontalVerticalDrag` — continuous parameters (most common)
        - `LinearHorizontal` — gain staging, levels, wide-range params
        - `juce::ComboBox` — discrete choices (waveform, mode, preset)
        - `juce::ToggleButton` — on/off switches (bypass, enable)

        ### Wiring a control to a parameter:
        ```cpp
        // In header (private section):
        juce::Slider driveSlider;
        juce::Label driveLabel;
        std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> driveAttachment;

        // In constructor:
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

        // For ComboBox:
        std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment> modeAttachment;
        modeAttachment = std::make_unique<juce::AudioProcessorValueTreeState::ComboBoxAttachment>(
            processorRef.apvts, "mode", modeBox);

        // For ToggleButton:
        std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment> bypassAttachment;
        ```

        ### Layout:
        ```cpp
        void resized() override
        {
            auto area = getLocalBounds().reduced(20);
            auto header = area.removeFromTop(48);
            // Group controls into sections
            auto driveSection = area.removeFromLeft(area.getWidth() / 3);
            auto toneSection = area.removeFromLeft(area.getWidth() / 2);
            auto outputSection = area;
            // Position knobs within each section
            mySlider.setBounds(section.reduced(10));
        }
        ```

        ### C++ rules (WILL NOT COMPILE IF VIOLATED):
        - **Iteration**: `for (const auto& item : container)` — NEVER `for (auto* item : container)`. The `auto*` syntax is ONLY for pointer return values. Using `auto*` on a `std::pair` or struct WILL NOT COMPILE.
          ```cpp
          // CORRECT:
          for (const auto& [slider, label] : sliderPairs) { ... }
          for (const auto& pair : myPairs) { pair.first->setBounds(...); }
          // WRONG — WILL NOT COMPILE:
          for (auto* pair : myPairs) { ... }
          ```
        - **No duplicate definitions**: Methods like getNumPrograms(), getCurrentProgram(), etc. already exist in PluginProcessor.cpp. Use Edit to MODIFY them — do NOT add new definitions or you get "redefinition" errors.
        - All method signatures in .cpp must match .h declarations exactly.

        ### Visual rules:
        - Dark background (0xff0a0a0a to 0xff181818), one muted accent colour
        - No emojis, no "AI" branding, no purple, no bright neon
        - Group controls into named sections when there are more than 4
        - Use `juce::Font(juce::FontOptions(float))` — never `juce::Font(float)`
        - `setSize(width, height)` to fit your layout
        - \(interfaceDirection)
        \(presetSection)
        """
        try content.write(to: dir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    }
}
