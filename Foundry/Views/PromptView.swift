import SwiftUI

// MARK: - Prompt View (New Plugin — v4 design)

struct PromptView: View {
    @Environment(AppState.self) private var appState
    @State private var prompt = ""
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
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            promptSection
                .padding(.bottom, 24)

            categoryGrid

            Spacer()
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $prompt)
                .font(.system(size: 14))
                .focused($isFocused)
                .frame(height: 100)

            HStack {
                Spacer()
                Button("Generate") { generate() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 8)
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

    private func generate() {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appState.push(.generation(config: GenerationConfig(
            prompt: prompt,
            format: .both,
            channelLayout: .stereo,
            presetCount: .five
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
