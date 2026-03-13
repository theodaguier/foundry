import SwiftUI

struct QuickOptionsView: View {
    @Environment(AppState.self) private var appState
    let prompt: String

    @State private var format: FormatOption = .both
    @State private var channelLayout: ChannelLayout = .stereo
    @State private var presetCount: PresetCount = .five

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Prompt recap
                VStack(alignment: .leading, spacing: 6) {
                    Text("Configure generation")
                        .font(.title3)
                        .fontWeight(.medium)

                    Text(prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                // Options
                GlassEffectContainer(spacing: 1) {
                    VStack(spacing: 1) {
                        optionRow("Format", icon: "square.stack.3d.up") {
                            Picker("Format", selection: $format) {
                                ForEach(FormatOption.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        } detail: {
                            Text("Choose which plugin formats Foundry should build and install.")
                        }

                        optionRow("Channels", icon: "speaker.wave.2") {
                            Picker("Channels", selection: $channelLayout) {
                                ForEach(ChannelLayout.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        } detail: {
                            Text("Mono keeps the graph simple. Stereo unlocks width and spatial processing.")
                        }

                        optionRow("Presets", icon: "slider.horizontal.3") {
                            Picker("Presets", selection: $presetCount) {
                                ForEach(PresetCount.allCases, id: \.self) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        } detail: {
                            Text("Presets push the generator toward more intentional, reusable results.")
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .navigationTitle("Options")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") {
                    startGeneration()
                }
                .buttonStyle(.glass)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Generate") {
                    startGeneration()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func optionRow<Content: View, Detail: View>(
        _ label: String,
        icon: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Label(label, systemImage: icon)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                content()
                    .labelsHidden()
            }

            detail()
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
    }

    private func startGeneration() {
        let config = GenerationConfig(
            prompt: prompt,
            format: format,
            channelLayout: channelLayout,
            presetCount: presetCount
        )
        appState.push(.generation(config: config))
    }
}

#Preview {
    NavigationStack {
        QuickOptionsView(prompt: "A warm analog synth with detuned oscillators")
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
