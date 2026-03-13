import SwiftUI

struct PromptView: View {
    @Environment(AppState.self) private var appState
    @State private var prompt = ""
    @FocusState private var isFocused: Bool

    private let instrumentExamples = [
        "Warm analog polysynth with detuned oscillators and a low-pass filter",
        "Monophonic bass synth with glide, sub-oscillator, and drive",
        "FM pad synth with slow attack, chorus, and stereo spread",
        "Supersaw lead synth with unison, portamento, and filter envelope",
        "Hammond-style tonewheel organ with drawbars, percussion, and rotary speaker",
        "Farfisa compact organ with vibrato and tone controls",
        "Electric piano with velocity-sensitive tines, tremolo, and chorus",
        "Granular instrument that turns MIDI notes into shimmering cloud textures",
    ]

    private let effectExamples = [
        "Lo-fi tape delay with wow, flutter, and saturation",
        "Shimmer reverb with pitch-shifted tails and freeze",
        "Multi-band distortion with per-band tone controls",
        "Stereo chorus with rate, depth, and feedback controls",
        "Gated reverb with adjustable threshold and decay",
        "Phaser with LFO sync, stereo mode, and resonance",
        "Bitcrusher with sample rate reduction and dithering",
        "Dynamic compressor with sidechain filter and auto-gain",
    ]

    private let utilityExamples = [
        "Stereo utility with width, polarity, and mono fold-down",
        "Transient shaper with simple attack and sustain macros",
        "Analyzer with input trim, output trim, and animated stereo meter",
        "DJ-style isolator with large low, mid, and high bands",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Describe your plugin")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Include the role, sonic character, must-have controls, and how the interface should feel.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Text editor
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $prompt)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)

                    if prompt.isEmpty {
                        Text("A stereo utility for widening vocals with width, mono check, output trim, and a focused interface with 4 large controls...")
                            .font(.body)
                            .foregroundStyle(.quaternary)
                            .allowsHitTesting(false)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }
                .frame(height: 100)
                .padding(10)
                .background(Color(.controlBackgroundColor).opacity(0.3), in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )

                // Tip
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Text("State whether it is an instrument, effect, or utility. Mention the source material, the primary controls, and whether you want a focused or dense interface.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.controlBackgroundColor).opacity(0.3), in: .rect(cornerRadius: 10))

                // Examples
                VStack(alignment: .leading, spacing: 20) {
                    exampleSection("Instruments", icon: "pianokeys", examples: instrumentExamples)
                    exampleSection("Effects", icon: "waveform", examples: effectExamples)
                    exampleSection("Utilities", icon: "dial.low", examples: utilityExamples)
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .navigationTitle("New plugin")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Continue") {
                    appState.push(.quickOptions(prompt: prompt))
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    private func exampleSection(_ title: String, icon: String, examples: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            prompt = example
                        }
                    } label: {
                        Text(example)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color(.controlBackgroundColor).opacity(0.2), in: .rect(cornerRadius: 8))
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
