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

    static func assemble(config: GenerationConfig, pluginName: String) throws -> AssembledProject {
        let fm = FileManager.default
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

        Subclass as `\(pluginName)Processor`. Key overrides:

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

        // State
        void getStateInformation(juce::MemoryBlock& destData) override;
        void setStateInformation(const void* data, int sizeInBytes) override;
        ```

        ## APVTS (AudioProcessorValueTreeState)

        Thread-safe parameter system. Initialize: `apvts(*this, nullptr, "PARAMETERS", createParameterLayout())`

        ```cpp
        // Parameter types
        juce::AudioParameterFloat(juce::ParameterID{"id", 1}, "Name",
            juce::NormalisableRange<float>(min, max, step, skew), defaultValue);
        juce::AudioParameterChoice(juce::ParameterID{"id", 1}, "Name",
            juce::StringArray{"A", "B", "C"}, defaultIndex);
        juce::AudioParameterBool(juce::ParameterID{"id", 1}, "Name", defaultValue);
        juce::AudioParameterInt(juce::ParameterID{"id", 1}, "Name", min, max, defaultValue);

        // Read (audio-thread safe)
        float val = apvts.getRawParameterValue("id")->load();

        // State save
        auto state = apvts.copyState();
        std::unique_ptr<juce::XmlElement> xml(state.createXml());
        copyXmlToBinary(*xml, destData);

        // State load
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

        ## Effect: processBlock essentials

        Every effect processBlock starts with:
        ```cpp
        juce::ScopedNoDenormals noDenormals;
        for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
            buffer.clear(i, 0, buffer.getNumSamples());
        ```

        Then choose the DSP architecture that best serves THIS specific plugin:

        ### Architecture 1 — Serial chain
        Input → stage A → stage B → stage C → output. Good for: channel strips, multi-stage distortion, EQ chains.
        ```cpp
        // Process each stage in sequence on the buffer
        stageA.process(context); stageB.process(context); stageC.process(context);
        ```

        ### Architecture 2 — Parallel paths with mix
        Split input into two (or more) processed paths, blend results. Good for: parallel compression, chorus, multi-band.
        ```cpp
        dryBuffer.makeCopyOf(buffer);
        // Process buffer (wet path), then blend: out = dry * (1-mix) + wet * mix
        ```

        ### Architecture 3 — Feedback loop
        Output feeds back into input with a coefficient < 1.0. Good for: delay, reverb, flanger, comb filter.
        ```cpp
        // Write to delay line, read from it, mix with feedback coefficient
        delayLine.pushSample(ch, inputSample + feedback * delayLine.popSample(ch, delayTime));
        ```

        ### Architecture 4 — Modulated parameters
        An LFO or envelope controls DSP parameters over time. Good for: auto-wah, tremolo, phaser, vibrato.
        ```cpp
        float lfo = std::sin(lfoPhase * twoPi); lfoPhase += lfoRate / sampleRate;
        filter.setCutoffFrequency(baseCutoff * (1.0f + depth * lfo));
        ```

        ### Architecture 5 — Envelope follower
        Track input amplitude, use it to drive a parameter. Good for: auto-gain, dynamic EQ, ducking, compressor-style effects.
        ```cpp
        float env = std::abs(sample); envelope += (env > envelope ? attackCoeff : releaseCoeff) * (env - envelope);
        ```

        Combine architectures freely. A phaser is a serial chain with modulated all-pass filters. A ping-pong delay is a feedback loop with channel swapping.

        ## prepareToPlay essentials
        - Create a `juce::dsp::ProcessSpec` with sampleRate, samplesPerBlock, numChannels
        - Call `.prepare(spec)` on all juce::dsp objects
        - Call `.reset(sampleRate, 0.02)` on all SmoothedValue members
        - Store sampleRate for LFO/modulation calculations
        """

        let instrumentPatterns = """
        # DSP Patterns

        ## Instrument: Synthesiser + Voice architecture

        ### Processor processBlock (structural — always this shape)
        ```cpp
        juce::ScopedNoDenormals noDenormals;
        buffer.clear();
        synth.renderNextBlock(buffer, midiMessages, 0, buffer.getNumSamples());
        // Then apply master-level processing (level, master filter, effects, etc.)
        ```

        ### prepareToPlay
        Call `synth.setCurrentPlaybackSampleRate(sampleRate)`, then iterate voices with `dynamic_cast` to call each voice's prepare method.

        ### Voice rules (non-negotiable)
        - Allocate 8 voices in the constructor
        - Use `buffer.addSample()` (not setSample) — voices are mixed additively
        - Check `isVoiceActive()` at the top of renderNextBlock
        - Call `clearCurrentNote()` when the amplitude envelope finishes
        - Use `juce::ADSR` for envelopes (handles sample-accurate note-on/off)
        - Access processor parameters via a stored pointer, not globals
        - Filters and envelopes must be per-voice for polyphonic correctness

        ## Choose your synthesis approach

        Pick based on what the plugin description calls for:

        - **Subtractive**: Oscillator(s) → filter → amplifier. Classic analog sound. Use polyBLEP oscillators + StateVariableTPTFilter.
        - **FM**: Modulator oscillator controls carrier frequency. Metallic, bell-like, evolving timbres.
        - **Additive**: Sum of sine partials with independent amplitudes. Organ-like, pad textures.
        - **Wavetable-style**: Lookup table with interpolation, morph between wave shapes. Rich, evolving sounds.
        - **Noise-based**: Filtered noise + envelopes. Percussive hits, wind, textures.

        Combine freely — most real synths mix approaches (e.g., subtractive + FM modulation + noise layer).

        ## Synthesis building blocks

        ### Anti-aliased oscillators (polyBLEP)
        ```cpp
        static double polyBlep(double t, double dt) {
            if (t < dt) { t /= dt; return t + t - t * t - 1.0; }
            if (t > 1.0 - dt) { t = (t - 1.0) / dt; return t * t + t + t + 1.0; }
            return 0.0;
        }
        // Saw: 2*phase - 1, subtract polyBlep(phase, dt)
        // Square: (phase < 0.5) ? 1 : -1, add polyBlep at 0 and 0.5
        // Triangle: 2*fabs(2*phase - 1) - 1 (smooth, no BLEP needed)
        // Sine: std::sin(phase * twoPi)
        ```

        ### Detuning
        ```cpp
        double freq2 = frequency * std::pow(2.0, detuneCents / 1200.0);
        ```

        ### Per-voice filtering
        `juce::dsp::StateVariableTPTFilter<float>` — prepare with maximumBlockSize=1, use `processSample(ch, sample)`.

        ### Multiple envelopes
        `juce::ADSR ampEnv, filterEnv;` — amplitude controls volume, filter envelope modulates cutoff, pitch envelope for plucks/kicks.

        ### LFO
        ```cpp
        float lfo = std::sin(lfoPhase * twoPi);
        lfoPhase += lfoRate / sampleRate; if (lfoPhase >= 1.0) lfoPhase -= 1.0;
        ```

        ### FM synthesis
        ```cpp
        double mod = std::sin(modPhase * twoPi) * fmDepth * modFreq;
        double carrier = std::sin((carrierPhase + mod / sampleRate) * twoPi);
        ```

        ### Noise + sub
        ```cpp
        float noise = random.nextFloat() * 2.0f - 1.0f;
        float sub = std::sin(phase * 0.5 * twoPi);
        ```
        """

        let utilityPatterns = """
        # DSP Patterns

        ## Utility: processBlock essentials

        Start with:
        ```cpp
        juce::ScopedNoDenormals noDenormals;
        for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
            buffer.clear(i, 0, buffer.getNumSamples());
        ```

        Then implement the utility's specific processing. Read parameters via SmoothedValue, process per-channel per-sample.

        ## Utility-specific rules
        - Use `juce::Decibels::decibelsToGain()` / `gainToDecibels()` for all gain parameters
        - Gain range: typically -60 dB to +12 dB, default 0 dB (unity)
        - Width range: 0% (mono) to 200% (wide), default 100% (unchanged)
        - Phase parameters are boolean (invert or not)
        - Default settings = no audible change (transparent utility)
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

        Design a layout that reflects the plugin's purpose and signal flow. Use `getLocalBounds().reduced(...)` and `removeFromTop/Left/Right/Bottom` to carve areas. Approaches:

        - **Centered row**: All knobs in one horizontal row, centered. Best for 3-4 controls (simple effects, utilities).
        - **Sectioned panels**: Divide into named groups (Input | Processing | Output) using `removeFromLeft`. Good for channel strips, multi-stage effects.
        - **Header + main area**: Top bar with plugin name and mode/preset selector, main area below for primary controls.
        - **Left-right split**: Input controls left, output/mix right, core processing center. Mirrors signal flow.
        - **Grid**: Arrange controls in rows and columns. Good for synths with many parameters.

        Match the spatial arrangement to the signal flow. A delay plugin might flow left→right (input→time→feedback→mix). A synth might have oscillators on top, filter in the middle, amp at the bottom.

        ## Custom painting

        Override `paint(juce::Graphics& g)` to draw beyond plain backgrounds: section dividers, gradient backgrounds, subtle labels for control groups, or decorative elements that reinforce the plugin's character.

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
        # LookAndFeel — Visual Design Reference

        Design a unique `FoundryLookAndFeel` class that gives this plugin its own visual identity.
        Subclass `juce::LookAndFeel_V4` in a header-only `FoundryLookAndFeel.h`.

        ## Color palette

        Define 5-7 named `juce::Colour` members. Choose colors that reflect the plugin's sonic character:

        - **Warm amber** (saturation, distortion, tape): background 0xff0d0a07, accent 0xffc8935a
        - **Cool blue** (delay, reverb, space): background 0xff070a0d, accent 0xff5a8ec8
        - **Earth green** (dynamics, compression): background 0xff070d0a, accent 0xff5ac870
        - **Violet** (modulation, chorus, phaser): background 0xff0a070d, accent 0xff8a6abf
        - **Copper/red** (vintage, analog character): background 0xff0d0907, accent 0xffc07050

        Pick or blend based on the plugin description. Do NOT default to grey (0xffc0c0c0).

        ## Required colour IDs

        Your constructor must call `setColour()` for ALL of these — missing any causes visual bugs:

        ```
        ResizableWindow::backgroundColourId
        Slider::rotarySliderFillColourId, rotarySliderOutlineColourId, thumbColourId
        Slider::trackColourId, backgroundColourId, textBoxTextColourId, textBoxOutlineColourId
        Label::textColourId
        ComboBox::backgroundColourId, outlineColourId, textColourId
        TextButton::buttonColourId, textColourOffId
        ToggleButton::textColourId, tickColourId
        PopupMenu::backgroundColourId, textColourId, highlightedBackgroundColourId, highlightedTextColourId
        ```

        ## Knob styles — pick or invent

        Override `drawRotarySlider(juce::Graphics& g, int x, int y, int width, int height, float sliderPos, float rotaryStartAngle, float rotaryEndAngle, juce::Slider&)`:

        **Arc + indicator line**: Draw a background circle, an accent-colored arc from start to current angle, and a line from center to the arc edge.

        **Filled dot**: Draw a filled circle for the knob body, a small dot at the arc edge as position indicator. Clean, modern.

        **Minimal arc only**: No background circle. Just a thick accent arc from start to current angle. Ultra-minimal.

        Choose or combine. The goal is a look that matches the plugin's personality.

        ## Linear slider

        Override `drawLinearSlider(...)`. For `LinearHorizontal`: draw a thin track line and fill from left to slider position with accent color. Fall back to `LookAndFeel_V4::drawLinearSlider` for other styles.

        ## Button background

        Override `drawButtonBackground(...)`. Draw a rounded rectangle with subtle brightness changes for hover/down states.

        ## Label font

        Override `getLabelFont(juce::Label&)` — return `juce::Font(juce::FontOptions(13.0f))`.

        ## Visual rules
        - Dark background. One or two muted accent colours — not neon.
        - No emojis, no "AI" branding.
        - Group controls into named sections when there are more than 4 parameters.
        - Labels: uppercase, small font (10-11pt), dim text colour.
        - Window sizes: Focused ~400x300, Balanced ~600x400, Exploratory ~800x500

        ## CRITICAL: LookAndFeel lifecycle
        - Editor constructor: `setLookAndFeel(&lookAndFeel);`
        - Editor destructor: `~MyEditor() override { setLookAndFeel(nullptr); }` — MANDATORY or crash
        - Do NOT use `= default;` for the editor destructor
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
        - `FoundryLookAndFeel.h` — Your custom LookAndFeel (see juce-kit/look-and-feel.md for API reference)

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

        ### 11. Hardcoded sample rate
        ```cpp
        // FATAL — assumes 44100:
        float delayInSamples = 0.5f * 44100.0f;
        // CORRECT — use stored sampleRate from prepareToPlay:
        float delayInSamples = 0.5f * storedSampleRate;
        ```

        ### 12. Division by zero in DSP
        Guard all divisions where the denominator can be zero (delay time, frequency, etc.):
        ```cpp
        float freq = juce::jmax(paramFreq, 0.001f); // never zero
        ```
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
        Name presets to evoke their sonic character (e.g., "Warm Tape", "Crystal Air", "Fat Growl") — not generic labels like "Preset 1".
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
        | `Source/FoundryLookAndFeel.h` | Design a unique LookAndFeel using `juce-kit/look-and-feel.md` as API reference |

        Class names: **\(pluginName)Processor**, **\(pluginName)Editor** — these are required by CMakeLists.txt.

        ## Knowledge kit

        Read these reference files for patterns and API details:

        | File | Contains |
        |---|---|
        | `juce-kit/juce-api.md` | JUCE API reference: AudioProcessor, APVTS, AudioBuffer, DSP module classes |
        | `juce-kit/dsp-patterns.md` | Correct DSP patterns for \(pluginType.displayName) plugins |
        | `juce-kit/ui-patterns.md` | PluginEditor patterns: sliders, labels, attachments, layout |
        | `juce-kit/look-and-feel.md` | LookAndFeel API reference — color palettes, knob styles, visual design patterns |
        | `juce-kit/build-rules.md` | C++17 rules, juce:: namespacing, fatal mistakes to avoid |
        | `juce-kit/presets.md` | JUCE program system for presets |

        ## Workflow

        1. Read the knowledge kit files you need (at minimum: juce-api, dsp-patterns, build-rules, look-and-feel)
        2. Design your parameter layout based on the plugin description
        3. Write `Source/FoundryLookAndFeel.h` — design a unique visual identity matching the plugin's character
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

        ## Creative direction

        Make this plugin visually and sonically **distinct**:
        - Choose a color palette that reflects the plugin's sonic character (warm for saturation, cool for spatial effects, etc.)
        - Design knob and slider styles that feel unique — do NOT produce a generic dark-grey plugin
        - Arrange the layout to mirror the signal flow or interaction model
        - The DSP architecture should serve this specific plugin's purpose — do not default to a generic dry/wet pattern
        """

        try content.write(to: dir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    }
}
