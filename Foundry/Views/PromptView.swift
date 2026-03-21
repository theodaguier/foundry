import SwiftUI

// MARK: - Prompt View (New Plugin — v4 design)

struct PromptView: View {
    @Environment(AppState.self) private var appState
    @State private var prompt = ""
    @State private var selectedModel: AgentModel = ModelCatalog.defaultModel
    @FocusState private var isFocused: Bool

    private var promptEmpty: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
        HStack(spacing: 0) {
            Spacer(minLength: 80)
            contentCanvas
                .frame(maxWidth: 1024)
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("New Plugin")
        .onAppear { isFocused = true }
    }

    // MARK: - Content Canvas

    private var contentCanvas: some View {
        VStack(spacing: 0) {
            Spacer()

            heroSection
                .padding(.bottom, 32)

            promptSection
                .padding(.bottom, 24)

            categoryGrid

            Spacer()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image("FoundryLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(.primary.opacity(0.7))

            Text("Describe your plugin, Foundry builds it.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                "A warm analog synth with detuned oscillators…",
                text: $prompt,
                axis: .vertical
            )
            .font(.system(size: 14))
            .focused($isFocused)
            .lineLimit(5...10)
            .textFieldStyle(.plain)
            .padding(12)
            .frame(minHeight: 100, alignment: .topLeading)
            .background(Color(.textBackgroundColor).opacity(0.5), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(.separatorColor).opacity(0.6), lineWidth: 1)
            )

            HStack(spacing: 10) {
                modelPicker

                Spacer()

                Button("Generate") { generate() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(promptEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                .disabled(promptEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        HStack(alignment: .top, spacing: 1) {
            ForEach(suggestions) { cat in
                SuggestionCategoryCard(category: cat) { item in
                    prompt = item.fullPrompt
                }
            }
        }
        .background(Color(.separatorColor))
        .overlay(
            Rectangle()
                .strokeBorder(Color(.separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Model Picker

    private var selectedProvider: AgentProvider {
        ModelCatalog.provider(for: selectedModel)
    }

    private var modelPicker: some View {
        Menu {
            ForEach(ModelCatalog.providers) { provider in
                Section {
                    ForEach(provider.models) { model in
                        Button {
                            selectedModel = model
                        } label: {
                            HStack {
                                Text(model.displayName)
                                Text("— \(model.subtitle)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label(provider.name, image: provider.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(selectedProvider.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)

                Text(selectedModel.displayName)
                    .font(.system(size: 12, weight: .medium))

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.controlBackgroundColor), in: .rect(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func generate() {
        guard !promptEmpty else { return }
        let agent = GenerationAgent(providerId: selectedProvider.id) ?? .claudeCode
        appState.push(.generation(config: GenerationConfig(
            prompt: prompt,
            format: .both,
            channelLayout: .stereo,
            presetCount: .five,
            agent: agent,
            model: selectedModel
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
                    .foregroundStyle(.primary)
                    .frame(width: 14, height: 14)

                Text(category.title)
                    .font(FoundryTheme.Fonts.azeretMono(12))
                    .tracking(2.4)
                    .foregroundStyle(.primary)
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.textBackgroundColor))
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
