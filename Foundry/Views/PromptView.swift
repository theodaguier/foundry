import SwiftUI

struct PromptView: View {
    @Environment(AppState.self) private var appState
    @State private var prompt = ""
    @FocusState private var isFocused: Bool

    private let examples = [
        "Warm analog polysynth with detuned oscillators and a low-pass filter",
        "Lo-fi tape delay with wow, flutter, and saturation",
        "Shimmer reverb with pitch-shifted tails and freeze",
        "Multi-band distortion with per-band tone controls",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Describe the sound, behavior, and controls.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(height: 100)
                    .padding(10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))

                // Examples
                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)

                    GlassEffectContainer(spacing: 4) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(examples, id: \.self) { example in
                                Button {
                                    prompt = example
                                } label: {
                                    Text(example)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .navigationTitle("New plugin")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Continue") {
                    appState.push(.quickOptions(prompt: prompt))
                }
                .buttonStyle(.glassProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear {
            isFocused = true
        }
    }
}

#Preview {
    NavigationStack {
        PromptView()
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
