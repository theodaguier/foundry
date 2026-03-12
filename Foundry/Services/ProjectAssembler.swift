import Foundation

enum ProjectAssembler {

    struct AssembledProject {
        let directory: URL
        let pluginName: String
        let isSynth: Bool
    }

    // MARK: - Assemble

    static func assemble(config: GenerationConfig) throws -> AssembledProject {
        let fm = FileManager.default

        // Generate a clean plugin name from the prompt
        let pluginName = generatePluginName(from: config.prompt)
        let isSynth = detectPluginType(from: config.prompt)

        // Create temp directory
        let uuid = UUID().uuidString.prefix(8).lowercased()
        let projectDir = URL(fileURLWithPath: "/tmp/foundry-build-\(uuid)")
        let sourceDir = projectDir.appendingPathComponent("Source")
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        // Write all template files
        try writeCMakeLists(to: projectDir, pluginName: pluginName, isSynth: isSynth, config: config)
        try writeProcessor(to: sourceDir, pluginName: pluginName, isSynth: isSynth, config: config)
        try writeEditor(to: sourceDir, pluginName: pluginName)
        try writeLookAndFeel(to: sourceDir)
        try writeClaudeMD(to: projectDir, pluginName: pluginName, isSynth: isSynth, config: config)

        return AssembledProject(directory: projectDir, pluginName: pluginName, isSynth: isSynth)
    }

    // MARK: - Plugin name generation

    private static func generatePluginName(from prompt: String) -> String {
        // Take first few meaningful words, PascalCase them — keep short for JUCE path limits
        let stopWords: Set<String> = ["a", "an", "the", "with", "and", "or", "for", "that", "like", "style", "based", "type"]
        let words = prompt
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty && !stopWords.contains($0.lowercased()) }
            .prefix(2)
            .map { String($0.prefix(8)).prefix(1).uppercased() + String($0.prefix(8)).dropFirst().lowercased() }

        var name = words.joined()
        if name.isEmpty { name = "FndryPlg" }
        // Cap at 16 chars to avoid JUCE path length issues
        return String(name.prefix(16))
    }

    private static func detectPluginType(from prompt: String) -> Bool {
        let synthKeywords = ["synth", "synthesizer", "oscillator", "polyphon", "monophon", "keys", "pad", "lead", "bass synth", "arpeggiator"]
        let lower = prompt.lowercased()
        return synthKeywords.contains { lower.contains($0) }
    }

    // MARK: - Template writers

    private static func writeCMakeLists(to dir: URL, pluginName: String, isSynth: Bool, config: GenerationConfig) throws {
        let jucePath = DependencyChecker.jucePath
        let pluginCode = String(pluginName.prefix(4).uppercased().padding(toLength: 4, withPad: "x", startingAt: 0))

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
            IS_SYNTH \(isSynth ? "TRUE" : "FALSE")
            NEEDS_MIDI_INPUT \(isSynth ? "TRUE" : "FALSE")
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

    private static func writeProcessor(to dir: URL, pluginName: String, isSynth: Bool, config: GenerationConfig) throws {
        let numChannels = config.channelLayout == .stereo ? 2 : 1
        let busLayout = config.channelLayout == .stereo
            ? "juce::AudioChannelSet::stereo()"
            : "juce::AudioChannelSet::mono()"

        // Header
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
            bool acceptsMidi() const override { return \(isSynth ? "true" : "false"); }
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

            // TODO: Add DSP member variables here

            JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(\(pluginName)Processor)
        };
        """
        try header.write(to: dir.appendingPathComponent("PluginProcessor.h"), atomically: true, encoding: .utf8)

        // Implementation
        let impl = """
        #include "PluginProcessor.h"
        #include "PluginEditor.h"

        \(pluginName)Processor::\(pluginName)Processor()
            : AudioProcessor(BusesProperties()
        \(isSynth
            ? "        .withOutput(\"Output\", \(busLayout), true)"
            : "        .withInput(\"Input\", \(busLayout), true)\n        .withOutput(\"Output\", \(busLayout), true)")
              ),
              apvts(*this, nullptr, "PARAMETERS", createParameterLayout())
        {
        }

        \(pluginName)Processor::~\(pluginName)Processor() {}

        juce::AudioProcessorValueTreeState::ParameterLayout \(pluginName)Processor::createParameterLayout()
        {
            std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;

            // TODO: Add parameters here
            // Example:
            // params.push_back(std::make_unique<juce::AudioParameterFloat>(
            //     juce::ParameterID{"gain", 1}, "Gain", 0.0f, 1.0f, 0.5f));

            return { params.begin(), params.end() };
        }

        void \(pluginName)Processor::prepareToPlay(double sampleRate, int samplesPerBlock)
        {
            // TODO: Initialize DSP here
        }

        void \(pluginName)Processor::releaseResources() {}

        void \(pluginName)Processor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
        {
            juce::ScopedNoDenormals noDenormals;
            auto totalNumInputChannels  = getTotalNumInputChannels();
            auto totalNumOutputChannels = getTotalNumOutputChannels();

            for (auto i = totalNumInputChannels; i < totalNumOutputChannels; ++i)
                buffer.clear(i, 0, buffer.getNumSamples());

            // TODO: Implement DSP processing here
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

    private static func writeEditor(to dir: URL, pluginName: String) throws {
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
            juce::Label titleLabel;

            // TODO: Add UI components here (sliders, labels, attachments)

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
            setSize(600, 200);

            titleLabel.setText("\(pluginName)", juce::dontSendNotification);
            titleLabel.setColour(juce::Label::textColourId, FoundryLookAndFeel::dimTextColour);
            titleLabel.setFont(juce::Font(juce::FontOptions(juce::Font::getDefaultMonospacedFontName(), 10.0f, juce::Font::plain)));
            titleLabel.setJustificationType(juce::Justification::centredRight);
            addAndMakeVisible(titleLabel);

            // TODO: Initialize sliders (50x50, RotaryHorizontalVerticalDrag, TextBoxBelow read-only)
            // TODO: Initialize short labels (1-3 char abbreviations, monospace, dimTextColour)
            // TODO: Create attachments (std::make_unique<SliderAttachment>)
        }

        \(pluginName)Editor::~\(pluginName)Editor()
        {
            setLookAndFeel(nullptr);
        }

        void \(pluginName)Editor::paint(juce::Graphics& g)
        {
            g.fillAll(FoundryLookAndFeel::backgroundColour);

            // TODO: Draw group brackets using drawBracket lambda (see CLAUDE.md)
        }

        void \(pluginName)Editor::resized()
        {
            auto area = getLocalBounds().reduced(16);
            titleLabel.setBounds(area.removeFromBottom(14));

            // TODO: Layout knobs in a single horizontal row
            // int numKnobs = N;
            // auto knobWidth = area.getWidth() / numKnobs;
            // for each knob:
            //   auto col = area.removeFromLeft(knobWidth);
            //   label.setBounds(col.removeFromTop(16));
            //   slider.setBounds(col.removeFromTop(50).reduced(4));
        }
        """
        try impl.write(to: dir.appendingPathComponent("PluginEditor.cpp"), atomically: true, encoding: .utf8)
    }

    private static func writeLookAndFeel(to dir: URL) throws {
        let content = """
        #pragma once
        #include <JuceHeader.h>

        //==============================================================================
        // FoundryLookAndFeel — Shared design system for all Foundry-generated plugins.
        // Dark, minimal, Glaze-inspired. DO NOT MODIFY THIS FILE.
        //==============================================================================
        class FoundryLookAndFeel : public juce::LookAndFeel_V4
        {
        public:
            // Colour palette — pure black + white, ultra minimal
            static inline const juce::Colour backgroundColour  { 0xff0a0a0a };
            static inline const juce::Colour surfaceColour     { 0xff1a1a1a };
            static inline const juce::Colour borderColour      { 0xff2a2a2a };
            static inline const juce::Colour textColour        { 0xffd0d0d0 };
            static inline const juce::Colour dimTextColour     { 0xff666666 };
            static inline const juce::Colour accentColour      { 0xffc0c0c0 };
            static inline const juce::Colour knobColour        { 0xff0a0a0a };
            static inline const juce::Colour knobTrackColour   { 0xff2a2a2a };

            FoundryLookAndFeel()
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

            //==============================================================================
            // Rotary slider — thin outline knob, no fill, just arc + indicator
            void drawRotarySlider(juce::Graphics& g, int x, int y, int width, int height,
                                  float sliderPos, float rotaryStartAngle, float rotaryEndAngle,
                                  juce::Slider& slider) override
            {
                auto bounds = juce::Rectangle<int>(x, y, width, height).toFloat().reduced(2.0f);
                auto radius = juce::jmin(bounds.getWidth(), bounds.getHeight()) / 2.0f;
                auto centreX = bounds.getCentreX();
                auto centreY = bounds.getCentreY();
                auto angle = rotaryStartAngle + sliderPos * (rotaryEndAngle - rotaryStartAngle);

                // Outer ring — thin circle outline
                g.setColour(knobTrackColour);
                g.drawEllipse(centreX - radius, centreY - radius,
                              radius * 2.0f, radius * 2.0f, 1.0f);

                // Active arc
                juce::Path fill;
                fill.addCentredArc(centreX, centreY, radius, radius,
                                    0.0f, rotaryStartAngle, angle, true);
                g.setColour(accentColour);
                g.strokePath(fill, juce::PathStrokeType(1.5f, juce::PathStrokeType::curved,
                                                         juce::PathStrokeType::rounded));

                // Indicator line from center outward
                juce::Path indicator;
                indicator.startNewSubPath(centreX, centreY);
                indicator.lineTo(centreX + (radius - 4.0f) * std::sin(angle),
                                 centreY - (radius - 4.0f) * std::cos(angle));
                g.setColour(accentColour);
                g.strokePath(indicator, juce::PathStrokeType(1.5f));
            }

            //==============================================================================
            // Linear slider
            void drawLinearSlider(juce::Graphics& g, int x, int y, int width, int height,
                                  float sliderPos, float /*minSliderPos*/, float /*maxSliderPos*/,
                                  juce::Slider::SliderStyle style, juce::Slider& slider) override
            {
                if (style == juce::Slider::LinearHorizontal)
                {
                    auto trackY = (float)y + (float)height * 0.5f;
                    g.setColour(knobTrackColour);
                    g.fillRoundedRectangle((float)x, trackY - 1.0f, (float)width, 2.0f, 1.0f);
                    g.setColour(accentColour);
                    g.fillRoundedRectangle((float)x, trackY - 1.0f, sliderPos - (float)x, 2.0f, 1.0f);
                    g.setColour(accentColour);
                    g.drawEllipse(sliderPos - 4.0f, trackY - 4.0f, 8.0f, 8.0f, 1.0f);
                }
                else
                {
                    LookAndFeel_V4::drawLinearSlider(g, x, y, width, height,
                                                      sliderPos, 0, 0, style, slider);
                }
            }

            //==============================================================================
            // Label — small monospace font
            juce::Font getLabelFont(juce::Label&) override
            {
                return juce::Font(juce::FontOptions(juce::Font::getDefaultMonospacedFontName(), 11.0f, juce::Font::plain));
            }

            //==============================================================================
            // Button — outline only, no fill
            void drawButtonBackground(juce::Graphics& g, juce::Button& button,
                                       const juce::Colour& /*backgroundColour*/,
                                       bool isHighlighted, bool isDown) override
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

    // MARK: - CLAUDE.md (system prompt for Claude Code)

    private static func writeClaudeMD(to dir: URL, pluginName: String, isSynth: Bool, config: GenerationConfig) throws {
        let pluginType = isSynth ? "synthesizer" : "audio effect"
        let channelDesc = config.channelLayout == .stereo ? "stereo" : "mono"

        let content = """
        # \(pluginName) — JUCE Plugin Project

        You are an expert audio DSP engineer building a professional JUCE audio plugin.
        This is a **\(pluginType)** plugin.

        ## Project Structure

        ```
        Source/
        ├── PluginProcessor.h/cpp   ← Audio processing (DSP) — EDIT THIS
        ├── PluginEditor.h/cpp      ← Plugin UI — EDIT THIS
        └── FoundryLookAndFeel.h    ← Design system — DO NOT MODIFY
        CMakeLists.txt              ← Build config — DO NOT MODIFY
        ```

        ## Your Task

        Build a **professional-quality, musically useful** \(pluginType) plugin:
        **\(config.prompt)**

        Channel layout: **\(channelDesc)**
        \(config.presetCount.rawValue > 0 ? "Number of presets: **\(config.presetCount.rawValue)**" : "")

        The plugin must sound good out of the box with sensible default parameter values.
        A user should be able to load it and immediately get a usable, musical result.

        ## Rules (MUST follow)

        1. **Only edit** `PluginProcessor.h`, `PluginProcessor.cpp`, `PluginEditor.h`, `PluginEditor.cpp`
        2. **DO NOT** modify `CMakeLists.txt` or `FoundryLookAndFeel.h`
        3. **DO NOT** add external dependencies — use only JUCE built-in classes
        4. **DO NOT** create new files
        5. The plugin **must compile** with JUCE and C++17

        ## DSP Guidelines — MUST SOUND PROFESSIONAL

        Think like an audio engineer. The DSP must be correct, stable, and musically useful.

        ### Signal flow fundamentals:
        - **Dry/wet mix**: effects MUST have a mix parameter. Blend dry (original) and wet (processed) signals.
        - **Output gain**: always include a final output gain stage to avoid clipping.
        - **Parameter smoothing**: use `juce::SmoothedValue<float>` for ALL parameters read in processBlock() to avoid zipper noise / clicks.
        - **Sample rate awareness**: all time-based parameters (delay, attack, release, LFO rate) must scale correctly with sample rate.
        - **Sensible defaults**: default values should produce an immediately audible, pleasant effect — not silence, not noise, not distortion.

        ### Parameter ranges (use these as reference):
        - Gain/Volume: 0.0 to 1.0 (default 0.5–0.8)
        - Mix (dry/wet): 0.0 to 1.0 (default 0.3–0.5)
        - Frequency (filter): 20.0 to 20000.0 Hz, **skew 0.3** for logarithmic feel
        - Resonance/Q: 0.1 to 10.0 (default 0.707)
        - Delay time: 0.01 to 2.0 seconds (default 0.25–0.5)
        - Feedback: 0.0 to 0.95 (NEVER >= 1.0, causes infinite feedback)
        - Attack/Release: 0.001 to 5.0 seconds
        - LFO rate: 0.1 to 20.0 Hz (default 1.0–3.0)
        - LFO depth: 0.0 to 1.0 (default 0.3–0.5)

        ### JUCE DSP classes to use:
        - `juce::dsp::IIR::Filter` + `juce::dsp::IIR::Coefficients` for filters
        - `juce::dsp::DelayLine<float>` for delays (set max delay in prepareToPlay)
        - `juce::dsp::Reverb` with `juce::dsp::Reverb::Parameters` for reverb
        - `juce::dsp::Chorus<float>` for chorus
        - `juce::dsp::Compressor<float>` for compression
        - `juce::dsp::WaveShaper<float>` for saturation/distortion
        - `juce::dsp::Gain<float>` for gain stages
        - `juce::dsp::Oscillator<float>` for LFOs and synth oscillators
        - `juce::dsp::ProcessSpec` to pass sample rate and block size
        - `juce::dsp::AudioBlock<float>` and `juce::dsp::ProcessContextReplacing` for processing

        ### Architecture:
        - Initialize ALL DSP objects in `prepareToPlay()` with correct sample rate
        - Read parameter values at the START of `processBlock()` using `apvts.getRawParameterValue("id")->load()`
        - Process audio sample-by-sample or block-by-block depending on the algorithm
        - Apply dry/wet mix at the END of processBlock()

        \(isSynth ? """
        ### Synth-specific:
        - Use `juce::Synthesiser` with custom `juce::SynthesiserVoice` subclass
        - Implement `renderNextBlock()` in the voice — generate audio sample by sample
        - Voices must handle noteOn, noteOff, pitchWheel
        - Add at least: oscillator, amplitude envelope (ADSR), filter with envelope
        - Use `juce::ADSR` for envelopes
        - Add 8 voices minimum for polyphony
        - The synth must produce musical output immediately when MIDI notes are received
        """ : """
        ### Effect-specific:
        - Process audio IN-PLACE in the buffer
        - Always preserve the dry signal for dry/wet mixing
        - Copy input buffer before processing if needed: `juce::AudioBuffer<float> dryBuffer; dryBuffer.makeCopyOf(buffer);`
        - At the end: `buffer.applyGain(wetLevel); for (ch) buffer.addFrom(ch, 0, dryBuffer, ch, 0, numSamples, dryLevel);`
        """)

        ## UI Guidelines — MINIMAL & FUNCTIONAL

        The UI must be **dark, clean, minimal, and functional**. The LookAndFeel handles all visual styling.

        ### Principles:
        - Every parameter gets a knob (rotary slider) with a readable label below it
        - Layout adapts to the number of parameters — use the space wisely
        - The plugin name appears at the top or bottom, small and subtle
        - The UI must be immediately understandable: a producer should see the knobs and know what they do

        ### Layout:
        - Window: 600 wide, height adapts (200 for ≤8 params, 300 for more)
        - Knobs: `juce::Slider` with `RotaryHorizontalVerticalDrag`, size 60×60
        - Text box below each knob: `setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16)`
        - Label below text box: short but readable name (e.g. "Mix", "Delay", "Freq", "Gain", "Rate")
        - Arrange in rows — up to 6-8 knobs per row, evenly spaced
        - Use `getLocalBounds().reduced(20)` and `removeFromTop/Left` for layout
        - Group related params visually by spacing (leave a gap between groups)

        ### Component pattern (MUST follow):
        ```cpp
        // Header private section — for EACH parameter:
        juce::Slider mixSlider;
        juce::Label mixLabel;
        std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> mixAttachment;

        // Constructor body:
        mixSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
        mixSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 60, 16);
        addAndMakeVisible(mixSlider);
        mixAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment>(
            processorRef.apvts, "mix", mixSlider);

        mixLabel.setText("Mix", juce::dontSendNotification);
        mixLabel.setJustificationType(juce::Justification::centred);
        addAndMakeVisible(mixLabel);
        ```

        ### What NOT to do:
        - No GroupBox, no TabbedComponent, no nested panels
        - No custom drawing beyond fillAll with background colour
        - No images, no gradients, no bright colors
        - **NEVER leave the editor empty** — every parameter MUST have a visible knob

        \(config.presetCount.rawValue > 0 ? """
        ## Presets

        Implement \(config.presetCount.rawValue) factory presets with musically useful values.
        Each preset should sound distinctly different and be immediately usable.
        Store presets as named parameter value sets. Provide a method to load them.
        State save/restore via APVTS is already implemented.
        """ : "")

        ## Compilation — Common Errors to Avoid

        - **Always fully qualify JUCE types**: `juce::Slider`, `juce::Label`, `juce::AudioParameterFloat`, etc.
        - **Header/cpp must match**: every method declared in .h must be implemented in .cpp
        - **Member variables in header**: declare ALL sliders, labels, attachments, DSP objects in the header `private:` section
        - **Attachments after addAndMakeVisible**: create `std::make_unique<SliderAttachment>(...)` AFTER calling `addAndMakeVisible()` on the slider
        - **Parameter IDs must match exactly** between `createParameterLayout()` and attachment constructors
        - **Do not use `juce::Font(float)`** — deprecated. Use `juce::Font(juce::FontOptions(float))`
        - **Do not call `addAndMakeVisible` in member initializer lists** — call it in the constructor body
        - **ProcessorChain**: all processors must be default-constructible
        - **SmoothedValue**: call `.reset(sampleRate, rampTimeSeconds)` in `prepareToPlay()`

        ## Final Checklist

        Before finishing, verify:
        1. ✓ All TODO comments replaced with real code
        2. ✓ Every parameter has a UI knob with label and attachment
        3. ✓ DSP produces correct, musical output (not silence, not noise, not clipping)
        4. ✓ Dry/wet mix works correctly
        5. ✓ Default parameter values produce a good sound immediately
        6. ✓ All parameters are smoothed (no clicks/zippers)
        7. ✓ Header and cpp are consistent
        8. ✓ Code compiles with C++17
        """
        try content.write(to: dir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    }
}
