import SwiftUI

// MARK: - Prompt View (New Plugin — v4 design)

struct PromptView: View {
    @Environment(AppState.self) private var appState
    @State private var prompt = ""
    @State private var format: FormatOption = .both
    @State private var channelLayout: ChannelLayout = .stereo
    @State private var presetCount: PresetCount = .five
    @FocusState private var isFocused: Bool

    private let suggestions: [SuggestionCategory] = [
        SuggestionCategory(
            title: "INSTRUMENTS",
            systemImage: "pianokeys",
            items: [
                ("SUBTRACTIVE SYNTH", "Warm analog polysynth with detuned oscillators and a low-pass filter"),
                ("FM ENGINE", "FM pad synth with slow attack, chorus, and stereo spread"),
                ("WAVETABLE OSC", "Wavetable synthesizer with morphable waveforms and built-in effects"),
            ]
        ),
        SuggestionCategory(
            title: "EFFECTS",
            systemImage: "waveform",
            items: [
                ("ALGORITHMIC REVERB", "Algorithmic reverb with room size, damping, and pre-delay"),
                ("TAPE DELAY", "Lo-fi tape delay with wow, flutter, and saturation"),
                ("BITCRUSHER", "Bitcrusher with sample rate reduction and dithering"),
            ]
        ),
        SuggestionCategory(
            title: "UTILITIES",
            systemImage: "dial.low",
            items: [
                ("MODULATION MATRIX", "Flexible modulation matrix with multiple sources and destinations"),
                ("STEP SEQUENCER", "8-step sequencer with rate, swing, and gate controls"),
                ("ADSR ENVELOPE", "ADSR envelope follower with output level and retrigger"),
            ]
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            FoundryHeaderBar(
                onLogoTap: { appState.popToRoot() }
            ) {
                HStack(spacing: FoundryTheme.Spacing.lg) {
                    if let building = appState.plugins.first(where: { $0.status == .building }) {
                        BuildingIndicator(name: building.name)
                    }

                    FoundryActionButton(
                        title: "GENERATE",
                        action: generate,
                        isDisabled: prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }

            GeometryReader { geo in
                ScrollView {
                    HStack(spacing: 0) {
                        Spacer(minLength: 128)
                        contentCanvas
                            .frame(maxWidth: 1024)
                        Spacer(minLength: 128)
                    }
                    .frame(minHeight: geo.size.height)
                    .padding(.vertical, FoundryTheme.Spacing.xxxl)
                }
            }
            .background(FoundryTheme.Colors.background)

        }
        .background(FoundryTheme.Colors.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden)
        .onAppear { isFocused = true }
    }

    // MARK: - Content Canvas

    private var contentCanvas: some View {
        VStack(alignment: .leading, spacing: 0) {
            promptSection
                .padding(.bottom, FoundryTheme.Spacing.xxl)

            categoryGrid
                .padding(.bottom, FoundryTheme.Spacing.xxxl)

            Spacer(minLength: 0)

            configRow
        }
        .padding(.horizontal, FoundryTheme.Spacing.xl)
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: FoundryTheme.Spacing.xs) {
            Text("Natural Language Prompt")
                .font(FoundryTheme.Fonts.jetBrainsMono(10))
                .tracking(1)
                .foregroundStyle(FoundryTheme.Colors.textSecondary)
                .textCase(.uppercase)

            promptTextarea
        }
    }

    private var promptTextarea: some View {
        ZStack(alignment: .topLeading) {
            FoundryTheme.Colors.backgroundDeep

            if prompt.isEmpty {
                Text("Describe the sound architecture... (e.g., A dual-oscillator subtractive synth with a ladder filter and gritty tape saturation stage)")
                    .font(FoundryTheme.Fonts.inter(20))
                    .lineSpacing(8)
                    .foregroundStyle(FoundryTheme.Colors.borderSubtle.opacity(0.3))
                    .allowsHitTesting(false)
                    .padding(FoundryTheme.Spacing.lg)
            }

            TextEditor(text: $prompt)
                .font(FoundryTheme.Fonts.inter(20))
                .lineSpacing(8)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundStyle(.white)
                .focused($isFocused)
                .padding(FoundryTheme.Spacing.lg - 5)
        }
        .frame(height: 180)
        .foundryBorder()
        .cornerBrackets()
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        HStack(alignment: .top, spacing: FoundryTheme.Spacing.lg) {
            ForEach(suggestions) { cat in
                SuggestionCategoryCard(category: cat) { item in
                    withAnimation(.easeOut(duration: 0.12)) {
                        prompt = item.fullPrompt
                    }
                }
            }
        }
    }

    // MARK: - Config Row

    private var configRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(FoundryTheme.Colors.border)
                .frame(height: 1)

            HStack(alignment: .center) {
                HStack(spacing: FoundryTheme.Spacing.xxxl) {
                    configSelector(
                        label: "FORMAT",
                        options: FormatOption.allCases.map { $0.rawValue.uppercased() },
                        selected: format.rawValue.uppercased()
                    ) { cycleFormat() }

                    configSelector(
                        label: "CHANNELS",
                        options: ChannelLayout.allCases.map { $0.rawValue.uppercased() },
                        selected: channelLayout.rawValue.uppercased()
                    ) { cycleChannels() }

                    configSelector(
                        label: "PRESETS",
                        options: [PresetCount.zero, .five, .ten].map { "\($0.rawValue)" },
                        selected: "\(presetCount.rawValue)"
                    ) { cyclePresets() }
                }

                Spacer()

                Button { appState.push(.quickOptions(prompt: prompt)) } label: {
                    HStack(spacing: FoundryTheme.Spacing.md) {
                        Text("Adv. Options")
                            .font(FoundryTheme.Fonts.jetBrainsMono(10))
                            .tracking(1)
                            .foregroundStyle(FoundryTheme.Colors.textSecondary)
                            .textCase(.uppercase)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                            .foregroundStyle(FoundryTheme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 21)
                    .padding(.vertical, 11)
                    .foundryBorder(background: FoundryTheme.Colors.backgroundToolbar)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, FoundryTheme.Spacing.xl)
            .padding(.bottom, FoundryTheme.Spacing.xxl)
        }
    }

    private func configSelector(
        label: String,
        options: [String],
        selected: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: FoundryTheme.Spacing.xs) {
            Text(label)
                .font(FoundryTheme.Fonts.jetBrainsMono(9))
                .tracking(2.7)
                .foregroundStyle(FoundryTheme.Colors.textSecondary)

            Button(action: action) {
                HStack(spacing: 4) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                        if idx > 0 {
                            Text("/")
                                .font(FoundryTheme.Fonts.jetBrainsMono(12))
                                .foregroundStyle(FoundryTheme.Colors.textDimmed)
                        }
                        Text(option)
                            .font(FoundryTheme.Fonts.jetBrainsMono(12))
                            .foregroundStyle(option == selected ? .white : FoundryTheme.Colors.textDimmed)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Cycle Actions

    private func cycleFormat() {
        let cases = FormatOption.allCases
        let idx = cases.firstIndex(of: format)!
        format = cases[(idx + 1) % cases.count]
    }

    private func cycleChannels() {
        channelLayout = channelLayout == .mono ? .stereo : .mono
    }

    private func cyclePresets() {
        let cases = PresetCount.allCases
        let idx = cases.firstIndex(of: presetCount)!
        presetCount = cases[(idx + 1) % cases.count]
    }

    private func generate() {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appState.push(.generation(config: GenerationConfig(
            prompt: prompt,
            format: format,
            channelLayout: channelLayout,
            presetCount: presetCount
        )))
    }
}

// MARK: - Suggestion Category Card

struct SuggestionCategoryCard: View {
    let category: SuggestionCategory
    let onSelect: (SuggestionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FoundryTheme.Spacing.lg) {
            HStack(spacing: FoundryTheme.Spacing.sm) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)

                Text(category.title)
                    .font(FoundryTheme.Fonts.azeretMono(12))
                    .tracking(2.4)
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: FoundryTheme.Spacing.md) {
                ForEach(category.items, id: \.display) { item in
                    Button { onSelect(item) } label: {
                        HStack {
                            Text(item.display)
                                .font(FoundryTheme.Fonts.jetBrainsMono(11))
                                .tracking(-0.275)
                                .foregroundStyle(FoundryTheme.Colors.textSecondary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 7, weight: .regular))
                                .foregroundStyle(FoundryTheme.Colors.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(25)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .foundryBorder()
    }
}

// MARK: - Data Models

struct SuggestionCategory: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let items: [SuggestionItem]
}

struct SuggestionItem {
    let display: String
    let fullPrompt: String
}

extension SuggestionCategory {
    init(title: String, systemImage: String, items: [(String, String)]) {
        self.title = title
        self.systemImage = systemImage
        self.items = items.map { SuggestionItem(display: $0.0, fullPrompt: $0.1) }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PromptView()
    }
    .environment({
        let s = AppState()
        s.plugins = Plugin.samplePlugins
        return s
    }())
    .preferredColorScheme(.dark)
}
