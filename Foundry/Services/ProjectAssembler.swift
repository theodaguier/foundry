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
        let kitDir = projectDir.appendingPathComponent("juce-kit")
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: kitDir, withIntermediateDirectories: true)

        try writeCMakeLists(to: projectDir, pluginName: pluginName, pluginType: pluginType, config: config)
        try writeJuceKit(to: kitDir, pluginName: pluginName, pluginType: pluginType)
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

    static func inferPluginType(from prompt: String) -> PluginType {
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

    static func inferInterfaceStyle(from prompt: String, pluginType: PluginType) -> InterfaceStyle {
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

    // MARK: - JUCE Knowledge Kit

    private static func writeJuceKit(
        to kitDir: URL,
        pluginName: String,
        pluginType: PluginType
    ) throws {
        try writeJuceAPI(to: kitDir, pluginName: pluginName, pluginType: pluginType)
        try writeDSPPatterns(to: kitDir, pluginType: pluginType)
        try writeUIPatterns(to: kitDir, pluginName: pluginName)
        try writeLookAndFeel(to: kitDir)
        try writeBuildRules(to: kitDir, pluginName: pluginName)
        try writePresets(to: kitDir, pluginName: pluginName)
    }

    // MARK: juce-api.md

    private static func writeJuceAPI(to dir: URL, pluginName: String, pluginType: PluginType) throws {
        let isInstrument = pluginType == .instrument

        let instrumentAPI = isInstrument ? """

        ### Synthesiser + Voice (instruments only)

        ```cpp
        // juce::Synthesiser — manages polyphonic voices
        synth.addSound(new MySynthSound());
        synth.addVoice(new MySynthVoice());         // add 8 voices
        synth.setCurrentPlaybackSampleRate(sr);
        synth.renderNextBlock(buffer, midi, 0, numSamples);

        // juce::SynthesiserVoice — one per note
        bool canPlaySound(juce::SynthesiserSound*) override;
        void startNote(int midiNote, float velocity, juce::SynthesiserSound*, int pitchWheel) override;
        void stopNote(float velocity, bool allowTailOff) override;
        void renderNextBlock(juce::AudioBuffer<float>&, int startSample, int numSamples) override;
        void pitchWheelMoved(int newValue) override;
        void controllerMoved(int controllerNumber, int newValue) override;

        // Voice helpers
        double getSampleRate();
        bool isVoiceActive();
        void clearCurrentNote();
        double juce::MidiMessage::getMidiNoteInHertz(int noteNumber);

        // juce::SynthesiserSound — determines which notes/channels a voice responds to
        bool appliesToNote(int midiNoteNumber) override;
        bool appliesToChannel(int midiChannel) override;
        ```

        """ : ""

        let content = """
        # JUCE API Reference

        ## AudioProcessor

        The base class for all plugins. You subclass it as `\(pluginName)Processor`.

        ```cpp
        // Lifecycle
        void prepareToPlay(double sampleRate, int samplesPerBlock) override;
        void releaseResources() override;
        void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midi) override;

        // Editor
        juce::AudioProcessorEditor* createEditor() override;
        bool hasEditor() const override;

        // Identity
        const juce::String getName() const override;
        bool acceptsMidi() const override;
        bool producesMidi() const override;
        double getTailLengthSeconds() const override;

        // Programs/Presets
        int getNumPrograms() override;
        int getCurrentProgram() override;
        void setCurrentProgram(int index) override;
        const juce::String getProgramName(int index) override;
        void changeProgramName(int index, const juce::String& newName) override;

        // State persistence
        void getStateInformation(juce::MemoryBlock& destData) override;
        void setStateInformation(const void* data, int sizeInBytes) override;
        ```

        ## AudioProcessorValueTreeState (APVTS)

        Thread-safe parameter system. The bridge between processor and editor.

        ```cpp
        // Creating parameters
        juce::AudioProcessorValueTreeState apvts;
        // Initialize in constructor: apvts(*this, nullptr, "PARAMETERS", createParameterLayout())

        // Parameter types
        juce::AudioParameterFloat(juce::ParameterID{"id", 1}, "Name",
            juce::NormalisableRange<float>(min, max, step, skew), defaultValue);
        juce::AudioParameterChoice(juce::ParameterID{"id", 1}, "Name",
            juce::StringArray{"A", "B", "C"}, defaultIndex);
        juce::AudioParameterBool(juce::ParameterID{"id", 1}, "Name", defaultValue);
        juce::AudioParameterInt(juce::ParameterID{"id", 1}, "Name", min, max, defaultValue);

        // Reading parameters (audio-thread safe)
        float val = apvts.getRawParameterValue("id")->load();

        // State save/load
        auto state = apvts.copyState();
        std::unique_ptr<juce::XmlElement> xml(state.createXml());
        copyXmlToBinary(*xml, destData);

        std::unique_ptr<juce::XmlElement> xml(getXmlFromBinary(data, sizeInBytes));
        if (xml && xml->hasTagName(apvts.state.getType()))
            apvts.replaceState(juce::ValueTree::fromXml(*xml));
        ```

        ## AudioBuffer

        ```cpp
        buffer.getNumChannels();
        buffer.getNumSamples();
        float* data = buffer.getWritePointer(channel);
        const float* data = buffer.getReadPointer(channel);
        buffer.addSample(channel, sampleIndex, value);  // additive (for voices)
        buffer.setSample(channel, sampleIndex, value);   // overwrite
        buffer.clear();
        buffer.clear(channel, startSample, numSamples);
        buffer.makeCopyOf(other);
        ```

        ## BusesProperties

        ```cpp
        // Effect (audio in + out)
        BusesProperties()
            .withInput("Input", juce::AudioChannelSet::stereo(), true)
            .withOutput("Output", juce::AudioChannelSet::stereo(), true)

        // Instrument (MIDI in, audio out only)
        BusesProperties()
            .withOutput("Output", juce::AudioChannelSet::stereo(), true)
        ```
        \(instrumentAPI)
        ## DSP Module Classes

        | Class | Use for |
        |---|---|
        | `juce::dsp::IIR::Filter<float>` | EQ, lowpass, highpass, shelving, bandpass |
        | `juce::dsp::StateVariableTPTFilter<float>` | Multi-mode filter (LP/HP/BP simultaneously) |
        | `juce::dsp::DelayLine<float>` | Delay, chorus, flanger, comb filtering |
        | `juce::Reverb` | Reverb — use `juce::Reverb` (NOT `juce::dsp::Reverb`). Call `setSampleRate()`, `setParameters()`, `processStereo(float*, float*, numSamples)`. The `juce::dsp` wrapper lacks `processStereo`. |
        | `juce::dsp::WaveShaper<float>` | Distortion, saturation, waveshaping |
        | `juce::dsp::Oscillator<float>` | LFO, tone generation, test signals |
        | `juce::dsp::Chorus<float>` | Chorus effect |
        | `juce::dsp::Compressor<float>` | Dynamics compression |
        | `juce::dsp::Limiter<float>` | Output limiting |
        | `juce::SmoothedValue<float>` | Parameter smoothing (ALWAYS use for continuous params) |
        | `juce::ADSR` | Amplitude/filter envelopes |

        ## ProcessSpec (for juce::dsp classes)

        ```cpp
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = (juce::uint32)samplesPerBlock;
        spec.numChannels = (juce::uint32)getTotalNumOutputChannels();
        myFilter.prepare(spec);
        ```
        """
        try content.write(to: dir.appendingPathComponent("juce-api.md"), atomically: true, encoding: .utf8)
    }

    // MARK: dsp-patterns.md

    private static func writeDSPPatterns(to dir: URL, pluginType: PluginType) throws {
        let effectPatterns = """
        # DSP Patterns

        ## Effect: processBlock pattern

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

        ## prepareToPlay pattern

        ```cpp
        void prepareToPlay(double sampleRate, int samplesPerBlock)
        {
            juce::dsp::ProcessSpec spec;
            spec.sampleRate = sampleRate;
            spec.maximumBlockSize = (juce::uint32)samplesPerBlock;
            spec.numChannels = (juce::uint32)getTotalNumOutputChannels();

            myFilter.prepare(spec);
            myDelay.prepare(spec);

            driveSmoothed.reset(sampleRate, 0.02);
            mixSmoothed.reset(sampleRate, 0.02);
        }
        ```
        """

        let instrumentPatterns = """
        # DSP Patterns

        ## Instrument: Synthesiser + Voice architecture

        ### Processor processBlock
        ```cpp
        void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
        {
            juce::ScopedNoDenormals noDenormals;
            buffer.clear();
            synth.renderNextBlock(buffer, midiMessages, 0, buffer.getNumSamples());
            // Apply master-level processing here (level, effects, etc.)
        }
        ```

        ### prepareToPlay
        ```cpp
        void prepareToPlay(double sampleRate, int samplesPerBlock)
        {
            synth.setCurrentPlaybackSampleRate(sampleRate);
            for (int i = 0; i < synth.getNumVoices(); ++i)
                if (auto* voice = dynamic_cast<MyVoice*>(synth.getVoice(i)))
                    voice->prepareToPlay(sampleRate, samplesPerBlock);
        }
        ```

        ### Voice rules
        - Allocate 8 voices in the constructor
        - Use `buffer.addSample()` (not setSample) — voices are mixed additively
        - Always check `isVoiceActive()` at the top of renderNextBlock
        - Always call `clearCurrentNote()` when the envelope finishes
        - Use `juce::ADSR` for envelopes — it handles sample-accurate note-on/off
        - Access processor parameters via a stored pointer, not globals
        - Filters and envelopes should be per-voice for polyphonic correctness

        ## Synthesis building blocks

        ### Oscillator waveforms with anti-aliasing (polyBLEP)
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

        ### Multiple oscillators and detuning
        ```cpp
        double freq2 = frequency * std::pow(2.0, detuneAmount / 12.0); // semitone detune
        double freq2 = frequency * std::pow(2.0, detuneCents / 1200.0); // cent detune
        float mixed = oscMix * osc1 + (1.0f - oscMix) * osc2;
        ```

        ### Per-voice filtering
        ```cpp
        juce::dsp::StateVariableTPTFilter<float> voiceFilter;
        // Prepare with maximumBlockSize = 1 for per-sample processing
        // setCutoffFrequency() and setResonance() can change per-sample
        // processSample(channel, sample) for single-sample filtering
        ```

        ### Multiple envelopes
        ```cpp
        juce::ADSR ampEnv, filterEnv; // independent ADSR instances
        // Both need setSampleRate(), both trigger on noteOn/noteOff
        // Amplitude envelope → voice volume
        // Filter envelope → cutoff modulation (adds movement and punch)
        // Pitch envelope → frequency (for plucks, kicks, percussive attacks)
        ```

        ### LFO modulation
        ```cpp
        float lfo = std::sin(lfoPhase * juce::MathConstants<float>::twoPi);
        lfoPhase += lfoRate / sampleRate;
        if (lfoPhase >= 1.0) lfoPhase -= 1.0;
        // Modulate pitch: freq * std::pow(2.0, depth * lfo / 12.0)
        // Modulate cutoff: cutoff * (1.0f + depth * lfo)
        ```

        ### FM synthesis
        ```cpp
        double modulator = std::sin(modPhase * twoPi) * fmDepth * modFreq;
        double carrier = std::sin((carrierPhase + modulator / sampleRate) * twoPi);
        ```

        ### Noise and sub-oscillators
        ```cpp
        float noise = (random.nextFloat() * 2.0f - 1.0f); // white noise
        float sub = std::sin(phase * 0.5 * twoPi); // one octave below
        ```
        """

        let utilityPatterns = """
        # DSP Patterns

        ## Utility: processBlock pattern

        ```cpp
        void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
        {
            juce::ScopedNoDenormals noDenormals;
            for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
                buffer.clear(i, 0, buffer.getNumSamples());

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

        ## Utility-specific rules
        - Use `juce::Decibels::decibelsToGain()` / `gainToDecibels()` for all gain parameters
        - Gain range: typically -60 dB to +12 dB, default 0 dB (unity)
        - Width range: 0% (mono) to 200% (wide), default 100% (unchanged)
        - Phase parameters are boolean (invert or not)
        - Default settings = no audible change (transparent)
        """

        let content: String = switch pluginType {
        case .effect: effectPatterns
        case .instrument: instrumentPatterns
        case .utility: utilityPatterns
        }

        let commonRules = """

        ## Common DSP rules
        - Feedback coefficients must be < 1.0 (or you get infinite gain → explosion)
        - Delay times: allocate max in prepareToPlay, set actual time in processBlock
        - All SmoothedValue members must be `.reset(sampleRate, rampTime)` in prepareToPlay
        - Every `getRawParameterValue()` call must use the exact string ID from createParameterLayout
        - Default parameter values must produce a musically useful, audible effect
        - Every parameter you expose must audibly change the output
        """

        try (content + commonRules).write(to: dir.appendingPathComponent("dsp-patterns.md"), atomically: true, encoding: .utf8)
    }

    // MARK: ui-patterns.md

    private static func writeUIPatterns(to dir: URL, pluginName: String) throws {
        let content = """
        # UI Patterns — PluginEditor

        ## Editor structure

        The editor is a `juce::AudioProcessorEditor` subclass named `\(pluginName)Editor`.
        It owns UI controls (sliders, labels, combo boxes) and connects them to processor
        parameters via APVTS Attachments.

        **CRITICAL**: The editor destructor MUST call `setLookAndFeel(nullptr)`:
        ```cpp
        ~\(pluginName)Editor() override { setLookAndFeel(nullptr); }
        ```

        ## Declaring members in the header

        For each parameter, declare in the private section of the editor class:

        ```cpp
        // Float parameter "drive":
        juce::Slider driveSlider;
        juce::Label driveLabel;
        std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> driveAttachment;

        // Choice parameter "mode":
        juce::ComboBox modeBox;
        juce::Label modeLabel;
        std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment> modeAttachment;

        // Bool parameter "bypass":
        juce::ToggleButton bypassButton { "Bypass" };
        std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment> bypassAttachment;
        ```

        ## Wiring controls in the constructor

        ```cpp
        // Slider
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

        // ComboBox
        addAndMakeVisible(modeBox);
        modeAttachment = std::make_unique<juce::AudioProcessorValueTreeState::ComboBoxAttachment>(
            processorRef.apvts, "mode", modeBox);
        modeLabel.setText("MODE", juce::dontSendNotification);
        modeLabel.setJustificationType(juce::Justification::centred);
        addAndMakeVisible(modeLabel);

        // ToggleButton
        addAndMakeVisible(bypassButton);
        bypassAttachment = std::make_unique<juce::AudioProcessorValueTreeState::ButtonAttachment>(
            processorRef.apvts, "bypass", bypassButton);
        ```

        ## Layout in resized()

        ```cpp
        void resized()
        {
            auto area = getLocalBounds().reduced(20);
            auto header = area.removeFromTop(40); // plugin title

            int numSections = 3;
            int sectionWidth = area.getWidth() / numSections;

            auto section1 = area.removeFromLeft(sectionWidth);
            driveSlider.setBounds(section1.removeFromTop(section1.getHeight() - 20).reduced(10));
            driveLabel.setBounds(section1);
            // ... repeat for other controls
        }
        ```

        ## Slider style guide

        | Parameter type | Slider style | Why |
        |---|---|---|
        | Gain, drive, amount | `RotaryHorizontalVerticalDrag` | Familiar knob feel |
        | Frequency, time | `RotaryHorizontalVerticalDrag` | Continuous range |
        | Dry/wet mix | `LinearHorizontal` | Visual feedback of balance |
        | Pan, balance | `LinearHorizontal` | Matches spatial metaphor |
        | Mode, type | `juce::ComboBox` | Discrete choices |
        | On/off, bypass | `juce::ToggleButton` | Binary state |

        ## Every parameter must have a visible control

        Every parameter ID in `createParameterLayout()` must have a matching control
        in the editor with `addAndMakeVisible()` and a matching Attachment.
        """
        try content.write(to: dir.appendingPathComponent("ui-patterns.md"), atomically: true, encoding: .utf8)
    }

    // MARK: look-and-feel.md

    private static func writeLookAndFeel(to dir: URL) throws {
        let content = """
        # FoundryLookAndFeel

        Create a header-only `FoundryLookAndFeel.h` in `Source/` with the exact code below.
        You may only change `accentColour` to match the plugin's character.

        ```cpp
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
            juce::Colour accentColour      { 0xffc0c0c0 };  // ← change this only
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
                setColour(juce::PopupMenu::backgroundColourId, surfaceColour);
                setColour(juce::PopupMenu::textColourId, textColour);
                setColour(juce::PopupMenu::highlightedBackgroundColourId, accentColour.withAlpha(0.2f));
                setColour(juce::PopupMenu::highlightedTextColourId, textColour);
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
        ```

        ## Visual rules
        - Dark background (0xff0a0a0a). One muted accent colour, not neon.
        - No emojis, no "AI" branding, no purple/magenta.
        - Group controls into named sections when there are more than 4 parameters.
        - Labels should be uppercase, small font (10-11pt), dimTextColour.
        - Suggested window sizes: Focused = 400x300, Balanced = 600x400, Exploratory = 800x500

        ## CRITICAL: LookAndFeel lifecycle
        - Constructor: `setLookAndFeel(&lookAndFeel);`
        - Destructor: `~MyEditor() override { setLookAndFeel(nullptr); }` — MANDATORY or crash on close
        - Do NOT use `~MyEditor() override = default;` — you MUST explicitly call `setLookAndFeel(nullptr)`
        """
        try content.write(to: dir.appendingPathComponent("look-and-feel.md"), atomically: true, encoding: .utf8)
    }

    // MARK: build-rules.md

    private static func writeBuildRules(to dir: URL, pluginName: String) throws {
        let content = """
        # Build Rules

        ## C++17 standard
        - All code must compile with C++17.
        - Use `auto`, structured bindings, `std::optional`, `if constexpr` freely.

        ## juce:: namespace
        - Every JUCE type must be fully qualified: `juce::Slider`, `juce::Label`,
          `juce::AudioProcessorValueTreeState`, `juce::dsp::IIR::Filter<float>`, etc.
        - Unqualified names cause "undeclared identifier" errors.

        ## Class naming
        - Processor class: `\(pluginName)Processor`
        - Editor class: `\(pluginName)Editor`
        - Do NOT rename these — CMakeLists.txt and the JUCE module system depend on them.

        ## File structure
        You must create these files in `Source/`:
        - `PluginProcessor.h` — Processor class declaration (and voice classes for instruments)
        - `PluginProcessor.cpp` — All processor method implementations
        - `PluginEditor.h` — Editor class declaration
        - `PluginEditor.cpp` — All editor method implementations
        - `FoundryLookAndFeel.h` — Header-only look and feel (copy from juce-kit/look-and-feel.md)

        ## CMakeLists.txt
        **NEVER modify CMakeLists.txt** — it is correct and must not be touched.

        ## Fatal mistakes that break the build

        ### 1. `auto*` on value types
        ```cpp
        // FATAL:
        for (auto* pair : myPairs) { ... }
        // CORRECT:
        for (const auto& [first, second] : myPairs) { ... }
        ```

        ### 2. Duplicate method definitions
        Do not define a method twice. Every method declared in .h must have exactly
        one implementation in .cpp.

        ### 3. Signature mismatch between .h and .cpp
        The .cpp implementation must match the .h declaration exactly — same types,
        same const qualifiers, same parameter order.

        ### 4. Wrong Font constructor
        ```cpp
        // FATAL — deprecated, will not compile:
        juce::Font(14.0f)
        // CORRECT:
        juce::Font(juce::FontOptions(14.0f))
        ```

        ### 5. Parameter ID mismatch
        If createParameterLayout uses `"drive"` but the SliderAttachment uses `"Drive"`,
        you get a runtime assertion failure. IDs must match exactly, case-sensitive.

        ### 6. Missing includes
        - `PluginProcessor.cpp` must `#include "PluginProcessor.h"` and `#include "PluginEditor.h"`
        - `PluginEditor.cpp` must `#include "PluginEditor.h"`
        - `PluginEditor.h` must `#include "PluginProcessor.h"` and `#include "FoundryLookAndFeel.h"`
        - `PluginProcessor.h` must `#include <JuceHeader.h>`
        - `FoundryLookAndFeel.h` must `#include <JuceHeader.h>`

        ### 7. Linker errors about undefined symbols
        If the linker complains about undefined symbols, the issue is in your source code,
        NOT in CMakeLists.txt. Check that every method declared in .h is implemented in .cpp.

        ### 8. Wrong Reverb class
        ```cpp
        // WRONG — juce::dsp::Reverb has no processStereo():
        juce::dsp::Reverb reverb;
        // CORRECT — use juce::Reverb directly:
        juce::Reverb reverb;
        // API: reverb.setSampleRate(sr); reverb.setParameters({...}); reverb.processStereo(L, R, n);
        ```

        ### 9. LookAndFeel dangling pointer
        ```cpp
        // FATAL — crash when editor closes:
        ~MyEditor() override = default;
        // CORRECT:
        ~MyEditor() override { setLookAndFeel(nullptr); }
        ```

        ### 10. Missing PopupMenu colours
        ComboBox dropdowns are unreadable without PopupMenu colour overrides in LookAndFeel.
        Always set `PopupMenu::backgroundColourId`, `textColourId`, `highlightedBackgroundColourId`.
        """
        try content.write(to: dir.appendingPathComponent("build-rules.md"), atomically: true, encoding: .utf8)
    }

    // MARK: presets.md

    private static func writePresets(to dir: URL, pluginName: String) throws {
        let content = """
        # Presets — JUCE Program System

        ## Implementation

        ### In PluginProcessor.h — add to private section:
        ```cpp
        struct PresetData {
            const char* name;
            std::vector<std::pair<const char*, float>> values;
        };
        static const std::array<PresetData, N> presets; // N = number of presets
        int currentPreset = 0;
        ```

        ### In PluginProcessor.cpp — implement the program methods:
        - `getNumPrograms()` → `return N;`
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
        try content.write(to: dir.appendingPathComponent("presets.md"), atomically: true, encoding: .utf8)
    }

    // MARK: - CLAUDE.md (mission brief + kit references)

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

        let presetInstruction = presetCount > 0
            ? "\n- Implement exactly \(presetCount) presets (see `juce-kit/presets.md`)"
            : ""

        let content = """
        # \(pluginName)

        You are an expert C++/JUCE audio plugin developer. Build a fully working
        \(pluginRole) plugin from scratch based on this description:

        > \(config.prompt)

        Channel layout: **\(channelDesc)** | Interface: **\(interfaceDirection)**

        ---

        ## Your mission

        Create all source files from scratch in `Source/`. There are no existing source files —
        you write everything. The only file that exists is `CMakeLists.txt` (do NOT modify it).

        ## Files to create

        | File | What to put in it |
        |---|---|
        | `Source/PluginProcessor.h` | Processor class declaration, member variables\(pluginType == .instrument ? ", Voice + Sound classes" : "") |
        | `Source/PluginProcessor.cpp` | All processor implementations: constructor, createParameterLayout, prepareToPlay, processBlock, state, createEditor, programs |
        | `Source/PluginEditor.h` | Editor class declaration, UI member variables |
        | `Source/PluginEditor.cpp` | Editor constructor (wire controls), paint, resized |
        | `Source/FoundryLookAndFeel.h` | Copy from `juce-kit/look-and-feel.md` (change accentColour only) |

        Class names: **\(pluginName)Processor**, **\(pluginName)Editor** — these are required by CMakeLists.txt.

        ## Knowledge kit

        Read these reference files for patterns and API details:

        | File | Contains |
        |---|---|
        | `juce-kit/juce-api.md` | JUCE API reference: AudioProcessor, APVTS, AudioBuffer, DSP module classes |
        | `juce-kit/dsp-patterns.md` | Correct DSP patterns for \(pluginType.displayName) plugins |
        | `juce-kit/ui-patterns.md` | PluginEditor patterns: sliders, labels, attachments, layout |
        | `juce-kit/look-and-feel.md` | FoundryLookAndFeel — exact code to copy into Source/ |
        | `juce-kit/build-rules.md` | C++17 rules, juce:: namespacing, fatal mistakes to avoid |
        | `juce-kit/presets.md` | JUCE program system for presets |

        ## Workflow

        1. Read the knowledge kit files you need (at minimum: juce-api, dsp-patterns, build-rules, look-and-feel)
        2. Design your parameter layout based on the plugin description
        3. Write `Source/FoundryLookAndFeel.h` (copy from kit, change accent colour)
        4. Write `Source/PluginProcessor.h` — declare the processor class\(pluginType == .instrument ? ", Voice class, Sound class" : "") with all members
        5. Write `Source/PluginProcessor.cpp` — implement all methods with real DSP
        6. Write `Source/PluginEditor.h` — declare UI members matching your parameters
        7. Write `Source/PluginEditor.cpp` — wire all controls, layout in resized()\(presetInstruction)

        ## Design principles

        - Every parameter must audibly change the output
        - Default values must produce a musically useful result
        - Every parameter needs a matching UI control with addAndMakeVisible()
        - Use SmoothedValue for all continuous parameters (prevents clicks)
        - The plugin must compile with C++17 and link against juce_audio_utils + juce_dsp
        """

        try content.write(to: dir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    }
}
